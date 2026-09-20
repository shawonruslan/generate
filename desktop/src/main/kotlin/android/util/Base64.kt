package android.util

/** Desktop stand-in for android.util.Base64. */
object Base64 {
    const val DEFAULT = 0
    const val NO_PADDING = 1
    const val NO_WRAP = 2
    const val URL_SAFE = 8

    @JvmStatic fun decode(str: String, flags: Int): ByteArray {
        val clean = str.replace("\n", "").replace("\r", "").trim()
        return if (flags and URL_SAFE != 0) java.util.Base64.getUrlDecoder().decode(clean) else java.util.Base64.getMimeDecoder().decode(clean)
    }
    @JvmStatic fun decode(input: ByteArray, flags: Int): ByteArray = decode(String(input, Charsets.US_ASCII), flags)
    @JvmStatic fun encodeToString(input: ByteArray, flags: Int): String {
        var enc = if (flags and URL_SAFE != 0) java.util.Base64.getUrlEncoder() else java.util.Base64.getEncoder()
        if (flags and NO_PADDING != 0) enc = enc.withoutPadding()
        return enc.encodeToString(input)
    }
    @JvmStatic fun encode(input: ByteArray, flags: Int): ByteArray = encodeToString(input, flags).toByteArray(Charsets.US_ASCII)
}
