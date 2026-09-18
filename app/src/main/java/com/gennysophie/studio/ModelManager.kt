package com.gennysophie.studio

import android.content.Context
import android.net.Uri
import java.io.File

object ModelManager {
    fun importModel(context: Context, uri: Uri): Result<File> {
        return runCatching {
            val dir = File(context.filesDir, "models").apply { mkdirs() }
            val out = File(dir, "image-model.bin")
            val input = context.contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("Não foi possível abrir o modelo selecionado.")
            input.use { source ->
                out.outputStream().use { target ->
                    source.copyTo(target)
                }
            }
            out
        }
    }

    fun clear(context: Context) {
        File(context.filesDir, "models").deleteRecursively()
    }
}