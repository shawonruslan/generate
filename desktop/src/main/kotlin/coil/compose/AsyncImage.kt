package coil.compose

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import com.zedge.contentstudio.desktop.ImageCache

/** Desktop stand-in for Coil's AsyncImage: OkHttp download + disk/memory cache + ImageIO decode. */
@Composable
fun AsyncImage(
    model: Any?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    alignment: Alignment = Alignment.Center,
    contentScale: ContentScale = ContentScale.Fit,
    alpha: Float = 1f,
    colorFilter: ColorFilter? = null,
) {
    val key = model?.toString().orEmpty()
    var bmp by remember(key) { mutableStateOf<ImageBitmap?>(ImageCache.peek(key)) }
    var failed by remember(key) { mutableStateOf(false) }
    LaunchedEffect(key) {
        if (bmp == null && key.isNotBlank()) {
            val loaded = ImageCache.load(key)
            if (loaded != null) bmp = loaded else failed = true
        }
    }
    val b = bmp
    if (b != null) {
        Image(bitmap = b, contentDescription = contentDescription, modifier = modifier, alignment = alignment, contentScale = contentScale, alpha = alpha, colorFilter = colorFilter)
    } else {
        Box(modifier.background(if (failed) Color.White.copy(alpha = 0.04f) else Color.White.copy(alpha = 0.08f)))
    }
}
