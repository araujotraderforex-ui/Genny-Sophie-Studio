package com.gennysophie.studio

import android.content.Context
import java.io.File

enum class ModelInstallState { MISSING, DOWNLOADING, VERIFYING, READY, ERROR }
data class ModelInstallStatus(val state:ModelInstallState,val progress:Int=0,val message:String="")

object ModelInstaller {
 private const val MODEL_FILE="sd15-q4_0.gguf"
 private const val MIN_FREE_BYTES=3L*1024L*1024L*1024L
 fun modelDir(context:Context)=File(context.filesDir,"models").apply{mkdirs()}
 fun modelFile(context:Context)=File(modelDir(context),MODEL_FILE)
 fun status(context:Context):ModelInstallStatus {
  val f=modelFile(context)
  return if(!f.isFile||f.length()==0L) ModelInstallStatus(ModelInstallState.MISSING,message="Motor por preparar.")
  else ModelInstallStatus(ModelInstallState.READY,100,"Motor preparado.")
 }
 fun hasEnoughSpace(context:Context)=modelDir(context).usableSpace>=MIN_FREE_BYTES
 fun clearPartial(context:Context){File(modelDir(context),"$MODEL_FILE.part").delete()}
}
