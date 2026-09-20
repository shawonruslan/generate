package android.content

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** android.content.SharedPreferences API backed by a JSON file (atomic writes). */
interface SharedPreferences {
    fun getString(key: String, defValue: String?): String?
    fun getStringSet(key: String, defValues: Set<String>?): MutableSet<String>?
    fun getInt(key: String, defValue: Int): Int
    fun getLong(key: String, defValue: Long): Long
    fun getFloat(key: String, defValue: Float): Float
    fun getBoolean(key: String, defValue: Boolean): Boolean
    fun contains(key: String): Boolean
    val all: Map<String, Any?>
    fun edit(): Editor

    interface Editor {
        fun putString(key: String, value: String?): Editor
        fun putStringSet(key: String, values: Set<String>?): Editor
        fun putInt(key: String, value: Int): Editor
        fun putLong(key: String, value: Long): Editor
        fun putFloat(key: String, value: Float): Editor
        fun putBoolean(key: String, value: Boolean): Editor
        fun remove(key: String): Editor
        fun clear(): Editor
        fun apply()
        fun commit(): Boolean
    }
}

class FilePreferences(private val file: File) : SharedPreferences {
    private val map = LinkedHashMap<String, Any?>()

    init {
        runCatching {
            if (file.isFile) {
                val o = JSONObject(file.readText())
                val it = o.keys()
                while (it.hasNext()) {
                    val k = it.next()
                    val v = o.opt(k)
                    map[k] = if (v is JSONArray) LinkedHashSet<String>().apply { for (i in 0 until v.length()) add(v.optString(i)) } else v
                }
            }
        }
    }

    private fun save() {
        val o = JSONObject()
        for ((k, v) in map) {
            when (v) {
                null -> {}
                is Set<*> -> o.put(k, JSONArray(v.toList()))
                else -> o.put(k, v)
            }
        }
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(o.toString())
        if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
    }

    @Synchronized override fun getString(key: String, defValue: String?): String? = (map[key] as? String) ?: map[key]?.toString() ?: defValue
    @Suppress("UNCHECKED_CAST")
    @Synchronized override fun getStringSet(key: String, defValues: Set<String>?): MutableSet<String>? =
        (map[key] as? Set<String>)?.let { LinkedHashSet(it) } ?: defValues?.let { LinkedHashSet(it) }
    @Synchronized override fun getInt(key: String, defValue: Int): Int = (map[key] as? Number)?.toInt() ?: defValue
    @Synchronized override fun getLong(key: String, defValue: Long): Long = (map[key] as? Number)?.toLong() ?: defValue
    @Synchronized override fun getFloat(key: String, defValue: Float): Float = (map[key] as? Number)?.toFloat() ?: defValue
    @Synchronized override fun getBoolean(key: String, defValue: Boolean): Boolean = (map[key] as? Boolean) ?: defValue
    @Synchronized override fun contains(key: String): Boolean = map.containsKey(key)
    override val all: Map<String, Any?> get() = synchronized(this) { LinkedHashMap(map) }
    override fun edit(): SharedPreferences.Editor = Ed()

    private inner class Ed : SharedPreferences.Editor {
        private val ops = ArrayList<(MutableMap<String, Any?>) -> Unit>()
        private var clearFirst = false
        override fun putString(key: String, value: String?) = also { ops.add { if (value == null) it.remove(key) else it[key] = value } }
        override fun putStringSet(key: String, values: Set<String>?) = also { ops.add { if (values == null) it.remove(key) else it[key] = LinkedHashSet(values) } }
        override fun putInt(key: String, value: Int) = also { ops.add { it[key] = value } }
        override fun putLong(key: String, value: Long) = also { ops.add { it[key] = value } }
        override fun putFloat(key: String, value: Float) = also { ops.add { it[key] = value.toDouble() } }
        override fun putBoolean(key: String, value: Boolean) = also { ops.add { it[key] = value } }
        override fun remove(key: String) = also { ops.add { it.remove(key) } }
        override fun clear() = also { clearFirst = true }
        override fun apply() { commit() }
        override fun commit(): Boolean {
            synchronized(this@FilePreferences) {
                if (clearFirst) map.clear()
                ops.forEach { it(map) }
                runCatching { save() }
            }
            return true
        }
    }
}
