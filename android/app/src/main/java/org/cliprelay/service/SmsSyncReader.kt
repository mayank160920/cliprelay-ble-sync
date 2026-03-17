package org.cliprelay.service

import android.content.Context
import android.provider.Telephony

data class SmsSyncEntry(
    val address: String,
    val body: String,
    val timestampMs: Long
)

class SmsSyncReader(private val context: Context) {
    fun readLatest(limit: Int): List<SmsSyncEntry> {
        val safeLimit = limit.coerceIn(1, 50)
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val messages = mutableListOf<SmsSyncEntry>()

        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            null,
            null,
            Telephony.Sms.DEFAULT_SORT_ORDER
        )?.use { cursor ->
            val addressIdx = cursor.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIdx = cursor.getColumnIndex(Telephony.Sms.BODY)
            val dateIdx = cursor.getColumnIndex(Telephony.Sms.DATE)
            var count = 0
            while (cursor.moveToNext() && count < safeLimit) {
                val address = if (addressIdx >= 0) cursor.getString(addressIdx) ?: "Unknown" else "Unknown"
                val body = if (bodyIdx >= 0) cursor.getString(bodyIdx) ?: "" else ""
                val timestamp = if (dateIdx >= 0) cursor.getLong(dateIdx) else 0L
                messages.add(SmsSyncEntry(address = address, body = body, timestampMs = timestamp))
                count += 1
            }
        }

        return messages
    }
}
