package com.cliprelay.debug

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.cliprelay.pairing.PairingStore
import com.cliprelay.service.ClipRelayService

/**
 * Debug-only receiver for injecting pairing tokens via adb.
 *
 * Usage:
 *   adb shell am broadcast -a com.cliprelay.action.SMOKE_IMPORT_PAIRING \
 *       --es extra_token "<64-char-hex>" -n com.cliprelay/.debug.SmokeImportReceiver
 */
class SmokeImportReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra("extra_token")
        if (token.isNullOrBlank() || token.length != 64) {
            Log.e("SmokeImport", "Invalid or missing token (expected 64 hex chars)")
            return
        }

        PairingStore(context).saveToken(token.lowercase())
        Log.e("SmokeImport", "Pairing token imported successfully")

        // Notify the running service to reload pairing state
        val serviceIntent = Intent(context, ClipRelayService::class.java)
        serviceIntent.action = ClipRelayService.ACTION_RELOAD_PAIRING
        context.startForegroundService(serviceIntent)
    }
}
