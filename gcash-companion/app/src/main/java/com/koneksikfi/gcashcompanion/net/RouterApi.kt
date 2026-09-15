package com.koneksikfi.gcashcompanion.net

import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

data class ClaimResult(
    val status: String,
    val mobile: String? = null,
    val minutes: Int? = null,
    val message: String? = null
)

object RouterApi {
    /**
     * Calls existing router endpoint:
     * /cgi-bin/api?action=gcash_claim_by_amount&app_secret=...&amount_cents=...
     */
    fun claimByAmount(baseUrl: String, appSecret: String, amountCents: Int): ClaimResult {
        val base = baseUrl.trim().trimEnd('/')
        val q = buildString {
            append(base)
            append("/cgi-bin/api?action=gcash_claim_by_amount")
            append("&app_secret=").append(URLEncoder.encode(appSecret, "UTF-8"))
            append("&amount_cents=").append(amountCents)
        }
        val conn = (URL(q).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8_000
            readTimeout = 8_000
            setRequestProperty("Accept", "application/json")
        }
        return try {
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val body = BufferedReader(InputStreamReader(stream)).use { it.readText() }
            val json = JSONObject(body)
            val mobile = if (json.has("mobile") && !json.isNull("mobile")) {
                json.optString("mobile").takeIf { it.isNotBlank() }
            } else null
            ClaimResult(
                status = json.optString("status", "error"),
                mobile = mobile,
                minutes = if (json.has("minutes")) json.optInt("minutes") else null,
                message = if (json.has("message") && !json.isNull("message")) {
                    json.optString("message").takeIf { it.isNotBlank() }
                } else null
            )
        } catch (e: Exception) {
            ClaimResult(status = "error", message = e.message ?: "Network error")
        } finally {
            conn.disconnect()
        }
    }
}
