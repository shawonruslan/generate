package androidx.lifecycle

import android.app.Application

/** Desktop stand-in for androidx.lifecycle.AndroidViewModel on top of the multiplatform ViewModel. */
open class AndroidViewModel(private val application: Application) : ViewModel() {
    @Suppress("UNCHECKED_CAST")
    fun <T : Application> getApplication(): T = application as T
}
