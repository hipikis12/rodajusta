package br.com.rodajusta.operacao

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.UUID

/**
 * O celular se apresenta como impressora Bluetooth (perfil SPP, o mesmo das
 * térmicas). O PDV "imprime" aqui; quando os dados param de chegar por um
 * instante, a comanda está completa e vai para o Flutter como bytes.
 * Opcionalmente repassa os mesmos bytes para a impressora real da loja.
 */
class ImpressoraVirtual(private val contexto: Context) {

    companion object {
        val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        const val PAUSA_FIM_MS = 700L
    }

    var saida: EventChannel.EventSink? = null

    private val principal = Handler(Looper.getMainLooper())
    private val buffer = ByteArrayOutputStream()
    @Volatile private var rodando = false
    @Volatile private var servidor: BluetoothServerSocket? = null
    @Volatile private var repassarPara: String? = null

    private val adaptador: BluetoothAdapter?
        get() = (contexto.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter

    private val descarregar = Runnable {
        val bytes = synchronized(buffer) {
            val b = buffer.toByteArray()
            buffer.reset()
            b
        }
        if (bytes.isNotEmpty()) entregar(bytes)
    }

    fun iniciar(repassar: String?) {
        repassarPara = repassar
        if (rodando) return
        val a = adaptador ?: throw IllegalStateException("Este celular não tem Bluetooth.")
        if (!a.isEnabled) throw IllegalStateException("Ligue o Bluetooth.")
        rodando = true
        Thread { laco(a) }.apply {
            isDaemon = true
            name = "impressora-virtual"
            start()
        }
    }

    fun parar() {
        rodando = false
        try {
            servidor?.close()
        } catch (_: IOException) {
        }
        emitir("parada")
    }

    @SuppressLint("MissingPermission")
    fun pareadas(): List<Map<String, String>> =
        adaptador?.bondedDevices?.map { mapOf("nome" to (it.name ?: it.address), "endereco" to it.address) }
            ?: emptyList()

    @SuppressLint("MissingPermission")
    private fun laco(a: BluetoothAdapter) {
        while (rodando) {
            try {
                val s = a.listenUsingRfcommWithServiceRecord("RodaJusta", SPP)
                servidor = s
                emitir("aguardando")
                val socket = s.accept() // espera o PDV conectar
                s.close()
                emitir("conectada")
                socket.use { lerComandas(it) }
            } catch (e: IOException) {
                if (rodando) {
                    emitir("Erro no Bluetooth: ${e.message}")
                    Thread.sleep(2000)
                }
            }
        }
    }

    private fun lerComandas(socket: BluetoothSocket) {
        val entrada = socket.inputStream
        val pedaco = ByteArray(4096)
        try {
            while (rodando) {
                val n = entrada.read(pedaco)
                if (n < 0) break
                synchronized(buffer) { buffer.write(pedaco, 0, n) }
                // a comanda termina quando o PDV para de mandar por um instante
                principal.removeCallbacks(descarregar)
                principal.postDelayed(descarregar, PAUSA_FIM_MS)
            }
        } catch (_: IOException) {
            // PDV desconectou: comum depois de cada impressão
        }
        principal.removeCallbacks(descarregar)
        principal.post(descarregar)
    }

    /** Roda na thread principal. */
    private fun entregar(bytes: ByteArray) {
        saida?.success(bytes)
        repassarPara?.let { mac -> Thread { repassar(mac, bytes) }.start() }
    }

    @SuppressLint("MissingPermission")
    private fun repassar(mac: String, bytes: ByteArray) {
        try {
            val a = adaptador ?: return
            a.cancelDiscovery()
            a.getRemoteDevice(mac).createRfcommSocketToServiceRecord(SPP).use { s ->
                s.connect()
                s.outputStream.write(bytes)
                s.outputStream.flush()
                Thread.sleep(300)
            }
        } catch (e: Exception) {
            emitir("Não consegui repassar para a impressora: ${e.message}")
        }
    }

    private fun emitir(estado: String) {
        principal.post { saida?.success(estado) }
    }
}
