package com.gennysophie.studio
import android.content.Context
import android.net.Uri
import java.io.File
object ModelManager{
 fun importModel(context:Context,uri:Uri):Result<File>=runCatching{val dir=File(context.filesDir,"models").apply{mkdirs()};val out=File(dir,"image-model.bin");context.contentResolver.openInputStream(uri)!!.use{i->out.outputStream().use{o->i.copyTo(o)}};out}
 fun clear(context:Context){File(context.filesDir,"models").deleteRecursively()}
}