package android.net

import java.io.File
import java.net.URI

/** Desktop stand-in for android.net.Uri. Wraps either a local file path / file: URI or a remote URL. */
class Uri private constructor(private val raw: String) {
    val scheme: String?
        get() {
            val i = raw.indexOf(':')
            if (i <= 1) return null                       // "C:\\..." is a Windows drive, not a scheme
            val s = raw.substring(0, i)
            return if (s.all { it.isLetterOrDigit() || it == '+' || it == '-' || it == '.' }) s.lowercase() else null
        }
    val isLocalFile: Boolean get() = scheme == null || scheme == "file"
    val path: String?
        get() = when (scheme) {
            null -> raw
            "file" -> runCatching { File(URI(raw)).path }.getOrElse { raw.removePrefix("file:") }
            else -> runCatching { URI(raw).path }.getOrNull()
        }
    val lastPathSegment: String?
        get() = (path ?: raw).trimEnd('/', '\\').substringAfterLast('/').substringAfterLast('\\').ifBlank { null }

    fun toFile(): File = if (scheme == "file") runCatching { File(URI(raw)) }.getOrElse { File(raw.removePrefix("file:")) } else File(raw)

    override fun toString(): String = raw
    override fun equals(other: Any?): Boolean = other is Uri && other.raw == raw
    override fun hashCode(): Int = raw.hashCode()

    companion object {
        @JvmStatic fun parse(s: String): Uri = Uri(s)
        @JvmStatic fun fromFile(f: File): Uri = Uri(f.toURI().toString())
    }
}
