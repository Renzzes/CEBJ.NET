package com.koneksikfi.gcashcompanion.data

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

data class PackagePool(
    val price: Int,
    val minutes: Int,
    val codes: MutableList<String>
)

/**
 * Local store for Admin → GCash → Export pool JSON.
 * Re-import replaces remaining codes for each price package.
 */
class PoolStore(context: Context) {
    private val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun importExportJson(raw: String): ImportResult {
        val root = JSONObject(raw)
        val packages = root.optJSONArray("packages")
            ?: return ImportResult(false, "Missing packages[] — use Admin Export pool JSON")

        val map = ConcurrentHashMap<Int, PackagePool>()
        var total = 0
        for (i in 0 until packages.length()) {
            val p = packages.getJSONObject(i)
            val price = p.optInt("price", 0)
            val minutes = p.optInt("minutes", 0)
            val codesArr = p.optJSONArray("codes") ?: JSONArray()
            if (price <= 0) continue
            val codes = mutableListOf<String>()
            for (c in 0 until codesArr.length()) {
                val code = codesArr.optString(c).trim()
                if (code.isNotEmpty()) codes.add(code)
            }
            map[price] = PackagePool(price, minutes, codes)
            total += codes.size
        }
        if (map.isEmpty()) {
            return ImportResult(false, "No valid packages found in file")
        }
        synchronized(lock) {
            save(map)
        }
        val gcash = root.optString("gcash_number", "")
        return ImportResult(
            true,
            "Imported $total codes across ${map.size} price(s)" +
                if (gcash.isNotBlank()) " · GCash $gcash" else ""
        )
    }

    fun summaryLines(): List<String> {
        val pools = load()
        if (pools.isEmpty()) return listOf("No pool imported")
        return pools.values.sortedBy { it.price }.map {
            "₱${it.price} → ${it.codes.size} left (${it.minutes} min)"
        }
    }

    fun remainingCount(): Int = load().values.sumOf { it.codes.size }

    /** Pop one unused code for this peso price. Returns null if empty. */
    fun popCode(pricePesos: Int): String? {
        synchronized(lock) {
            val pools = load().toMutableMap()
            val pool = pools[pricePesos] ?: return null
            if (pool.codes.isEmpty()) return null
            val code = pool.codes.removeAt(0)
            pools[pricePesos] = pool
            save(pools)
            return code
        }
    }

    private fun load(): Map<Int, PackagePool> {
        val raw = sp.getString(KEY_POOL, null) ?: return emptyMap()
        return try {
            val arr = JSONArray(raw)
            val out = mutableMapOf<Int, PackagePool>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val price = o.getInt("price")
                val minutes = o.optInt("minutes", 0)
                val codesArr = o.getJSONArray("codes")
                val codes = mutableListOf<String>()
                for (c in 0 until codesArr.length()) {
                    codes.add(codesArr.getString(c))
                }
                out[price] = PackagePool(price, minutes, codes)
            }
            out
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun save(pools: Map<Int, PackagePool>) {
        val arr = JSONArray()
        pools.values.sortedBy { it.price }.forEach { p ->
            val o = JSONObject()
            o.put("price", p.price)
            o.put("minutes", p.minutes)
            o.put("codes", JSONArray(p.codes))
            arr.put(o)
        }
        sp.edit().putString(KEY_POOL, arr.toString()).apply()
    }

    data class ImportResult(val ok: Boolean, val message: String)

    companion object {
        private const val PREFS = "ks_gcash_pool"
        private const val KEY_POOL = "packages_json"
    }
}
