package com.zedge.contentstudio.desktop

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import com.zedge.contentstudio.ui.components.MhLogo
import java.awt.Color
import java.awt.RenderingHints
import java.awt.geom.AffineTransform
import java.awt.geom.Path2D
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage

/**
 * v30: Meta Hawladar monogram rendered with java.awt for the window icon, taskbar and tray.
 * The SVG path data lives in [MhLogo] (shared with the Compose mark) so the icon always matches the UI,
 * and [render] accepts palette colours so the icon re-tints with the live theme.
 */
object AppIcon {
    private val TOKEN = Regex("[MLCZ]|-?(?:[0-9]*\\.)?[0-9]+(?:[eE]-?[0-9]+)?")

    /** Minimal absolute M/L/C/Z parser - exactly the command set used by logo.svg. */
    private fun parse(d: String): Path2D.Double {
        val p = Path2D.Double(Path2D.WIND_NON_ZERO)
        val t = TOKEN.findAll(d).map { it.value }.toList()
        var i = 0
        var cmd = 'M'
        fun n(): Double = t[i++].toDouble()
        while (i < t.size) {
            val tok = t[i]
            if (tok.length == 1 && tok[0].isLetter()) {
                cmd = tok[0]; i++
                if (cmd == 'Z') { p.closePath(); continue }
                if (i >= t.size) break
            }
            when (cmd) {
                'M' -> { p.moveTo(n(), n()); cmd = 'L' }
                'L' -> p.lineTo(n(), n())
                'C' -> p.curveTo(n(), n(), n(), n(), n(), n())
                else -> i++
            }
        }
        return p
    }

    private val primaryShape: Path2D.Double by lazy { parse(MhLogo.PATH_PRIMARY) }
    private val inkShape: Path2D.Double by lazy { parse(MhLogo.PATH_INK) }
    private val ink2Shape: Path2D.Double by lazy { parse(MhLogo.PATH_INK2) }

    const val DEFAULT_PRIMARY = 0xFE4102
    const val DEFAULT_INK = 0x151515
    const val DEFAULT_TILE = 0xF5F4E8

    /** Renders the logo tile at [size] px. Colours are 0xRRGGBB ints (alpha ignored). */
    fun render(size: Int, primary: Int = DEFAULT_PRIMARY, ink: Int = DEFAULT_INK, tile: Int = DEFAULT_TILE): BufferedImage {
        val img = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE)
        val r = size * 0.22
        g.color = Color(tile and 0xFFFFFF)
        g.fill(RoundRectangle2D.Double(0.0, 0.0, size.toDouble(), size.toDouble(), r, r))
        val inset = 0.10
        val s = size * (1.0 - 2.0 * inset) / MhLogo.VIEWPORT
        val at = AffineTransform()
        at.translate(size * inset, size * inset)
        at.scale(s, s)
        g.transform(at)
        g.color = Color(primary and 0xFFFFFF); g.fill(primaryShape)
        g.color = Color(ink and 0xFFFFFF); g.fill(inkShape); g.fill(ink2Shape)
        g.dispose()
        return img
    }

    /** Default (brand colours) icon - used before the theme is known. */
    val image: BufferedImage by lazy { render(256) }
    val bitmap: ImageBitmap by lazy { image.toComposeImageBitmap() }

    /** Theme-tinted icon for the window / taskbar / tray. */
    fun themed(primary: Int, ink: Int, tile: Int, size: Int = 256): BufferedImage = render(size, primary, ink, tile)
    fun themedBitmap(primary: Int, ink: Int, tile: Int): ImageBitmap = themed(primary, ink, tile).toComposeImageBitmap()
}
