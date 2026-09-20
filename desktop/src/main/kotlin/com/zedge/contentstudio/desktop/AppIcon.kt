package com.zedge.contentstudio.desktop

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import java.awt.BasicStroke
import java.awt.Color
import java.awt.GradientPaint
import java.awt.Polygon
import java.awt.RenderingHints
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage

/** Programmatic app icon (gradient tile + bolt) used for the window, tray and notifications. */
object AppIcon {
    val image: BufferedImage by lazy { render(256) }
    val bitmap: ImageBitmap by lazy { image.toComposeImageBitmap() }

    fun render(size: Int): BufferedImage {
        val img = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE)
        val r = size * 0.28f
        g.paint = GradientPaint(0f, 0f, Color(0x7C5CFF), size.toFloat(), size.toFloat(), Color(0x22D3EE))
        g.fill(RoundRectangle2D.Float(0f, 0f, size.toFloat(), size.toFloat(), r, r))
        val s = size / 256.0
        val bolt = Polygon()
        val pts = intArrayOf(150, 40, 92, 140, 128, 140, 106, 216, 168, 112, 132, 112)
        for (i in pts.indices step 2) bolt.addPoint((pts[i] * s).toInt(), (pts[i + 1] * s).toInt())
        g.color = Color(255, 255, 255, 235)
        g.fill(bolt)
        g.color = Color(255, 255, 255, 90)
        g.stroke = BasicStroke((2 * s).toFloat())
        g.draw(RoundRectangle2D.Float(1f, 1f, size - 2f, size - 2f, r, r))
        g.dispose()
        return img
    }
}
