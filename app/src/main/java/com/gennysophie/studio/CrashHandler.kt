package com.gennysophie.studio
import android.content.Context
import java.io.File
object CrashHandler{
 fun install(context:Context){val prior=Thread.getDefaultUncaughtExceptionHandler();Thread.setDefaultUncaughtExceptionHandler{t,e->runCatching{File(context.filesDir,"last_crash.txt").writeText(e.stackTraceToString())};prior?.uncaughtException(t,e)}}
}