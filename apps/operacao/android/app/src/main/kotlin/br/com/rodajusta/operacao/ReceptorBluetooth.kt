package br.com.rodajusta.operacao

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import java.io.IOException
import java.util.UUID

/**
 * Bluetooth clássico, perfil SPP: o mesmo das impressoras térmicas. Serve
 * para PDVs no Windows (porta COM do Bluetooth) e apps Android que imprimem
 * em impressora pareada. Aceita várias conexões, uma por PDV.
 */
class ReceptorBluetooth(
    private val adaptador: BluetoothAdapter,
    private val aoReceber: (ByteArray, String) -> Unit,
    private val estado: (String) -> Unit,
) {
    companion object {
        val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    @Volatile private var rodando = false
    @Volatile private var servidor: BluetoothServerSocket? = null

    fun iniciar() {
        if (rodando) return
        rodando = true
        Thread({ laco() }, "rj-bluetooth").apply { isDaemon = true }.start()
    }

    fun parar() {
        rodando = false
        try {
            servidor?.close()
        } catch (_: IOException) {
        }
    }

    @SuppressLint("MissingPermission")
    private fun laco() {
        while (rodando) {
            try {
                if (!adaptador.isEnabled) {
                    estado("Bluetooth desligado")
                    Thread.sleep(5000)
                    continue
                }
                // "insecure" aceita também PDVs que conectam sem autenticar
                val s = adaptador.listenUsingInsecureRfcommWithServiceRecord("RodaJusta Impressora", SPP)
                servidor = s
                estado("aguardando")
                while (rodando) {
                    val socket = s.accept()
                    Thread({ atender(socket) }, "rj-bt-conexao").apply { isDaemon = true }.start()
                }
            } catch (e: IOException) {
                if (rodando) {
                    estado("Bluetooth: ${e.message ?: "erro"}; tentando de novo")
                    Thread.sleep(3000)
                }
            } catch (_: InterruptedException) {
                return
            }
        }
    }

    private fun atender(socket: BluetoothSocket) {
        val acumulador = Acumulador("bluetooth", aoReceber)
        estado("conectada")
        try {
            socket.use {
                val entrada = it.inputStream
                val saida = it.outputStream
                val pedaco = ByteArray(8192)
                while (rodando) {
                    val n = entrada.read(pedaco)
                    if (n < 0) break
                    Recepcao.responderStatus(pedaco, n, saida)
                    acumulador.adicionar(pedaco, n)
                }
            }
        } catch (_: IOException) {
            // o PDV desconecta depois de cada cupom: normal
        }
        acumulador.descarregar()
        if (rodando) estado("aguardando")
    }
}
