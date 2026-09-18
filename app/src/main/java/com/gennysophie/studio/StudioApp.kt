package com.gennysophie.studio
import android.app.Application
class StudioApp:Application(){override fun onCreate(){super.onCreate();CrashHandler.install(this)}}
