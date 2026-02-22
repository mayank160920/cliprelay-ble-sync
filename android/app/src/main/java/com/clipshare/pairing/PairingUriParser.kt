package com.clipshare.pairing

import java.net.URI
import java.net.URLDecoder

data class PairingInfo(val token: String, val deviceName: String?)

object PairingUriParser {
    fun parse(rawValue: String): PairingInfo? {
        val text = rawValue.trim()
        val query = extractQuery(text) ?: return null
        val params = parseQuery(query)

        val token = params["t"] ?: params["token"] ?: return null
        if (token.length != 64) return null
        if (!token.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) return null
        val deviceName = (params["n"] ?: params["name"])?.takeIf { it.isNotBlank() }
        return PairingInfo(token.lowercase(), deviceName)
    }

    private fun extractQuery(raw: String): String? {
        val uri = runCatching { URI(raw) }.getOrNull()
        if (uri != null && uri.scheme.equals("greenpaste", ignoreCase = true)) {
            val target = when {
                !uri.host.isNullOrBlank() -> uri.host
                !uri.path.isNullOrBlank() -> uri.path.trim('/').ifBlank { null }
                else -> null
            }
            if (!target.equals("pair", ignoreCase = true)) return null
            return uri.rawQuery
        }

        val schemePrefix = "greenpaste:"
        if (!raw.startsWith(schemePrefix, ignoreCase = true)) return null
        val remainder = raw.substring(schemePrefix.length).trimStart('/').trim()
        val queryStart = remainder.indexOf('?')
        if (queryStart < 0) return null
        val target = remainder.substring(0, queryStart).trim().trim('/')
        if (!target.equals("pair", ignoreCase = true)) return null
        return remainder.substring(queryStart + 1)
    }

    private fun parseQuery(rawQuery: String): Map<String, String> {
        if (rawQuery.isBlank()) return emptyMap()
        val params = linkedMapOf<String, String>()
        rawQuery.split("&").forEach { pair ->
            if (pair.isBlank()) return@forEach
            val idx = pair.indexOf('=')
            if (idx <= 0) return@forEach
            val rawKey = pair.substring(0, idx)
            val rawValue = pair.substring(idx + 1)
            val key = decodeQueryComponent(rawKey).lowercase()
            val value = decodeQueryComponent(rawValue)
            params[key] = value
        }
        return params
    }

    private fun decodeQueryComponent(value: String): String {
        return runCatching {
            URLDecoder.decode(value, "UTF-8")
        }.getOrElse {
            value.replace('+', ' ')
        }
    }
}
