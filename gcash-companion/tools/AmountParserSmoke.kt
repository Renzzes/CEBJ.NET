package com.koneksikfi.gcashcompanion

import com.koneksikfi.gcashcompanion.notif.AmountParser

/** Run with: kotlinc or from Android Studio scratch — quick sanity for amount parsing. */
fun main() {
    val samples = listOf(
        "You have received PHP 10.00 from Juan",
        "Received Php 5",
        "GCash: You received ₱20.00",
        "Unrelated notification"
    )
    for (s in samples) {
        println("$s -> ${AmountParser.parseAmountCents("GCash", s)}")
    }
}
