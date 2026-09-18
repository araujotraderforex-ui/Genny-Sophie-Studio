package com.example.local_diffusion

import android.content.Intent
import android.os.StatFs
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var speechResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "studio/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> result.success(StatFs(filesDir.path).availableBytes)
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
