package br.com.rodajusta.operacao

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Manda o mesmo cupom para a impressora de verdade da loja, para o papel
 * continuar saindo. Destino: endereço Bluetooth (AA:BB:CC:DD:EE:FF) ou
 * impressora de rede (192.168.0.50 ou 192.168.0.50:9100).
 */
object Repassador {
    fun repassar(adaptador: BluetoothAdapter?, destino: String, bytes: ByteArray, erro: (String) -> Unit) {
        Thread({
            try {
                if (Regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$").matches(destino)) {
                    porBluetooth(adaptador, destino, bytes)
                } else {
                    val partes = destino.split(":")
                    val porta = partes.getOrNull(1)?.toIntOrNull() ?: 9100
                    Socket().use {
                        it.connect(InetSocketAddress(partes[0], porta), 4000)
                        it.getOutputStream().write(bytes)
                        it.getOutputStream().flush()
                    }
                }
            } catch (e: Exception) {
                erro("Não consegui repassar para a impressora ($destino): ${e.message}")
            }
        }, "rj-repasse").start()
    }

    @SuppressLint("MissingPermission")
    private fun porBluetooth(adaptador: BluetoothAdapter?, mac: String, bytes: ByteArray) {
        val a = adaptador ?: throw IllegalStateException("sem Bluetooth")
        a.cancelDiscovery()
        a.getRemoteDevice(mac).createRfcommSocketToServiceRecord(ReceptorBluetooth.SPP).use { s ->
            s.connect()
            s.outputStream.write(bytes)
            s.outputStream.flush()
            Thread.sleep(400) // dá tempo de a impressora ler antes de fechar
        }
    }
}
