package android.graphics

/** Desktop stand-in for android.graphics.Color (only the static helpers the app uses). */
object Color {
    @JvmStatic fun parseColor(s: String): Int {
        var h = s.trim().removePrefix("#")
        if (h.length == 3) h = h.map { "$it$it" }.joinToString("")
        if (h.length == 6) h = "FF$h"
        require(h.length == 8) { "Unknown color $s" }
        return java.lang.Long.parseLong(h, 16).toInt()
    }
    @JvmStatic fun colorToHSV(color: Int, hsv: FloatArray) {
        val out = java.awt.Color.RGBtoHSB((color shr 16) and 0xFF, (color shr 8) and 0xFF, color and 0xFF, null)
        hsv[0] = out[0] * 360f; hsv[1] = out[1]; hsv[2] = out[2]
    }
    @JvmStatic fun HSVToColor(hsv: FloatArray): Int = HSVToColor(0xFF, hsv)
    @JvmStatic fun HSVToColor(alpha: Int, hsv: FloatArray): Int {
        val rgb = java.awt.Color.HSBtoRGB(hsv[0] / 360f, hsv[1], hsv[2]) and 0xFFFFFF
        return (alpha shl 24) or rgb
    }
    @JvmStatic fun red(c: Int) = (c shr 16) and 0xFF
    @JvmStatic fun green(c: Int) = (c shr 8) and 0xFF
    @JvmStatic fun blue(c: Int) = c and 0xFF
    @JvmStatic fun alpha(c: Int) = (c shr 24) and 0xFF
    @JvmStatic fun argb(a: Int, r: Int, g: Int, b: Int) = (a shl 24) or (r shl 16) or (g shl 8) or b
    @JvmStatic fun rgb(r: Int, g: Int, b: Int) = argb(0xFF, r, g, b)
}
