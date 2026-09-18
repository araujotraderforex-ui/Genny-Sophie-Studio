package com.gennysophie.studio

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.widget.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import java.util.Locale

class MainActivity : AppCompatActivity() {
    private lateinit var prompt: EditText
    private lateinit var status: TextView
    private var referenceUri: String? = null

    private val speech = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val text = r.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            if (!text.isNullOrBlank()) prompt.setText(text)
        }
    }
    private val image = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        referenceUri = uri?.toString()
        status.text = if (uri != null) "Referência carregada." else "Nenhuma referência selecionada."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState); setContentView(R.layout.activity_main)
        prompt=findViewById(R.id.prompt); status=findViewById(R.id.status)
        findViewById<Button>(R.id.referenceButton).setOnClickListener { image.launch("image/*") }
        findViewById<Button>(R.id.voiceButton).setOnClickListener {
            val i=Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
                putExtra(RecognizerIntent.EXTRA_PROMPT, "Diga o comando para a foto")
            }
            speech.launch(i)
        }
        findViewById<Button>(R.id.generateButton).setOnClickListener {
            val who=if(findViewById<RadioButton>(R.id.sophie).isChecked) "Sophie" else "Gênny"
            if(prompt.text.isBlank()) status.text="Escreva ou fale um comando."
            else status.text="$who: comando preparado. Motor local de imagem ainda precisa do modelo para gerar a foto."
        }
    }
}
