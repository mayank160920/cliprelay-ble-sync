package com.clipshare.ui

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.clipshare.R
import com.clipshare.service.ClipShareService

class ShareReceiverActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) {
                val serviceIntent = Intent(this, ClipShareService::class.java).apply {
                    action = ClipShareService.ACTION_PUSH_TEXT
                    putExtra(ClipShareService.EXTRA_TEXT, text)
                }
                startForegroundService(serviceIntent)

                val deviceName = getSharedPreferences(ClipShareService.PREFS_NAME, MODE_PRIVATE)
                    .getString(ClipShareService.KEY_CONNECTED_DEVICE, null)
                val message = if (deviceName != null)
                    getString(R.string.toast_sent_to, deviceName)
                else
                    getString(R.string.toast_sent)
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }
        }

        finish()
    }
}
