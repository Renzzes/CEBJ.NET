package com.koneksikfi.gcashcompanion.sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager
import androidx.core.content.ContextCompat

object SmsSender {
    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    fun send(context: Context, mobile: String, body: String): Result<Unit> {
        if (!hasPermission(context)) {
            return Result.failure(SecurityException("SMS permission not granted"))
        }
        val dest = normalizePh(mobile)
            ?: return Result.failure(IllegalArgumentException("Invalid mobile: $mobile"))
        return try {
            @Suppress("DEPRECATION")
            val sms = SmsManager.getDefault()
            val parts = sms.divideMessage(body)
            if (parts.size == 1) {
                sms.sendTextMessage(dest, null, body, null, null)
            } else {
                sms.sendMultipartTextMessage(dest, null, parts, null, null)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /** Normalize to 09XXXXXXXXX for PH SMS. */
    fun normalizePh(raw: String): String? {
        val digits = raw.filter { it.isDigit() }
        return when {
            digits.length == 11 && digits.startsWith("09") -> digits
            digits.length == 12 && digits.startsWith("63") -> "0" + digits.substring(2)
            digits.length == 10 && digits.startsWith("9") -> "0$digits"
            else -> null
        }
    }
}
