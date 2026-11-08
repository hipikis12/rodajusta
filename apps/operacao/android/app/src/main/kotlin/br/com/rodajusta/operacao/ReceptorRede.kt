package br.com.rodajusta.operacao

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import java.io.IOException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket

/**
 * Impressora de rede (RAW, porta 9100): no Windows, adicione uma impressora
 * com "Porta TCP/IP padrão" apontando para o IP do celular; muitos PDVs
 * também aceitam "impressora de rede" direto. O celular se anuncia na rede
 * (mDNS) como impressora para facilitar a descoberta.
 */
class ReceptorRede(
    private val contexto: Context,
    private val porta: Int,
    private val aoReceber: (ByteArray, String) -> Unit,
    private val estado: (String) -> Unit,
) {
    companion object {
        /** IPs do celular na rede local (Wi-Fi ou cabo). */
        fun ipsLocais(): List<String> = try {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<Inet4Address>()
                .filter { it.isSiteLocalAddress }
                .map { it.hostAddress ?: "" }
                .filter { it.isNotEmpty() }
        } catch (_: Exception) {
            emptyList()
        }
    }

    @Volatile private var rodando = false
    @Volatile private var servidor: ServerSocket? = null
    private var nsd: NsdManager? = null
    private var registro: NsdManager.RegistrationListener? = null

    fun iniciar() {
        if (rodando) return
        rodando = true
        Thread({ laco() }, "rj-rede").apply { isDaemon = true }.start()
        anunciar()
    }

    fun parar() {
        rodando = false
        try {
            servidor?.close()
        } catch (_: IOException) {
        }
        try {
            registro?.let { nsd?.unregisterService(it) }
        } catch (_: Exception) {
        }
        registro = null
    }

    private fun laco() {
        while (rodando) {
            try {
                val s = ServerSocket()
                s.reuseAddress = true
                s.bind(InetSocketAddress(porta))
                servidor = s
                estado("aguardando")
                while (rodando) {
                    val cliente = s.accept()
                    Thread({ atender(cliente) }, "rj-rede-conexao").apply { isDaemon = true }.start()
                }
            } catch (e: IOException) {
                if (rodando) {
                    estado("Rede: ${e.message ?: "erro"}; tentando de novo")
                    try {
                        Thread.sleep(3000)
                    } catch (_: InterruptedException) {
                        return
                    }
                }
            }
        }
    }

    private fun atender(cliente: Socket) {
        val acumulador = Acumulador("rede", aoReceber)
        estado("conectada")
        try {
            cliente.use {
                it.soTimeout = 0
                val entrada = it.getInputStream()
                val saida = it.getOutputStream()
                val pedaco = ByteArray(16384)
                while (rodando) {
                    val n = entrada.read(pedaco)
                    if (n < 0) break
                    Recepcao.responderStatus(pedaco, n, saida)
                    acumulador.adicionar(pedaco, n)
                }
            }
        } catch (_: IOException) {
        }
        acumulador.descarregar()
        if (rodando) estado("aguardando")
    }

    private fun anunciar() {
        try {
            val gerenciador = contexto.getSystemService(Context.NSD_SERVICE) as NsdManager
            val info = NsdServiceInfo().apply {
                serviceName = "RodaJusta Impressora"
                serviceType = "_pdl-datastream._tcp"
                port = porta
            }
            val l = object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(serviceInfo: NsdServiceInfo) = Unit
                override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
                override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit
                override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
            }
            gerenciador.registerService(info, NsdManager.PROTOCOL_DNS_SD, l)
            nsd = gerenciador
            registro = l
        } catch (_: Exception) {
            // anúncio é conveniência; por IP continua funcionando
        }
    }
}
