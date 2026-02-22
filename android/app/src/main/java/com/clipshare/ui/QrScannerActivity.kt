package com.clipshare.ui

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.clipshare.pairing.PairingStore
import com.clipshare.pairing.PairingUriParser
import com.clipshare.service.ClipShareService
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode

class QrScannerActivity : AppCompatActivity() {
    companion object {
        private const val MODULE_RETRY_DELAY_MS = 1_500L
        private const val MAX_MODULE_RETRIES = 20
    }

    private val handler = Handler(Looper.getMainLooper())
    private var moduleRetryCount = 0
    private var moduleToastShown = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        launchScanner()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun launchScanner() {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()

        val scanner = GmsBarcodeScanning.getClient(this, options)
        scanner.startScan()
            .addOnSuccessListener { barcode ->
                val rawValue = barcode.rawValue
                if (rawValue != null) {
                    handleScannedValue(rawValue)
                } else {
                    Toast.makeText(this, "No data in QR code", Toast.LENGTH_SHORT).show()
                    finish()
                }
            }
            .addOnCanceledListener {
                handler.removeCallbacksAndMessages(null)
                finish()
            }
            .addOnFailureListener { e ->
                if (isBarcodeModulePendingError(e)) {
                    retryWhenBarcodeModuleReady()
                    return@addOnFailureListener
                }
                Toast.makeText(this, "Scan failed: ${e.message}", Toast.LENGTH_SHORT).show()
                finish()
            }
    }

    private fun retryWhenBarcodeModuleReady() {
        if (!moduleToastShown) {
            moduleToastShown = true
            Toast.makeText(
                this,
                "Preparing barcode scanner. Please wait a moment...",
                Toast.LENGTH_LONG
            ).show()
        }

        if (moduleRetryCount >= MAX_MODULE_RETRIES) {
            Toast.makeText(
                this,
                "Barcode scanner is still downloading. Please try again shortly.",
                Toast.LENGTH_LONG
            ).show()
            finish()
            return
        }

        moduleRetryCount += 1
        handler.postDelayed({ launchScanner() }, MODULE_RETRY_DELAY_MS)
    }

    private fun isBarcodeModulePendingError(error: Exception): Boolean {
        val message = error.message ?: return false
        return message.contains("barcode module", ignoreCase = true) &&
            message.contains("download", ignoreCase = true)
    }

    private fun handleScannedValue(rawValue: String) {
        val info = PairingUriParser.parse(rawValue)
        if (info == null) {
            Toast.makeText(this, "Invalid pairing QR code", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        val stored = runCatching {
            PairingStore(this).saveToken(info.token)

            if (info.deviceName != null) {
                getSharedPreferences(ClipShareService.PREFS_NAME, MODE_PRIVATE)
                    .edit()
                    .putString(ClipShareService.KEY_CONNECTED_DEVICE, info.deviceName)
                    .apply()
            }
        }.isSuccess

        if (!stored) {
            Toast.makeText(this, "Pairing failed. Please try again.", Toast.LENGTH_LONG).show()
            finish()
            return
        }

        Toast.makeText(this, "Paired successfully!", Toast.LENGTH_SHORT).show()
        setResult(RESULT_OK)
        finish()
    }
}
