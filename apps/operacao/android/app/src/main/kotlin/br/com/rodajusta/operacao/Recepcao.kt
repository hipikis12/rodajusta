package br.com.rodajusta.operacao

import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.io.OutputStream

/**
 * Junta os pedaços que chegam de uma conexão até formar um trabalho de
 * impressão completo: termina quando a conexão fecha ou quando o PDV fica
 * um instante sem mandar nada (muitos mantêm a conexão aberta entre cupons).
 */
class Acumulador(
    private val origem: String,
    private val aoCompletar: (ByteArray, String) -> Unit,
) {
    companion object {
        const val PAUSA_FIM_MS = 1500L
        private val principal = Handler(Looper.getMainLooper())
    }

    private val buffer = ByteArrayOutputStream()
    private val fim = Runnable { descarregar() }

    fun adicionar(dados: ByteArray, tamanho: Int = dados.size) {
        synchronized(buffer) { buffer.write(dados, 0, tamanho) }
        principal.removeCallbacks(fim)
        principal.postDelayed(fim, PAUSA_FIM_MS)
    }

    fun descarregar() {
        principal.removeCallbacks(fim)
        val bytes = synchronized(buffer) {
            val b = buffer.toByteArray()
            buffer.reset()
            b
        }
        if (Recepcao.temConteudo(bytes)) aoCompletar(bytes, origem)
    }
}

object Recepcao {
    /**
     * Trabalhos só com comandos (consultas de status que alguns PDVs fazem
     * a cada poucos segundos) não viram comanda.
     */
    fun temConteudo(b: ByteArray): Boolean {
        if (b.size >= 256) return true // imagem raster ou cupom grande
        var texto = 0
        for (x in b) {
            val v = x.toInt() and 0xFF
            if (v in 0x30..0x39 || v in 0x41..0x5A || v in 0x61..0x7A || v >= 0xC0) texto++
        }
        return texto >= 12
    }

    /**
     * Responde às consultas de status como uma impressora de verdade:
     * alguns PDVs não imprimem se a impressora não responde "estou OK".
     */
    fun responderStatus(b: ByteArray, n: Int, saida: OutputStream?) {
        if (saida == null) return
        val r = respostas(b, n)
        if (r.isEmpty()) return
        try {
            saida.write(r)
            saida.flush()
        } catch (_: Exception) {
        }
    }

    fun respostas(b: ByteArray, n: Int = b.size): ByteArray {
        val r = ByteArrayOutputStream()
        var i = 0
        fun at(k: Int) = if (k < n) b[k].toInt() and 0xFF else -1
        while (i < n) {
            val c = at(i)
            val c1 = at(i + 1)
            val c2 = at(i + 2)
            when {
                c == 0x10 && c1 == 0x04 && c2 >= 0 -> { r.write(0x12); i += 3 } // DLE EOT n
                c == 0x1D && c1 == 0x49 && c2 >= 0 -> { // GS I n
                    when (c2) {
                        1, 49 -> r.write(0x20)
                        2, 50 -> r.write(0x02)
                        3, 51 -> r.write(0x01)
                        in 65..69 -> { r.write(0x5F); r.write("RodaJusta".toByteArray()); r.write(0) }
                    }
                    i += 3
                }
                c == 0x1D && c1 == 0x72 && c2 >= 0 -> { r.write(0x00); i += 3 } // GS r n
                c == 0x1B && (c1 == 0x76 || c1 == 0x75) -> { r.write(0x00); i += 2 } // ESC v / ESC u
                else -> i++
            }
        }
        return r.toByteArray()
    }
}
