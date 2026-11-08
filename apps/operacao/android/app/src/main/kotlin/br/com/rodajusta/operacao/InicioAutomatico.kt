package br.com.rodajusta.operacao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Liga a "impressora" quando o celular reinicia ou o app é atualizado. */
class InicioAutomatico : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intent: Intent) {
        val acao = intent.action ?: return
        if (acao != Intent.ACTION_BOOT_COMPLETED &&
            acao != Intent.ACTION_MY_PACKAGE_REPLACED &&
            acao != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        if (ServicoImpressora.preferencias(contexto).getBoolean("ativo", false)) {
            try {
                ServicoImpressora.iniciar(contexto)
            } catch (_: Exception) {
                // sistema não deixou iniciar agora; abre ao abrir o app
            }
        }
    }
}
