package com.koneksikfi.gcashcompanion

import android.content.Context
import com.koneksikfi.gcashcompanion.data.EventLog
import com.koneksikfi.gcashcompanion.data.PoolStore
import com.koneksikfi.gcashcompanion.data.Prefs
import com.koneksikfi.gcashcompanion.net.RouterApi
import com.koneksikfi.gcashcompanion.notif.AmountParser
import com.koneksikfi.gcashcompanion.sms.SmsSender
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object PaymentProcessor {
    private val recentKeys = LinkedHashMap<String, Long>()

    suspend fun handleGcashNotification(
        context: Context,
        title: CharSequence?,
        text: CharSequence?,
        packageName: String?
    ) {
        val prefs = Prefs(context)
        if (!prefs.listeningEnabled) return

        val pkg = packageName.orEmpty().lowercase()
        if (pkg.isNotEmpty() && !isLikelyGcash(pkg, title, text)) return

        val cents = AmountParser.parseAmountCents(title, text) ?: return
        val pesos = AmountParser.centsToPesos(cents)
        if (pesos <= 0) return

        // Dedupe identical payment bursts within 45s
        val dedupeKey = "$cents"
        val now = System.currentTimeMillis()
        synchronized(recentKeys) {
            recentKeys.entries.removeIf { now - it.value > 45_000 }
            if (recentKeys.containsKey(dedupeKey)) return
            recentKeys[dedupeKey] = now
        }

        val log = EventLog(context)
        val pool = PoolStore(context)

        if (prefs.appSecret.isBlank()) {
            log.add("ERR", "₱$pesos seen but companion secret not set")
            return
        }

        log.add("INFO", "GCash ₱$pesos detected — claiming order…")

        val claim = withContext(Dispatchers.IO) {
            RouterApi.claimByAmount(prefs.routerBaseUrl, prefs.appSecret, cents)
        }

        when (claim.status) {
            "ok" -> {
                val mobile = claim.mobile
                if (mobile.isNullOrBlank()) {
                    log.add("ERR", "Claim OK but no mobile returned")
                    return
                }
                val code = pool.popCode(pesos)
                if (code == null) {
                    log.add("ERR", "No local code left for ₱$pesos — re-import pool")
                    return
                }
                val body = context.getString(R.string.sms_template, code)
                val sms = SmsSender.send(context, mobile, body)
                if (sms.isSuccess) {
                    log.add("OK", "SMS $code → $mobile (₱$pesos)")
                } else {
                    log.add("ERR", "Code $code reserved but SMS failed: ${sms.exceptionOrNull()?.message}")
                }
            }
            "no_match" -> {
                log.add(
                    "WARN",
                    "₱$pesos paid but no pending portal order (customer must enter mobile + package first, or order expired)"
                )
            }
            else -> {
                log.add("ERR", "Claim failed: ${claim.message ?: claim.status}")
            }
        }
    }

    private fun isLikelyGcash(pkg: String, title: CharSequence?, text: CharSequence?): Boolean {
        if (pkg.contains("gcash")) return true
        val blob = "${title?.toString().orEmpty()} ${text?.toString().orEmpty()}".lowercase()
        if (blob.contains("gcash")) return true
        val looksLikeMoney = blob.contains("php") || blob.contains("₱") || blob.contains("peso")
        val looksLikeReceive = blob.contains("received") || blob.contains("you have received")
        return looksLikeMoney && looksLikeReceive
    }
}
