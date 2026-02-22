package com.clipshare.pairing

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class PairingStore(context: Context) {
    companion object {
        private const val PREFS_NAME = "greenpaste_pairing"
        private const val KEY_TOKEN = "pairing_token"
    }

    private val fallbackPrefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val encryptedPrefs: SharedPreferences? = try {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (_: Exception) {
        null
    }

    fun saveToken(token: String) {
        if (writeToken(encryptedPrefs, token)) return
        writeToken(fallbackPrefs, token)
    }

    fun loadToken(): String? {
        return readToken(encryptedPrefs) ?: readToken(fallbackPrefs)
    }

    fun clear() {
        clearToken(encryptedPrefs)
        clearToken(fallbackPrefs)
    }

    private fun writeToken(prefs: SharedPreferences?, token: String): Boolean {
        if (prefs == null) return false
        return runCatching {
            prefs.edit().putString(KEY_TOKEN, token).apply()
            true
        }.getOrDefault(false)
    }

    private fun readToken(prefs: SharedPreferences?): String? {
        if (prefs == null) return null
        return runCatching { prefs.getString(KEY_TOKEN, null) }.getOrNull()
    }

    private fun clearToken(prefs: SharedPreferences?) {
        if (prefs == null) return
        runCatching {
            prefs.edit().remove(KEY_TOKEN).apply()
        }
    }
}
