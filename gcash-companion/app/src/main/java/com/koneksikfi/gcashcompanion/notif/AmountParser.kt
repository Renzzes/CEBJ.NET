package com.koneksikfi.gcashcompanion.notif

import java.util.regex.Pattern

object AmountParser {
    private val patterns = listOf(
        Pattern.compile("(?i)received\\s*(?:php|₱|p)\\s*([0-9]+(?:[.,][0-9]{1,2})?)"),
        Pattern.compile("(?i)you have received\\s*(?:php|₱|p)?\\s*([0-9]+(?:[.,][0-9]{1,2})?)"),
        Pattern.compile("(?i)(?:php|₱)\\s*([0-9]+(?:[.,][0-9]{1,2})?)\\s*(?:has been|was)?\\s*received"),
        Pattern.compile("(?i)amount[:\\s]+(?:php|₱)?\\s*([0-9]+(?:[.,][0-9]{1,2})?)"),
        Pattern.compile("(?i)(?:php|₱)\\s*([0-9]+(?:[.,][0-9]{1,2})?)")
    )

    /**
     * Returns amount in centavos (₱10.00 → 1000), or null if not found.
     */
    fun parseAmountCents(title: CharSequence?, text: CharSequence?): Int? {
        val blob = listOfNotNull(title?.toString(), text?.toString()).joinToString(" ")
        if (blob.isBlank()) return null
        // Prefer "received" patterns first
        for (p in patterns) {
            val m = p.matcher(blob)
            if (m.find()) {
                val raw = m.group(1)?.replace(",", "") ?: continue
                val pesos = raw.toDoubleOrNull() ?: continue
                if (pesos <= 0) continue
                return Math.round(pesos * 100.0).toInt()
            }
        }
        return null
    }

    fun centsToPesos(cents: Int): Int = Math.round(cents / 100.0).toInt()
}
