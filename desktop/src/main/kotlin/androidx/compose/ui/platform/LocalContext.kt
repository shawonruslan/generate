package androidx.compose.ui.platform

import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf

/** Desktop stand-in for LocalContext: always the application singleton. */
val LocalContext = staticCompositionLocalOf<Context> { com.zedge.contentstudio.ContentStudioApp.instance }
