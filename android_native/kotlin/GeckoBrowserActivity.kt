package com.aistudio.ai_image_studio

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.OvalShape
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ProgressBar
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoView

/**
 * Image to Prompt browser for Android: the built-in Firefox engine with the
 * same picture overlay as the Windows app ("Select pictures" -> tap
 * pictures -> "Generate prompts"). Prompts are made by the app in the
 * background; the back arrow returns to the app's prompt list.
 */
class GeckoBrowserActivity : Activity() {
    private lateinit var view: GeckoView
    private lateinit var urlField: EditText
    private lateinit var progress: ProgressBar
    private lateinit var reload: ImageButton
    private var session: GeckoSession? = null
    private var mainSession: GeckoSession? = null

    /** Popup windows (window.open), e.g. "Continue with Google" on
     *  Pinterest. They stay linked to their opener page so the sign-in can
     *  post its result back and close itself, like in a desktop browser. */
    private val popups = ArrayList<GeckoSession>()
    private val backable = HashMap<GeckoSession, Boolean>()
    private var loading = false
    private var density = 1f

    private fun dp(v: Int) = (v * density).toInt()

    /** Round icon button with a ripple, drawn with the app's own glyphs. */
    private fun iconButton(glyph: Glyph.Kind, desc: String, onTap: () -> Unit): ImageButton {
        val b = ImageButton(this)
        b.setImageDrawable(Glyph(glyph, Color.parseColor("#E6E6F0")))
        b.scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
        b.setPadding(dp(11), dp(11), dp(11), dp(11))
        b.background = RippleDrawable(
            ColorStateList.valueOf(Color.parseColor("#33FFFFFF")), null,
            ShapeDrawable(OvalShape()))
        b.contentDescription = desc
        if (Build.VERSION.SDK_INT >= 26) b.tooltipText = desc
        b.setOnClickListener { onTap() }
        return b
    }

    private fun setLoading(v: Boolean) {
        if (loading == v) return
        loading = v
        reload.setImageDrawable(Glyph(
            if (v) Glyph.Kind.CLOSE else Glyph.Kind.RELOAD,
            Color.parseColor("#E6E6F0")))
        reload.contentDescription = if (v) "Stop loading" else "Reload"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        GeckoBridge.browserActivity = this
        density = resources.displayMetrics.density
        val barColor = Color.parseColor("#15161D")
        if (Build.VERSION.SDK_INT >= 21) {
            window.statusBarColor = barColor
            window.navigationBarColor = Color.parseColor("#0E0F14")
        }

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Color.parseColor("#0E0F14"))
        root.fitsSystemWindows = true

        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setPadding(dp(6), dp(8), dp(6), dp(8))
        bar.setBackgroundColor(barColor)

        val close = iconButton(Glyph.Kind.CLOSE, "Back to AI Image Studio") {
            if (popups.isNotEmpty()) closePopup(popups.last()) else finish()
        }
        bar.addView(close, LinearLayout.LayoutParams(dp(44), dp(44)))

