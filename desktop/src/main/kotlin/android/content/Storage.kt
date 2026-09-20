package android.content

import java.io.File
import java.util.concurrent.ConcurrentHashMap

/** Where the Windows app keeps its data: %APPDATA%\MetaHawladar (fallback: ~/.meta-hawladar). */
object Storage {
    val baseDir: File by lazy {
        val appData = System.getenv("APPDATA")
        val dir = if (!appData.isNullOrBlank()) File(appData, "MetaHawladar") else File(System.getProperty("user.home"), ".meta-hawladar")
        dir.mkdirs(); dir
    }
    val filesDir: File by lazy { File(baseDir, "files").also { it.mkdirs() } }
    val cacheDir: File by lazy { File(baseDir, "cache").also { it.mkdirs() } }
    val prefsDir: File by lazy { File(baseDir, "prefs").also { it.mkdirs() } }

    private val cache = ConcurrentHashMap<String, SharedPreferences>()
    fun prefs(name: String): SharedPreferences = cache.getOrPut(name) { FilePreferences(File(prefsDir, "$name.json")) }
}
