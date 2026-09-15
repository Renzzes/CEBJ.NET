package com.koneksikfi.gcashcompanion.data

import android.content.Context
import android.content.SharedPreferences

class Prefs(context: Context) {
    private val sp: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var appSecret: String
        get() = sp.getString(KEY_SECRET, "") ?: ""
        set(value) = sp.edit().putString(KEY_SECRET, value.trim()).apply()

    var routerBaseUrl: String
        get() = (sp.getString(KEY_ROUTER, "http://10.0.0.1") ?: "http://10.0.0.1").trimEnd('/')
        set(value) {
            val cleaned = value.trim().trimEnd('/')
            sp.edit().putString(KEY_ROUTER, if (cleaned.isEmpty()) "http://10.0.0.1" else cleaned).apply()
        }

    var listeningEnabled: Boolean
        get() = sp.getBoolean(KEY_LISTEN, false)
        set(value) = sp.edit().putBoolean(KEY_LISTEN, value).apply()

    companion object {
        private const val PREFS = "ks_gcash_companion"
        private const val KEY_SECRET = "app_secret"
        private const val KEY_ROUTER = "router_base_url"
        private const val KEY_LISTEN = "listening_enabled"
    }
}
