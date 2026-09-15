package com.koneksikfi.gcashcompanion.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class AppEvent(
    val ts: Long,
    val level: String,
    val message: String
)

class EventLog(context: Context) {
    private val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val fmt = SimpleDateFormat("HH:mm:ss", Locale.getDefault())

    fun add(level: String, message: String) {
        val events = load().toMutableList()
        events.add(0, AppEvent(System.currentTimeMillis(), level, message))
        while (events.size > MAX) events.removeAt(events.lastIndex)
        save(events)
    }

    fun lines(): List<String> = load().map {
        "${fmt.format(Date(it.ts))} [${it.level}] ${it.message}"
    }

    fun clear() = sp.edit().remove(KEY).apply()

    private fun load(): List<AppEvent> {
        val raw = sp.getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                AppEvent(o.getLong("ts"), o.getString("level"), o.getString("message"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun save(events: List<AppEvent>) {
        val arr = JSONArray()
        events.forEach {
            arr.put(
                JSONObject()
                    .put("ts", it.ts)
                    .put("level", it.level)
                    .put("message", it.message)
            )
        }
        sp.edit().putString(KEY, arr.toString()).apply()
    }

    companion object {
        private const val PREFS = "ks_gcash_events"
        private const val KEY = "events"
        private const val MAX = 20
    }
}
