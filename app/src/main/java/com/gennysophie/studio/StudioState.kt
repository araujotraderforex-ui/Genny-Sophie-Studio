package com.gennysophie.studio
import android.content.Context
import java.io.File
data class StudioPrompt(val character:String,val prompt:String,val reference:String?)
object StudioState {
 fun saveHistory(context:Context,item:StudioPrompt){val safe=item.prompt.replace("\n"," ").replace("|","/");context.openFileOutput("history.txt",Context.MODE_APPEND).bufferedWriter().use{it.appendLine(""+java.lang.System.currentTimeMillis()+"|"+item.character+"|"+safe)}}
 fun history(context:Context):List<String>{val f=File(context.filesDir,"history.txt");return if(f.exists())f.readLines().takeLast(30).reversed() else emptyList()}
}