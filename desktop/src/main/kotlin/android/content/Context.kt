package android.content

import java.io.File

/** Desktop stand-in for android.content.Context: app-scoped storage + preferences (no Android runtime). */
open class Context {
    open val cacheDir: File get() = Storage.cacheDir
    open val filesDir: File get() = Storage.filesDir
    open fun getSharedPreferences(name: String, mode: Int): SharedPreferences = Storage.prefs(name)

    companion object {
        const val MODE_PRIVATE = 0
    }
}
