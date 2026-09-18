package com.gennysophie.studio
import android.content.Context
import java.io.File
object EngineGuard{
 fun validate(context:Context):Result<File> = runCatching {
  val dir=File(context.filesDir,"models")
  val model=dir.listFiles()?.firstOrNull{it.isFile&&it.length()>1024*1024} ?: error("Modelo local não instalado.")
  require(model.length()<6L*1024*1024*1024){"Modelo excede o limite de segurança."}
  model
 }
 fun freeBytes(context:Context)=context.filesDir.usableSpace
}