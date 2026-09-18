package com.gennysophie.studio

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

enum class ModelInstallState { MISSING, DOWNLOADING, VERIFYING, READY, ERROR }
data class ModelInstallStatus(val state:ModelInstallState,val progress:Int=0,val message:String="")

object ModelInstaller {
 private const val MODEL_FILE="sd15-q4_0.gguf"
 private const val MIN_FREE_BYTES=3L*1024L*1024L*1024L
 fun modelDir(context:Context)=File(context.filesDir,"models").apply{mkdirs()}
 fun modelFile(context:Context)=File(modelDir(context),MODEL_FILE)
 fun partialFile(context:Context)=File(modelDir(context),"$MODEL_FILE.part")
 fun status(context:Context):ModelInstallStatus {
  val f=modelFile(context)
  return if(!f.isFile||f.length()==0L) ModelInstallStatus(ModelInstallState.MISSING,message="Motor por preparar.")
  else ModelInstallStatus(ModelInstallState.READY,100,"Motor preparado.")
 }
 fun hasEnoughSpace(context:Context)=modelDir(context).usableSpace>=MIN_FREE_BYTES
 fun clearPartial(context:Context){partialFile(context).delete()}

 /** Resumable downloader used by the app; URL/checksum come from the signed model manifest. */
 fun download(context:Context,url:String,onProgress:(Int)->Unit):Result<File> = runCatching {
  require(hasEnoughSpace(context)){"Espaço insuficiente para preparar o motor."}
  val part=partialFile(context); val existing=if(part.exists()) part.length() else 0L
  val conn=(URL(url).openConnection() as HttpURLConnection).apply {
   connectTimeout=15000; readTimeout=30000
   if(existing>0) setRequestProperty("Range","bytes=$existing-")
  }
  conn.connect()
  val append=existing>0 && conn.responseCode==HttpURLConnection.HTTP_PARTIAL
  if(existing>0 && !append) part.delete()
  val start=if(append) existing else 0L
  val total=conn.contentLengthLong.let{if(it>0) it+start else -1L}
  conn.inputStream.use { input ->
   part.outputStream().buffered().use { out ->
    if(append) { out.close(); part.outputStream().buffered() }
   }
  }
  // reopen correctly in append mode for the actual transfer
  conn.disconnect()
  val c2=(URL(url).openConnection() as HttpURLConnection).apply {
   connectTimeout=15000; readTimeout=30000
   if(start>0) setRequestProperty("Range","bytes=$start-")
  }
  c2.connect()
  var done=start
  c2.inputStream.use { input ->
   java.io.FileOutputStream(part,start>0).use { out ->
    val buf=ByteArray(1024*1024)
    while(true){ val n=input.read(buf); if(n<0) break; out.write(buf,0,n); done+=n
     if(total>0) onProgress(((done*100)/total).toInt().coerceIn(0,99))
    }
   }
  }
  c2.disconnect()
  val dest=modelFile(context)
  require(part.renameTo(dest)){"Falha ao finalizar o modelo."}
  onProgress(100); dest
 }
}
