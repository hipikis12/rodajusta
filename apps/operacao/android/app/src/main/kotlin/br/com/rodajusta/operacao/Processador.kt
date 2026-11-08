package br.com.rodajusta.operacao

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Um motor Flutter sem tela, que roda o código Dart de leitura das
 * comandas (o mesmo do app) mesmo com o app fechado: decodifica, faz OCR de
 * cupons em imagem, acha o endereço no mapa e grava no Firebase.
 * Só deve ser chamado na thread principal.
 */
object Processador {
    private var motor: FlutterEngine? = null
    private var canal: MethodChannel? = null
    private var pronto = false
    private var pendenteAviso = false

    fun iniciar(contexto: Context, servico: ServicoImpressora) {
        if (motor != null) return
        val carregador = FlutterInjector.instance().flutterLoader()
        if (!carregador.initialized()) carregador.startInitialization(contexto.applicationContext)
        carregador.ensureInitializationComplete(contexto.applicationContext, null)
        val m = FlutterEngine(contexto.applicationContext) // registra os plugins sozinho
        val c = MethodChannel(m.dartExecutor.binaryMessenger, "rodajusta/fila")
        c.setMethodCallHandler { chamada, resultado ->
            when (chamada.method) {
                "pronto" -> {
                    pronto = true
                    resultado.success(null)
                    if (pendenteAviso) avisar()
                }
                "pendentes" -> resultado.success(servico.fila.pendentes())
                "concluir" -> {
                    val id = chamada.argument<String>("id") ?: ""
                    servico.fila.apagar(id)
                    servico.aoProcessar(
                        chamada.argument<String>("mensagem") ?: "",
                        chamada.argument<List<String>>("novas") ?: emptyList(),
                    )
                    resultado.success(null)
                }
                "falhou" -> {
                    servico.aoFalhar(chamada.argument<String>("mensagem") ?: "Erro ao processar comanda")
                    resultado.success(null)
                }
                else -> resultado.notImplemented()
            }
        }
        motor = m
        canal = c
        m.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(carregador.findAppBundlePath(), "processadorDeComandas"),
        )
    }

    /** Avisa o Dart que há comanda nova na fila. */
    fun avisar() {
        if (!pronto) {
            pendenteAviso = true
            return
        }
        pendenteAviso = false
        canal?.invokeMethod("processar", null)
    }

    fun parar() {
        pronto = false
        canal?.setMethodCallHandler(null)
        canal = null
        motor?.destroy()
        motor = null
    }
}
