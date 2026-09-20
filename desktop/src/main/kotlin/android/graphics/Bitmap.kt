package android.graphics

import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import javax.imageio.ImageIO

/** Desktop stand-in for android.graphics.Bitmap (wraps a BufferedImage). */
class Bitmap(val image: BufferedImage) {
    val width: Int get() = image.width
    val height: Int get() = image.height
    fun recycle() {}
    enum class Config { ARGB_8888, RGB_565, ALPHA_8 }
    enum class CompressFormat { JPEG, PNG, WEBP }
}

/** Desktop stand-in for android.graphics.BitmapFactory (ImageIO based). */
object BitmapFactory {
    class Options {
        var inJustDecodeBounds: Boolean = false
        var inSampleSize: Int = 1
        var inPreferredConfig: Bitmap.Config = Bitmap.Config.ARGB_8888
        var outWidth: Int = 0
        var outHeight: Int = 0
    }

    @JvmStatic fun decodeByteArray(data: ByteArray, offset: Int, length: Int, opts: Options? = null): Bitmap? {
        val slice = if (offset == 0 && length == data.size) data else data.copyOfRange(offset, offset + length)
        return try {
            if (opts != null && opts.inJustDecodeBounds) {
                ImageIO.createImageInputStream(ByteArrayInputStream(slice)).use { iis ->
                    val readers = ImageIO.getImageReaders(iis)
                    if (!readers.hasNext()) return null
                    val r = readers.next()
                    try { r.input = iis; opts.outWidth = r.getWidth(0); opts.outHeight = r.getHeight(0) } finally { r.dispose() }
                }
                null
            } else {
                var img = ImageIO.read(ByteArrayInputStream(slice)) ?: return null
                val sample = opts?.inSampleSize ?: 1
                if (sample > 1) img = scale(img, maxOf(1, img.width / sample), maxOf(1, img.height / sample))
                if (opts != null) { opts.outWidth = img.width; opts.outHeight = img.height }
                Bitmap(img)
            }
        } catch (_: Exception) { null }
    }

    fun scale(src: BufferedImage, w: Int, h: Int): BufferedImage {
        val type = if (src.colorModel.hasAlpha()) BufferedImage.TYPE_INT_ARGB else BufferedImage.TYPE_INT_RGB
        val out = BufferedImage(w, h, type)
        val g = out.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        g.drawImage(src, 0, 0, w, h, null)
        g.dispose()
        return out
    }
}
