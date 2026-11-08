package br.com.rodajusta.operacao

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var ouvinte: ((String) -> Unit)? = null
    private var aguardandoPermissao: Pair<MethodCall, MethodChannel.Result>? = null

    private val adaptador: BluetoothAdapter?
        get() = getSystemService(BluetoothManager::class.java)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        criarCanaisDeNotificacao()
        val mensageiro = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(mensageiro, "rodajusta/impressora/estado").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val o: (String) -> Unit = { events?.success(it) }
                    ouvinte = o
                    ServicoImpressora.ouvintes.add(o)
                    events?.success(ServicoImpressora.estadoAtual)
                }

                override fun onCancel(arguments: Any?) {
                    ouvinte?.let { ServicoImpressora.ouvintes.remove(it) }
                    ouvinte = null
                }
            },
        )

        MethodChannel(mensageiro, "rodajusta/impressora").setMethodCallHandler { call, result ->
            try {
                tratar(call, result)
            } catch (e: Exception) {
                result.error("erro", e.message, null)
            }
        }
    }

    private fun tratar(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configurar" -> {
                val ativo = call.argument<Boolean>("ativo") ?: false
                val usaBluetooth = (call.argument<Boolean>("bluetooth") ?: true) || (call.argument<Boolean>("ble") ?: true)
                if (ativo && usaBluetooth && !temPermissoesBluetooth()) {
                    aguardandoPermissao = call to result
                    pedirPermissoesBluetooth()
                    return
                }
                configurar(call)
                result.success(ServicoImpressora.estadoAtual)
            }
            "estado" -> result.success(ServicoImpressora.estadoAtual)
            "pareadas" -> result.success(if (temPermissoesBluetooth()) pareadas() else emptyList<Map<String, String>>())
            "ficarVisivel" -> {
                if (!temPermissoesBluetooth()) {
                    pedirPermissoesBluetooth()
                } else {
                    startActivity(
                        Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                            .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300),
                    )
                }
                result.success(null)
            }
            "ipLocal" -> result.success(ReceptorRede.ipsLocais().firstOrNull())
            "nomeBluetooth" -> result.success(if (temPermissoesBluetooth()) nomeBluetooth() else null)
            "renomearBluetooth" -> {
                result.success(if (temPermissoesBluetooth()) renomearBluetooth(call.argument<String>("nome")) else false)
            }
            "bateriaLiberada" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName))
            }
            "liberarBateria" -> {
                @SuppressLint("BatteryLife")
                val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                try {
                    startActivity(i)
                } catch (_: Exception) {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun configurar(call: MethodCall) {
        val ativo = call.argument<Boolean>("ativo") ?: false
        ServicoImpressora.preferencias(this).edit()
            .putBoolean("ativo", ativo)
            .putBoolean("bluetooth", call.argument<Boolean>("bluetooth") ?: true)
            .putBoolean("ble", call.argument<Boolean>("ble") ?: true)
            .putBoolean("rede", call.argument<Boolean>("rede") ?: true)
            .putInt("porta", call.argument<Int>("porta") ?: 9100)
            .putString("repassarPara", call.argument<String>("repassarPara"))
            .apply()
        if (ativo) ServicoImpressora.iniciar(this) else ServicoImpressora.parar(this)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 42) return
        val (call, result) = aguardandoPermissao ?: return
        aguardandoPermissao = null
        if (temPermissoesBluetooth()) {
            configurar(call)
            result.success(ServicoImpressora.estadoAtual)
        } else {
            result.error("permissao", "Sem permissão de Bluetooth. Ative em Configurações > Apps > RodaJusta.", null)
        }
    }

    private fun temPermissoesBluetooth(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED)

    private fun pedirPermissoesBluetooth() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE),
                42,
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun pareadas(): List<Map<String, String>> =
        adaptador?.bondedDevices?.map { mapOf("nome" to (it.name ?: it.address), "endereco" to it.address) } ?: emptyList()

    @SuppressLint("MissingPermission")
    private fun nomeBluetooth(): String? = adaptador?.name

    /**
     * Alguns PDVs só listam aparelhos com cara de impressora no nome.
     * Guarda o nome original para poder voltar.
     */
    @SuppressLint("MissingPermission")
    private fun renomearBluetooth(nome: String?): Boolean {
        val a = adaptador ?: return false
        val p = ServicoImpressora.preferencias(this)
        return if (nome == null) {
            val original = p.getString("nomeOriginal", null) ?: return false
            @Suppress("DEPRECATION")
            a.setName(original).also { p.edit().remove("nomeOriginal").apply() }
        } else {
            if (!p.contains("nomeOriginal")) p.edit().putString("nomeOriginal", a.name).apply()
            @Suppress("DEPRECATION")
            a.setName(nome)
        }
    }

    /** Ofertas em canal de alta prioridade, com som; avisos gerais à parte. */
    private fun criarCanaisDeNotificacao() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val gerenciador = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        gerenciador.createNotificationChannel(
            NotificationChannel("ofertas", "Ofertas de entrega", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Novas entregas para aceitar"
                enableVibration(true)
            },
        )
        gerenciador.createNotificationChannel(
            NotificationChannel("geral", "Avisos", NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    override fun onDestroy() {
        ouvinte?.let { ServicoImpressora.ouvintes.remove(it) }
        super.onDestroy()
    }
}
