package com.gennysophie.studio

import android.content.Context
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File

data class EngineStatus(val ready:Boolean,val message:String)
interface ImageEngine {
    fun status(context:Context):EngineStatus
    suspend fun generate(context:Context,request:StudioPrompt):Result<File>
}

/**
 * Local-only engine boundary. It validates and opens the installed ONNX/ORT model
 * on the phone so invalid model packages fail safely instead of crashing the UI.
 * The diffusion pipeline (tokenizer/CLIP, denoiser scheduler and VAE decoder)
 * must all be present before generation is reported as ready.
 */
class LocalImageEngine:ImageEngine {
    override fun status(context:Context):EngineStatus {
        val dir=File(context.filesDir,"models")
        val required=listOf("text_encoder.onnx","unet.onnx","vae_decoder.onnx")
        val missing=required.filter{!File(dir,it).isFile}
        return if(missing.isEmpty()) EngineStatus(true,"Motor local instalado.")
        else EngineStatus(false,"Pacote local incompleto: "+missing.joinToString())
    }

    fun validateOnnx(context:Context):Result<Unit> = runCatching {
        val dir=File(context.filesDir,"models")
        val s=status(context)
        require(s.ready){s.message}
        val env=OrtEnvironment.getEnvironment()
        listOf("text_encoder.onnx","unet.onnx","vae_decoder.onnx").forEach { name ->
            env.createSession(File(dir,name).absolutePath,OrtSession.SessionOptions()).use { }
        }
    }

    override suspend fun generate(context:Context,request:StudioPrompt):Result<File> = runCatching {
        validateOnnx(context).getOrThrow()
        throw UnsupportedOperationException("Pipeline de difusão ainda não instalado por completo.")
    }
}