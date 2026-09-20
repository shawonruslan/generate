package androidx.activity.compose

import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState

class ManagedActivityResultLauncher<I>(private val fire: (I) -> Unit) {
    fun launch(input: I) = fire(input)
}

/** Desktop stand-in for rememberLauncherForActivityResult (file dialogs / permissions). */
@Composable
fun <I, O> rememberLauncherForActivityResult(contract: ActivityResultContract<I, O>, onResult: (O) -> Unit): ManagedActivityResultLauncher<I> {
    val cb = rememberUpdatedState(onResult)
    return remember(contract) { ManagedActivityResultLauncher<I> { input -> contract.run(input) { r -> cb.value(r) } } }
}
