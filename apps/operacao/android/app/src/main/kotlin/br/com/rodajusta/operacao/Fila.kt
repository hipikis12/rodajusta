package br.com.rodajusta.operacao

import android.content.Context
import java.io.File
import kotlin.random.Random

/**
 * Comandas recebidas ficam gravadas em disco até serem processadas: se o
 * celular estiver sem internet ou o app for fechado, nada se perde.
 */
class Fila(contexto: Context) {
    private val pasta = File(contexto.filesDir, "comandas").apply { mkdirs() }

    fun salvar(bytes: ByteArray, origem: String): String {
        limpar()
        val id = "${System.currentTimeMillis()}_${origem}_${Random.nextInt(1000, 9999)}"
        val tmp = File(pasta, "$id.tmp")
        tmp.writeBytes(bytes)
        tmp.renameTo(File(pasta, "$id.bin"))
        return id
    }

    /** As mais antigas primeiro. */
    fun pendentes(limite: Int = 10): List<Map<String, Any>> =
        (pasta.listFiles { f -> f.name.endsWith(".bin") } ?: emptyArray())
            .sortedBy { it.name }
            .take(limite)
            .map { f ->
                val id = f.name.removeSuffix(".bin")
                mapOf(
                    "id" to id,
                    "origem" to id.split("_").getOrElse(1) { "" },
                    "recebidoEm" to f.lastModified(),
                    "bytes" to f.readBytes(),
                )
            }

    fun quantidade(): Int = pasta.listFiles { f -> f.name.endsWith(".bin") }?.size ?: 0

    fun apagar(id: String) {
        File(pasta, "$id.bin").delete()
    }

    /** Guarda no máximo 7 dias / 300 trabalhos. */
    private fun limpar() {
        val arquivos = pasta.listFiles() ?: return
        val limite = System.currentTimeMillis() - 7L * 24 * 3600 * 1000
        arquivos.filter { it.lastModified() < limite }.forEach { it.delete() }
        val sobra = arquivos.filter { it.exists() }.sortedBy { it.name }
        if (sobra.size > 300) sobra.take(sobra.size - 300).forEach { it.delete() }
    }
}
