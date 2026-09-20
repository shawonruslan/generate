package android.text.format

/** Desktop stand-in for android.text.format.DateUtils.getRelativeTimeSpanString. */
object DateUtils {
    @JvmStatic fun getRelativeTimeSpanString(at: Long): CharSequence = getRelativeTimeSpanString(at, System.currentTimeMillis(), 60_000L)
    @JvmStatic fun getRelativeTimeSpanString(time: Long, now: Long, minResolution: Long): CharSequence {
        val past = now >= time
        val d = kotlin.math.abs(now - time)
        val txt = when {
            d < 60_000L -> return if (past) "just now" else "in a moment"
            d < 3_600_000L -> "${d / 60_000L} min"
            d < 86_400_000L -> { val h = d / 3_600_000L; if (h == 1L) "1 hour" else "$h hours" }
            else -> { val days = d / 86_400_000L; if (days == 1L) "1 day" else "$days days" }
        }
        return if (past) "$txt ago" else "in $txt"
    }
}