        urlField = EditText(this)
        urlField.setSingleLine(true)
        urlField.hint = "Search images or type a website"
        urlField.setTextColor(Color.parseColor("#F2F2F7"))
        urlField.setHintTextColor(Color.parseColor("#8B8CA3"))
        urlField.textSize = 14.5f
        urlField.imeOptions = EditorInfo.IME_ACTION_GO
        urlField.inputType = android.text.InputType.TYPE_CLASS_TEXT or
            android.text.InputType.TYPE_TEXT_VARIATION_URI
        urlField.setSelectAllOnFocus(true)
        urlField.background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(22).toFloat()
            setColor(Color.parseColor("#24252F"))
            setStroke(dp(1), Color.parseColor("#33344A"))
        }
        urlField.setPadding(dp(14), 0, dp(14), 0)
        val search = Glyph(Glyph.Kind.SEARCH, Color.parseColor("#8B8CA3"))
        search.setBounds(0, 0, dp(18), dp(18))
        urlField.setCompoundDrawables(search, null, null, null)
        urlField.compoundDrawablePadding = dp(10)
        urlField.setOnEditorActionListener { _, actionId, ev ->
            if (actionId == EditorInfo.IME_ACTION_GO ||
                (ev != null && ev.keyCode == KeyEvent.KEYCODE_ENTER)) {
                load(urlField.text.toString())
                true
            } else false
        }
        val urlLp = LinearLayout.LayoutParams(0, dp(44), 1f)
        urlLp.setMargins(dp(4), 0, dp(4), 0)
        bar.addView(urlField, urlLp)

        reload = iconButton(Glyph.Kind.RELOAD, "Reload") {
            if (loading) session?.stop() else session?.reload()
        }
        bar.addView(reload, LinearLayout.LayoutParams(dp(44), dp(44)))

        root.addView(bar, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal)
        progress.max = 100
        progress.visibility = View.INVISIBLE
        if (Build.VERSION.SDK_INT >= 21) {
            progress.progressTintList = ColorStateList.valueOf(Color.parseColor("#8B7CF6"))
            progress.progressBackgroundTintList = ColorStateList.valueOf(barColor)
        }
        // INVISIBLE (not GONE) so the page does not jump when loading ends.
        val pLp = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(2))
        root.addView(progress, pLp)

        view = GeckoView(this)
        root.addView(view, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)

        val s = GeckoBridge.browserSession(this)
        attach(s)
        view.setSession(s)
        session = s
        mainSession = s
        GeckoBridge.browserState()
        val url = intent.getStringExtra("url")
        if (url != null) load(url)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("url")?.let { load(it) }
    }

    private fun attach(s: GeckoSession) {
        s.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onLocationChange(
                session: GeckoSession,
                url: String?,
                perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
                hasUserGesture: Boolean
            ) {
                if (session === this@GeckoBrowserActivity.session && !urlField.hasFocus())
                    urlField.setText(url ?: "")
            }

            override fun onCanGoBack(session: GeckoSession, canGoBack: Boolean) {
                backable[session] = canGoBack
            }

            // New windows open as real popups (kept linked to the opener),
            // so OAuth / "Sign in with Google" can report back and close.
            override fun onNewSession(session: GeckoSession, uri: String): GeckoResult<GeckoSession>? {
                return GeckoResult.fromValue(openPopup(session))
            }

            override fun onLoadRequest(
                session: GeckoSession,
                request: GeckoSession.NavigationDelegate.LoadRequest
            ): GeckoResult<AllowOrDeny>? = null
        }
        s.contentDelegate = object : GeckoSession.ContentDelegate {
            // window.close() from a popup (sign-in finished).
            override fun onCloseRequest(session: GeckoSession) {
                if (popups.contains(session)) closePopup(session)
            }
        }
        s.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                if (session !== this@GeckoBrowserActivity.session) return
                progress.visibility = View.VISIBLE
                progress.progress = 5
                setLoading(true)
            }

            override fun onProgressChange(session: GeckoSession, p: Int) {
                if (session !== this@GeckoBrowserActivity.session) return
                progress.progress = p
                progress.visibility = if (p >= 100) View.INVISIBLE else View.VISIBLE
            }

            override fun onPageStop(session: GeckoSession, success: Boolean) {
                if (session !== this@GeckoBrowserActivity.session) return
                progress.visibility = View.INVISIBLE
                setLoading(false)
            }
        }
    }

    /** Creates (not opens - Gecko opens it) the popup session and shows it. */
    private fun openPopup(opener: GeckoSession): GeckoSession {
        val p = GeckoSession(opener.settings)
        attach(p)
        popups.add(p)
        show(p)
        return p
    }

    private fun closePopup(p: GeckoSession) {
        val i = popups.indexOf(p)
        if (i < 0) return
        popups.removeAt(i)
        backable.remove(p)
        val next = if (popups.isNotEmpty()) popups.last() else mainSession
        if (session === p && next != null) show(next)
        try {
            p.navigationDelegate = null
            p.progressDelegate = null
            p.contentDelegate = null
            p.close()
        } catch (_: Exception) {
        }
    }

    private fun show(s: GeckoSession) {
        try {
            view.releaseSession()
        } catch (_: Exception) {
        }
        view.setSession(s)
        session = s
        progress.visibility = View.INVISIBLE
        setLoading(false)
        view.requestFocus()
    }

    /** Renders the visible page and cuts out the area (shares 0..1 of the
     *  view). [done] gets base64 PNG or null, on the main thread. */
    fun capture(fx: Double, fy: Double, fw: Double, fh: Double, done: (String?) -> Unit) {
        val main = android.os.Handler(mainLooper)
        try {
            view.capturePixels().accept({ bmp ->
                if (bmp == null) {
                    main.post { done(null) }
                } else {
                    Thread {
                        val out = try {
                            val bw = bmp.width
                            val bh = bmp.height
                            val x = (fx * bw).toInt().coerceIn(0, bw - 1)
                            val y = (fy * bh).toInt().coerceIn(0, bh - 1)
                            val w = (fw * bw).toInt().coerceIn(1, bw - x)
                            val h = (fh * bh).toInt().coerceIn(1, bh - y)
                            val crop = android.graphics.Bitmap.createBitmap(bmp, x, y, w, h)
                            val bos = java.io.ByteArrayOutputStream()
                            crop.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, bos)
                            android.util.Base64.encodeToString(bos.toByteArray(), android.util.Base64.NO_WRAP)
                        } catch (e: Throwable) {
                            null
                        }
                        main.post { done(out) }
                    }.start()
                }
            }, { _ ->
                main.post { done(null) }
            })
        } catch (e: Throwable) {
            done(null)
        }
    }

    fun load(input: String) {
        val u = normalize(input)
        urlField.setText(u)
        urlField.clearFocus()
        (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(urlField.windowToken, 0)
        view.requestFocus()
        session?.loadUri(u)
    }

    private fun normalize(input: String): String {
        val t = input.trim()
        if (t.isEmpty()) return "https://www.google.com/imghp"
        if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*://").containsMatchIn(t)) return t
        if (!t.contains(' ') && t.contains('.')) return "https://$t"
        return "https://www.google.com/search?tbm=isch&q=" +
            java.net.URLEncoder.encode(t, "UTF-8")
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val cur = session
        if (cur != null && backable[cur] == true) {
            cur.goBack()
            return
        }
        if (cur != null && popups.contains(cur)) {
            closePopup(cur)
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    override fun onDestroy() {
        // Keep the tab (and its page) alive for the next time; just detach.
        try {
            view.releaseSession()
        } catch (_: Exception) {
        }
        for (p in ArrayList(popups)) {
            try {
                p.close()
            } catch (_: Exception) {
            }
        }
        popups.clear()
        mainSession?.navigationDelegate = null
        mainSession?.progressDelegate = null
        mainSession?.contentDelegate = null
        if (GeckoBridge.browserActivity === this) GeckoBridge.browserActivity = null
        GeckoBridge.browserState()
        super.onDestroy()
    }
}

/** Minimal line icons (24-unit grid) so the toolbar matches the app. */
class Glyph(private val kind: Kind, color: Int) : Drawable() {
    enum class Kind { CLOSE, RELOAD, SEARCH, BACK }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        style = Paint.Style.FILL
    }

    override fun getIntrinsicWidth() = 72
    override fun getIntrinsicHeight() = 72

    override fun draw(canvas: Canvas) {
        val b = bounds
        val size = minOf(b.width(), b.height()).toFloat()
        if (size <= 0f) return
        val k = size / 24f
        canvas.save()
        canvas.translate(b.left + (b.width() - size) / 2f, b.top + (b.height() - size) / 2f)
        canvas.scale(k, k)
        paint.strokeWidth = 2f
        when (kind) {
            Kind.CLOSE -> {
                canvas.drawLine(6f, 6f, 18f, 18f, paint)
                canvas.drawLine(18f, 6f, 6f, 18f, paint)
            }
            Kind.BACK -> {
                canvas.drawLine(19f, 12f, 5f, 12f, paint)
                val p = Path()
                p.moveTo(11f, 6f); p.lineTo(5f, 12f); p.lineTo(11f, 18f)
                canvas.drawPath(p, paint)
            }
            Kind.SEARCH -> {
                canvas.drawCircle(10.5f, 10.5f, 6f, paint)
                canvas.drawLine(15f, 15f, 20f, 20f, paint)
            }
            Kind.RELOAD -> {
                canvas.drawArc(RectF(5f, 5f, 19f, 19f), 20f, 290f, false, paint)
                // Arrow head at the end of the arc (310 deg, upper right).
                val a = Math.toRadians(310.0)
                val ex = (12 + 7 * Math.cos(a)).toFloat()
                val ey = (12 + 7 * Math.sin(a)).toFloat()
                val dx = (-Math.sin(a)).toFloat()
                val dy = Math.cos(a).toFloat()
                val p = Path()
                p.moveTo(ex + dx * 3.2f, ey + dy * 3.2f)
                p.lineTo(ex - dy * 3f, ey + dx * 3f)
                p.lineTo(ex + dy * 3f, ey - dx * 3f)
                p.close()
                canvas.drawPath(p, fill)
            }
        }
        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        fill.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        fill.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
