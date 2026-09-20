package android.app

import android.content.Context

/** Desktop stand-in for android.app.Application (process-wide singleton owner). */
open class Application : Context() {
    open fun onCreate() {}
}
