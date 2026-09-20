package androidx.compose.ui.graphics

/** Android's Bitmap.asImageBitmap() for the desktop Bitmap stand-in. */
fun android.graphics.Bitmap.asImageBitmap(): ImageBitmap = image.toComposeImageBitmap()
