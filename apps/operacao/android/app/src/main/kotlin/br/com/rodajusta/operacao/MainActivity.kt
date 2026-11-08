package br.com.rodajusta.operacao

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private lateinit var impressora: ImpressoraVirtual

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        criarCanaisDeNotificacao()
        impressora = ImpressoraVirtual(applicationContext)
        val mensageiro = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(mensageiro, "rodajusta/impressora/comandas").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    impressora.saida = events
                }

                override fun onCancel(arguments: Any?) {
                    impressora.saida = null
                }
            },
        )

        MethodChannel(mensageiro, "rodajusta/impressora").setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciar" -> {
                    if (!temPermissaoBluetooth()) {
                        pedirPermissaoBluetooth()
                        result.error("permissao", "Permita o acesso ao Bluetooth e tente de novo.", null)
                    } else {
                        try {
                            impressora.iniciar(call.argument<String>("repassarPara"))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("bluetooth", e.message, null)
                        }
                    }
                }
                "parar" -> {
                    impressora.parar()
                    result.success(null)
                }
                "ficarVisivel" -> {
                    if (!temPermissaoBluetooth()) {
                        pedirPermissaoBluetooth()
                        result.success(null)
                    } else {
                        startActivity(
                            Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                                .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300),
                        )
                        result.success(null)
                    }
                }
                "pareadas" -> {
                    if (!temPermissaoBluetooth()) {
                        pedirPermissaoBluetooth()
                        result.success(emptyList<Map<String, String>>())
                    } else {
                        result.success(impressora.pareadas())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::impressora.isInitialized) impressora.parar()
        super.onDestroy()
    }

    private fun temPermissaoBluetooth(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun pedirPermissaoBluetooth() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(
                arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE),
                42,
            )
        }
    }

    /** Ofertas em canal de alta prioridade, com som; avisos gerais à parte. */
    private fun criarCanaisDeNotificacao() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val gerenciador = getSystemService(NotificationManager::class.java)
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
}
