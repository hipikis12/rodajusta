package br.com.rodajusta.operacao

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Bluetooth de baixo consumo (BLE): o celular se anuncia com os serviços
 * que as impressoras térmicas BLE mais comuns usam, e o PDV/app escreve o
 * cupom na característica de escrita.
 */
class ReceptorBle(
    private val contexto: Context,
    private val aoReceber: (ByteArray, String) -> Unit,
    private val estado: (String) -> Unit,
) {
    private class Perfil(val servico: String, val escrita: String, val aviso: String?)

    companion object {
        private fun uuid16(x: String) = "0000$x-0000-1000-8000-00805F9B34FB"
        private val CCCD: UUID = UUID.fromString(uuid16("2902"))

        // serviços/características usados por impressoras térmicas BLE populares
        private val PERFIS = listOf(
            Perfil(uuid16("18F0"), uuid16("2AF1"), uuid16("2AF0")),
            Perfil("E7810A71-73AE-499D-8C15-FAA9AEF0C3F2", "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F", null),
            Perfil("49535343-FE7D-4AE5-8FA9-9FAFD205E455", "49535343-8841-43F4-A8D4-ECBE34729BB3", "49535343-1E4D-4BD9-BA61-23C647249616"),
            Perfil(uuid16("FFE0"), uuid16("FFE1"), null),
            Perfil(uuid16("FF00"), uuid16("FF02"), uuid16("FF01")),
        )
    }

    private val gerenciador = contexto.getSystemService(BluetoothManager::class.java)
    private var servidor: BluetoothGattServer? = null
    private val acumuladores = ConcurrentHashMap<String, Acumulador>()
    private val preparados = ConcurrentHashMap<String, ByteArrayOutputStream>()
    private val avisos = mutableListOf<BluetoothGattCharacteristic>()
    private val aAdicionar = ArrayDeque<BluetoothGattService>()
    @Volatile private var comNome = true

    private fun acumulador(d: BluetoothDevice) =
        acumuladores.getOrPut(d.address) { Acumulador("ble", aoReceber) }

    private val anuncio = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) = estado("aguardando")
        override fun onStartFailure(errorCode: Int) {
            when {
                errorCode == ADVERTISE_FAILED_ALREADY_STARTED -> Unit
                errorCode == ADVERTISE_FAILED_DATA_TOO_LARGE && comNome -> {
                    comNome = false // nome do celular muito longo: anuncia sem ele
                    anunciar()
                }
                else -> estado("BLE: não consegui anunciar (erro $errorCode)")
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun iniciar() {
        if (servidor != null) return
        val adaptador = gerenciador?.adapter
        if (adaptador == null || !adaptador.isEnabled) {
            estado("Bluetooth desligado")
            return
        }
        servidor = gerenciador?.openGattServer(contexto, callback) ?: run {
            estado("BLE indisponível neste celular")
            return
        }
        for (p in PERFIS) {
            val s = BluetoothGattService(UUID.fromString(p.servico), BluetoothGattService.SERVICE_TYPE_PRIMARY)
            val combinada = p.aviso == null
            val escrita = BluetoothGattCharacteristic(
                UUID.fromString(p.escrita),
                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_READ or
                    (if (combinada) BluetoothGattCharacteristic.PROPERTY_NOTIFY else 0),
                BluetoothGattCharacteristic.PERMISSION_WRITE or BluetoothGattCharacteristic.PERMISSION_READ,
            )
            if (combinada) {
                escrita.addDescriptor(cccd())
                avisos.add(escrita)
            }
            s.addCharacteristic(escrita)
            p.aviso?.let {
                val aviso = BluetoothGattCharacteristic(
                    UUID.fromString(it),
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
                    BluetoothGattCharacteristic.PERMISSION_READ,
                )
                aviso.addDescriptor(cccd())
                s.addCharacteristic(aviso)
                avisos.add(aviso)
            }
            aAdicionar.addLast(s)
        }
        // os serviços precisam ser adicionados um de cada vez
        servidor?.addService(aAdicionar.removeFirst())
    }

    private fun cccd() = BluetoothGattDescriptor(
        CCCD,
        BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
    )

    @SuppressLint("MissingPermission")
    private fun anunciar() {
        val anunciante = gerenciador?.adapter?.bluetoothLeAdvertiser ?: run {
            estado("Este celular não anuncia BLE")
            return
        }
        val config = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setConnectable(true)
            .setTimeout(0)
            .build()
        val dados = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid.fromString(PERFIS.first().servico))
            .build()
        val resposta = AdvertiseData.Builder().setIncludeDeviceName(comNome).build()
        anunciante.startAdvertising(config, dados, resposta, anuncio)
    }

    @SuppressLint("MissingPermission")
    fun parar() {
        try {
            gerenciador?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(anuncio)
        } catch (_: Exception) {
        }
        acumuladores.values.forEach { it.descarregar() }
        acumuladores.clear()
        try {
            servidor?.close()
        } catch (_: Exception) {
        }
        servidor = null
        avisos.clear()
        aAdicionar.clear()
    }

    @SuppressLint("MissingPermission")
    private fun responder(d: BluetoothDevice, dados: ByteArray, n: Int) {
        val r = Recepcao.respostas(dados, n)
        if (r.isEmpty()) return
        val s = servidor ?: return
        for (c in avisos) {
            try {
                if (Build.VERSION.SDK_INT >= 33) {
                    s.notifyCharacteristicChanged(d, c, false, r)
                } else {
                    @Suppress("DEPRECATION")
                    c.value = r
                    @Suppress("DEPRECATION")
                    s.notifyCharacteristicChanged(d, c, false)
                }
            } catch (_: Exception) {
            }
        }
    }

    private val callback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            val proximo = aAdicionar.removeFirstOrNull()
            if (proximo != null) servidor?.addService(proximo) else anunciar()
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                estado("conectada")
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                acumuladores.remove(device.address)?.descarregar()
                estado("aguardando")
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            val v = value ?: ByteArray(0)
            if (preparedWrite) {
                preparados.getOrPut(device.address) { ByteArrayOutputStream() }.write(v)
            } else {
                responder(device, v, v.size)
                acumulador(device).adicionar(v)
            }
            if (responseNeeded) servidor?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, v)
        }

        @SuppressLint("MissingPermission")
        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
            val b = preparados.remove(device.address)
            if (execute && b != null) {
                val v = b.toByteArray()
                responder(device, v, v.size)
                acumulador(device).adicionar(v)
            }
            servidor?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?,
        ) {
            if (responseNeeded) servidor?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic,
        ) {
            servidor?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, byteArrayOf(0))
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor,
        ) {
            servidor?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
        }
    }
}
