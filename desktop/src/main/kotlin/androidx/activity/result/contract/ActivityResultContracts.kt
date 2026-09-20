package androidx.activity.result.contract

import android.net.Uri
import com.zedge.contentstudio.desktop.DesktopPickers

/** Desktop stand-in: contracts run native file dialogs instead of Android intents. */
abstract class ActivityResultContract<I, O> {
    abstract fun run(input: I, onResult: (O) -> Unit)
}

object ActivityResultContracts {
    class OpenDocument : ActivityResultContract<Array<String>, Uri?>() {
        override fun run(input: Array<String>, onResult: (Uri?) -> Unit) = DesktopPickers.pick(input, false) { onResult(it.firstOrNull()) }
    }
    class OpenMultipleDocuments : ActivityResultContract<Array<String>, List<Uri>>() {
        override fun run(input: Array<String>, onResult: (List<Uri>) -> Unit) = DesktopPickers.pick(input, true) { onResult(it) }
    }
    class GetContent : ActivityResultContract<String, Uri?>() {
        override fun run(input: String, onResult: (Uri?) -> Unit) = DesktopPickers.pick(arrayOf(input), false) { onResult(it.firstOrNull()) }
    }
    class GetMultipleContents : ActivityResultContract<String, List<Uri>>() {
        override fun run(input: String, onResult: (List<Uri>) -> Unit) = DesktopPickers.pick(arrayOf(input), true) { onResult(it) }
    }
    class RequestPermission : ActivityResultContract<String, Boolean>() {
        override fun run(input: String, onResult: (Boolean) -> Unit) = onResult(true)
    }
}
