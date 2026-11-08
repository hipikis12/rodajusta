package br.com.rodajusta.operacao

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import java.util.concurrent.CopyOnWriteArraySet

/**
 * Serviço em primeiro plano que fica "fingindo ser impressora" o tempo
 * todo, com o app aberto ou fechado: Bluetooth clássico, BLE e rede.
 * Começa sozinho quando o celular liga, se estiver ativado.
 */
class ServicoImpressora : Service() {

    companion object {
        private const val CANAL_SERVICO = "impressora"
        private const val CANAL_COMANDAS = "comandas"
        private const val ID_SERVICO = 7001
        private var idNotificacao = 7100

        val ouvintes = CopyOnWriteArraySet<(String) -> Unit>()

        @Volatile var estadoAtual = "parada"
            private set

        private val principal = Handler(Looper.getMainLooper())

        fun publicar(estado: String) {
            estadoAtual = estado
            principal.post { ouvintes.forEach { it(estado) } }
        }

        fun preferencias(ctx: Context): SharedPreferences =
            ctx.getSharedPreferences("impressora", Context.MODE_PRIVATE)

        fun iniciar(ctx: Context) {
            val i = Intent(ctx, ServicoImpressora::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun parar(ctx: Context) {
            ctx.stopService(Intent(ctx, ServicoImpressora::class.java))
        }
    }

    lateinit var fila: Fila
        private set
    private var bluetooth: ReceptorBluetooth? = null
    private var ble: ReceptorBle? = null
    private var rede: ReceptorRede? = null
    private var travaCpu: PowerManager.WakeLock? = null
    private var travaWifi: WifiManager.WifiLock? = null
    private var recebidasHoje = 0
    private var ultima = ""

    private val adaptador get() = getSystemService(BluetoothManager::class.java)?.adapter
    private val notificacoes get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        fila = Fila(this)
        criarCanais()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notificacao = notificacaoServico("Iniciando…")
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID_SERVICO, notificacao, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(ID_SERVICO, notificacao)
        }
        val p = preferencias(this)
        if (!p.getBoolean("ativo", false)) {
            stopSelf()
            return START_NOT_STICKY
        }
        reiniciarReceptores(p)
        travar()
        Processador.iniciar(this, this)
        if (fila.quantidade() > 0) Processador.avisar()
        atualizarNotificacao()
        return START_STICKY
    }

    private fun reiniciarReceptores(p: SharedPreferences) {
        pararReceptores()
        val a = adaptador
        if (p.getBoolean("bluetooth", true) && a != null) {
            bluetooth = ReceptorBluetooth(a, ::aoReceber, ::aoMudarEstado).also { it.iniciar() }
        }
        if (p.getBoolean("ble", true) && a != null) {
            ble = ReceptorBle(this, ::aoReceber, ::aoMudarEstado).also {
                try {
                    it.iniciar()
                } catch (e: SecurityException) {
                    aoMudarEstado("BLE sem permissão")
                }
            }
        }
        if (p.getBoolean("rede", true)) {
            rede = ReceptorRede(this, p.getInt("porta", 9100), ::aoReceber, ::aoMudarEstado).also { it.iniciar() }
        }
    }

    private fun pararReceptores() {
        bluetooth?.parar()
        ble?.parar()
        rede?.parar()
        bluetooth = null
        ble = null
        rede = null
    }

    /** Chamado pelos receptores (qualquer thread) quando um cupom termina. */
    private fun aoReceber(bytes: ByteArray, origem: String) {
        fila.salvar(bytes, origem)
        preferencias(this).getString("repassarPara", null)?.takeIf { it.isNotBlank() }?.let {
            Repassador.repassar(adaptador, it, bytes, ::aoMudarEstado)
        }
        principal.post {
            Processador.iniciar(this, this)
            Processador.avisar()
        }
        publicar("Comanda recebida (${nomeOrigem(origem)}), lendo…")
    }

    private fun aoMudarEstado(estado: String) {
        publicar(estado)
        principal.post { atualizarNotificacao() }
    }

    /** Dart terminou um trabalho. */
    fun aoProcessar(mensagem: String, novas: List<String>) {
        recebidasHoje += novas.size
        if (mensagem.isNotEmpty()) ultima = mensagem
        publicar(mensagem)
        atualizarNotificacao()
        for (d in novas) avisarComanda(d)
    }

    fun aoFalhar(mensagem: String) {
        ultima = mensagem
        publicar(mensagem)
        atualizarNotificacao()
    }

    override fun onDestroy() {
        pararReceptores()
        Processador.parar()
        destravar()
        publicar("parada")
        super.onDestroy()
    }

    // ---------------------------------------------------------- notificações

    private fun criarCanais() {
        if (Build.VERSION.SDK_INT < 26) return
        val g = notificacoes
        g.createNotificationChannel(
            NotificationChannel(CANAL_SERVICO, "Impressora RodaJusta", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Mostra que o celular está pronto para receber comandas"
            },
        )
        g.createNotificationChannel(
            NotificationChannel(CANAL_COMANDAS, "Comandas recebidas", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Aviso a cada comanda que chega do PDV"
            },
        )
    }

    private fun abrirApp(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    @Suppress("DEPRECATION")
    private fun construtor(canal: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, canal) else Notification.Builder(this)

    private fun resumoCanais(): String {
        val p = preferencias(this)
        val partes = mutableListOf<String>()
        if (bluetooth != null) partes.add("Bluetooth")
        if (ble != null) partes.add("BLE")
        if (rede != null) {
            val ip = ReceptorRede.ipsLocais().firstOrNull()
            partes.add(if (ip != null) "Wi-Fi $ip:${p.getInt("porta", 9100)}" else "Wi-Fi (sem rede)")
        }
        return partes.joinToString(" · ")
    }

    private fun notificacaoServico(texto: String): Notification =
        construtor(CANAL_SERVICO)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Recebendo comandas")
            .setContentText(texto)
            .setOngoing(true)
            .setContentIntent(abrirApp())
            .build()

    private fun atualizarNotificacao() {
        val linha = buildString {
            append(resumoCanais())
            if (recebidasHoje > 0) append(" · $recebidasHoje hoje")
            if (ultima.isNotEmpty()) append("\n$ultima")
        }
        val n = construtor(CANAL_SERVICO)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Recebendo comandas")
            .setContentText(linha.lineSequence().first())
            .setStyle(Notification.BigTextStyle().bigText(linha))
            .setOngoing(true)
            .setContentIntent(abrirApp())
            .build()
        notificacoes.notify(ID_SERVICO, n)
    }

    private fun avisarComanda(descricao: String) {
        val n = construtor(CANAL_COMANDAS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Nova comanda")
            .setContentText(descricao)
            .setAutoCancel(true)
            .setContentIntent(abrirApp())
            .build()
        notificacoes.notify(idNotificacao++, n)
    }

    private fun nomeOrigem(o: String) = when (o) {
        "bluetooth" -> "Bluetooth"
        "ble" -> "BLE"
        "rede" -> "Wi-Fi"
        else -> o
    }

    // ---------------------------------------------------------- energia

    @SuppressLint("WakelockTimeout")
    private fun travar() {
        if (travaCpu == null) {
            travaCpu = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "rodajusta:impressora")
                .apply { acquire() }
        }
        if (travaWifi == null && preferencias(this).getBoolean("rede", true)) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            travaWifi = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "rodajusta:rede").apply { acquire() }
        }
    }

    private fun destravar() {
        travaCpu?.takeIf { it.isHeld }?.release()
        travaWifi?.takeIf { it.isHeld }?.release()
        travaCpu = null
        travaWifi = null
    }
}
