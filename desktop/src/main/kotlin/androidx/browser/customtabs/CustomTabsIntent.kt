package androidx.browser.customtabs

import android.content.Context
import android.net.Uri
import java.awt.Desktop
import java.net.URI

/** Desktop stand-in: opens the URL in the default browser. */
class CustomTabsIntent private constructor() {
    fun launchUrl(context: Context, uri: Uri) {
        runCatching { Desktop.getDesktop().browse(URI(uri.toString())) }
    }
    class Builder {
        fun build(): CustomTabsIntent = CustomTabsIntent()
    }
}
