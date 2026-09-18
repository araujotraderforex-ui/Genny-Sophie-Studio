package com.gennysophie.studio
import android.content.Context
import java.io.File
data class EngineStatus(val ready:Boolean,val message:String)
interface ImageEngine{fun status(context:Context):EngineStatus; suspend fun generate(context:Context,request:StudioPrompt):Result<File>}
class LocalImageEngine:ImageEngine{
 override fun status(context:Context):EngineStatus{val dir=File(context.filesDir,"models");val model=dir.listFiles()?.firstOrNull{it.extension in setOf("onnx","ort","bin")};return if(model!=null)EngineStatus(true,"Modelo local encontrado: "+model.name) else EngineStatus(false,"Modelo local ainda não instalado.")}
 override suspend fun generate(context:Context,request:StudioPrompt):Result<File>{return Result.failure(IllegalStateException("Runtime de difusão local não instalado."))}
}