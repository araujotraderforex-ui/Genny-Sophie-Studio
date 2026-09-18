package com.example.local_diffusion

import android.app.*
import android.content.*
import android.os.*
import android.speech.RecognizerIntent
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class GenerationService : Service() {
    companion object { const val CHANNEL_ID = "generation"; const val ID = 4101 }
    private var lock: PowerManager.WakeLock? = null
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Geração de imagens", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Mantém a criação em andamento com a tela apagada"
            setSound(null, null); enableVibration(false)
        })
        lock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "gennysophie:generation").apply { acquire(30 * 60 * 1000L) }
        startForeground(ID, NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setContentTitle("ESTÚDIO G & S")
            .setContentText("A criar imagem em segundo plano…")
            .setSilent(true).setOngoing(true).build())
    }
    override fun onBind(intent: Intent?) = null
    override fun onDestroy() { if (lock?.isHeld == true) lock?.release(); super.onDestroy() }
}

class MainActivity : FlutterActivity() {
    private var speechResult: MethodChannel.Result? = null
    private val generationChannel = "generation"
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "studio/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> result.success(StatFs(filesDir.path).availableBytes)
                "startGenerationService" -> {
                    val i = Intent(this, GenerationService::class.java)
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                    result.success(true)
                }
                "stopGenerationService" -> { stopService(Intent(this, GenerationService::class.java)); result.success(true) }
                "generationFinished" -> {
                    stopService(Intent(this, GenerationService::class.java))
                    val nm = getSystemService(NotificationManager::class.java)
                    nm.createNotificationChannel(NotificationChannel(generationChannel, "Imagens prontas", NotificationManager.IMPORTANCE_DEFAULT))
                    val n = NotificationCompat.Builder(this, generationChannel)
                        .setSmallIcon(android.R.drawable.ic_menu_gallery)
                        .setContentTitle("ESTÚDIO G & S")
                        .setContentText("Imagem pronta para visualização.")
                        .setAutoCancel(true).build()
                    nm.notify(4102, n)
                    result.success(true)
                }
                "recognize" -> {
                    if (speechResult != null) { result.error("BUSY", "Voice recognition already running", null); return@setMethodCallHandler }
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-PT")
                    }
                    try { speechResult = result; startActivityForResult(intent, 7142) }
                    catch (e: Exception) { speechResult = null; result.error("VOICE", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 7142) {
            speechResult?.success(data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull())
            speechResult = null
        }
    }
}
