package com.aistudio.ai_image_studio

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Android Chromium WebView activity for Stable Audio sign-in and automated
 * account rotation (WorkOS AuthKit + OTP). Kept separate from GeckoView so
 * Google/Gemini stays on GeckoView while Stable Audio runs on Chromium.
 */
class StableAudioWebViewActivity : Activity() {
    companion object {
        private var pendingResult: MethodChannel.Result? = null
        var saChannel: MethodChannel? = null

        fun startSignIn(activity: Activity, result: MethodChannel.Result) {
            pendingResult?.success(null)
            pendingResult = result
            val i = Intent(activity, StableAudioWebViewActivity::class.java)
            i.putExtra("auto", false)
            activity.startActivity(i)
        }

        fun startAutoCreate(
            activity: Activity,
            email: String,
            password: String,
            result: MethodChannel.Result
        ) {
            pendingResult?.success(null)
            pendingResult = result
            val i = Intent(activity, StableAudioWebViewActivity::class.java)
            i.putExtra("auto", true)
            i.putExtra("email", email)
            i.putExtra("password", password)
            activity.startActivity(i)
        }

        private fun finishWith(json: String?) {
            val r = pendingResult ?: return
            pendingResult = null
            r.success(json)
        }
    }

    private lateinit var webView: WebView
    private val main = Handler(Looper.getMainLooper())
    private var autoMode = false
    private var email = ""
    private var password = ""
    private var otpCode = ""
    private var otpRequested = false
    private var finished = false
    private var lastClientId = "client_01M5FKRSSZMYNTGJZ7SF9WXKH6"

    private val ticker = object : Runnable {
        override fun run() {
            if (finished) return
            injectHookAndStep()
            main.postDelayed(this, 900)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        autoMode = intent.getBooleanExtra("auto", false)
        email = intent.getStringExtra("email") ?: ""
        password = intent.getStringExtra("password") ?: ""

        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val root = LinearLayout(this)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Color.WHITE)
        root.fitsSystemWindows = true

        val bar = LinearLayout(this)
        bar.orientation = LinearLayout.HORIZONTAL
        bar.gravity = Gravity.CENTER_VERTICAL
        bar.setPadding(dp(16), dp(6), dp(8), dp(6))
        bar.setBackgroundColor(Color.parseColor("#F1F3F4"))
        val title = TextView(this)
        title.text = if (autoMode) "Creating Stable Audio Account..." else "Sign in to Stable Audio"
        title.setTextColor(Color.parseColor("#202124"))
        title.textSize = 16f
        bar.addView(title, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        val done = Button(this)
        done.text = "Done"
        done.setOnClickListener { completeAndClose(null) }
        bar.addView(done)
        root.addView(bar, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))

        webView = WebView(this)
        root.addView(webView, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)

        val ws = webView.settings
        ws.javaScriptEnabled = true
        ws.domStorageEnabled = true
        ws.databaseEnabled = true
        ws.useWideViewPort = true
        ws.loadWithOverviewMode = true
        ws.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        // Desktop Chrome UA so stableaudio.com renders desktop navbar ("Start free").
        ws.userAgentString =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        webView.addJavascriptInterface(JsBridge(), "aisSaBridge")
        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                val headers = request?.requestHeaders
                if (headers != null) {
                    for ((k, v) in headers) {
                        if (k.equals("Authorization", ignoreCase = true) && v.startsWith("Bearer ")) {
                            val tok = v.substring(7).trim()
                            if (tok.length > 40) {
                                main.post {
                                    emitToken(tok, "", lastClientId)
                                }
                            }
                        }
                    }
                }
                return super.shouldInterceptRequest(view, request)
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                injectHookAndStep()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                injectHookAndStep()
            }
        }

        // Clear previous Stable Audio / AuthKit session so each rotation starts fresh.
        val cm = CookieManager.getInstance()
        cm.setAcceptCookie(true)
        cm.removeAllCookies {
            cm.flush()
            WebStorage.getInstance().deleteAllData()
            webView.clearCache(true)
            webView.loadUrl("https://stableaudio.com")
            main.postDelayed(ticker, 900)
        }

        if (autoMode) {
            main.postDelayed({ completeAndClose(null) }, 140000)
        }
    }

    private fun emitToken(accessToken: String, refreshToken: String, clientId: String) {
        if (finished) return
        if (accessToken.isEmpty() && refreshToken.isEmpty()) return
        val obj = JSONObject()
            .put("accessToken", accessToken)
            .put("refreshToken", refreshToken)
            .put("clientId", if (clientId.isNotEmpty()) clientId else lastClientId)
        completeAndClose(obj.toString())
    }

    private fun completeAndClose(json: String?) {
        if (finished) return
        finished = true
        main.removeCallbacks(ticker)
        finishWith(json)
        finish()
    }

    private fun injectHookAndStep() {
        if (finished) return
        val cfgJson = JSONObject()
            .put("auto", autoMode)
            .put("email", email)
            .put("password", password)
            .put("otp", otpCode)
            .toString()

        val js = """
        (function(cfg) {
          try {
            if (!window.__aisSaHooked) {
              window.__aisSaHooked = true;
              window.__aisSaState = window.__aisSaState || {
                signupAt: 0, emailAt: 0, passAt: 0, otpAt: 0, termsAt: 0, otpAsked: false
              };
              var origFetch = window.fetch;
              window.fetch = function(input, init) {
                var url = '';
                var reqCid = '';
                try {
                  url = typeof input === 'string' ? input : (input && input.url) || '';
                  var hdrs = (init && init.headers) || (input && input.headers);
                  if (hdrs) {
                    var auth = '';
                    if (typeof hdrs.get === 'function') auth = hdrs.get('authorization') || hdrs.get('Authorization') || '';
                    else if (typeof hdrs === 'object') {
                      Object.keys(hdrs).forEach(function(k) {
                        if (k.toLowerCase() === 'authorization') auth = String(hdrs[k] || '');
                      });
                    }
                    if (auth.indexOf('Bearer ') === 0 && auth.length > 48) {
                      aisSaBridge.onToken(auth.slice(7).trim(), '', '');
                    }
                  }
                  if (url.indexOf('workos.com/user_management/authenticate') !== -1 && init && typeof init.body === 'string') {
                    var b = JSON.parse(init.body);
                    if (b && b.client_id) reqCid = String(b.client_id);
                  }
                } catch (e) {}
                var p = origFetch.apply(this, arguments);
                try {
                  if (url.indexOf('/authenticate') !== -1 || url.indexOf('/oauth/token') !== -1 || url.indexOf('/token') !== -1) {
                    Promise.resolve(p).then(function(res) {
                      if (!res || !res.ok) return;
                      res.clone().text().then(function(txt) {
                        try {
                          var j = JSON.parse(txt);
                          var tok = j && (j.access_token || j.accessToken || j.token || j.id_token || (j.data && j.data.access_token));
                          var rt = (j && j.refresh_token) || '';
                          if ((tok && tok.length > 40) || rt) {
                            aisSaBridge.onToken(tok || '', rt, reqCid);
                          }
                        } catch (e) {}
                      }).catch(function(){});
                    }).catch(function(){});
                  }
                } catch (e) {}
                return p;
              };
            }

            var host = location.hostname || '';
            var url = location.href || '';
            if (host.endsWith('stableaudio.com') && !host.startsWith('login.') && host.indexOf('authkit.') === -1) {
              var scan = function(st) {
                for (var i = 0; i < st.length; i++) {
                  var k = st.key(i) || '';
                  var v = (st.getItem(k) || '').trim();
                  if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(v)) return { at: v, rt: '' };
                  if (k.toLowerCase().indexOf('workos') !== -1 && k.toLowerCase().indexOf('refresh') !== -1 && v.length > 12) {
                    return { at: '', rt: v };
                  }
                  try {
                    var p = JSON.parse(v);
                    var t = (p && p.body && p.body.access_token) || (p && p.access_token) || (p && p.accessToken) || (p && p.token);
                    var rt = (p && p.body && p.body.refresh_token) || (p && p.refresh_token) || '';
                    if ((t && t.length > 40) || (rt && rt.length > 12)) return { at: t || '', rt: rt || '' };
                  } catch (e) {}
                }
                return null;
              };
              var found = scan(localStorage) || scan(sessionStorage);
              if (found && found.at) { aisSaBridge.onToken(found.at, found.rt, ''); return; }
              if (found && found.rt && url.indexOf('code=') === -1) { aisSaBridge.onToken('', found.rt, ''); return; }
            }

            if (!cfg.auto) return;
            var st = window.__aisSaState;
            var now = Date.now();
            var setVal = function(el, val) {
              if (!el) return;
              el.focus();
              var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              if (setter) setter.call(el, val); else el.value = val;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            };

            if (host.endsWith('stableaudio.com') && !host.startsWith('login.') && host.indexOf('authkit.') === -1) {
              if (url.indexOf('/terms') !== -1 || url.indexOf('onboarding') !== -1) {
                if (now - st.termsAt < 5000) return;
                st.termsAt = now;
                document.querySelectorAll('input[type="checkbox"], [role="checkbox"]').forEach(function(el) {
                  if (!(el.checked === true || el.getAttribute('aria-checked') === 'true')) el.click();
                });
                var tbtn = Array.from(document.querySelectorAll('button')).find(function(b) {
                  return /accept|agree|continue|get started/i.test(b.innerText || '');
                }) || document.querySelector('button[type="submit"]');
                if (tbtn) tbtn.click();
                return;
              }
              if (url.indexOf('code=') !== -1 || url.indexOf('workspace-next') !== -1) return;
              if (now - st.signupAt < 8000) return;
              var btns = Array.from(document.querySelectorAll('button, a')).filter(function(el) {
                return /^\s*(start\s*free|sign\s*up)\s*$/i.test(el.innerText || el.textContent || '');
              });
              var vis = btns.find(function(el) { return el.offsetParent !== null; });
              if (vis) { st.signupAt = now; vis.click(); return; }
              var menu = document.querySelector('button[aria-label="Open menu"]');
              if (menu && menu.offsetParent !== null && menu.getAttribute('aria-expanded') !== 'true') {
                menu.click();
              }
              return;
            }

            var emailEl = document.querySelector('input[name="email"], input[type="email"], input[autocomplete="email"]');
            var passEl = document.querySelector('input[name="password"], input[type="password"]');
            var otpEl = document.querySelector('input[name="code"], input[autocomplete="one-time-code"], input[data-input-otp], input[maxlength="1"], input[maxlength="6"]');

            if (otpEl || url.indexOf('email-verification') !== -1 || url.indexOf('verify') !== -1) {
              if (cfg.otp) {
                if (now - st.otpAt < 6000) return;
                st.otpAt = now;
                var code = cfg.otp;
                var all = Array.from(document.querySelectorAll('input')).filter(function(el) {
                  var t = (el.getAttribute('type') || '').toLowerCase();
                  return t !== 'hidden' && t !== 'checkbox' && t !== 'radio';
                });
                if (all.length === 6) {
                  for (var i = 0; i < 6; i++) setVal(all[i], code[i]);
                }
                var single = document.querySelector('input[autocomplete="one-time-code"], input[name="code"], input[data-input-otp], input[inputmode="numeric"]') || (all.length === 1 ? all[0] : otpEl);
                if (single) setVal(single, code);
                var pasteTarget = single || all[0] || document.querySelector('[data-input-otp-container], form');
                if (pasteTarget) {
                  try {
                    var dt = new DataTransfer();
                    dt.setData('text/plain', code);
                    pasteTarget.dispatchEvent(new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }));
                  } catch (e) {}
                }
                setTimeout(function() {
                  var btn = document.querySelector('button[type="submit"], button.ak-PrimaryButton') ||
                    Array.from(document.querySelectorAll('button')).find(function(b) { return /verify|continue|confirm|submit/i.test(b.innerText || ''); });
                  if (btn) btn.click();
                }, 400);
              } else if (!st.otpAsked) {
                st.otpAsked = true;
                aisSaBridge.needOtp();
              }
              return;
            }

            if (passEl && passEl.offsetParent !== null) {
              if (now - st.passAt < 6000) return;
              st.passAt = now;
              if (!passEl.value) setVal(passEl, cfg.password);
              setTimeout(function() {
                var btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
                if (btn) btn.click();
              }, 350);
              return;
            }

            if (emailEl && emailEl.offsetParent !== null) {
              if (now - st.emailAt < 6000) return;
              st.emailAt = now;
              var fn = document.querySelector('input[name="first_name"], input[name="firstName"]');
              var ln = document.querySelector('input[name="last_name"], input[name="lastName"]');
              if (fn && !fn.value) setVal(fn, 'Alex');
              if (ln && !ln.value) setVal(ln, 'Carter');
              if (!emailEl.value) setVal(emailEl, cfg.email);
              setTimeout(function() {
                var btn = document.querySelector('button.ak-PrimaryButton, button[type="submit"]');
                if (btn) btn.click();
              }, 350);
            }
          } catch (e) {}
        })($cfgJson);
        """.trimIndent()

        webView.evaluateJavascript(js, null)
    }

    inner class JsBridge {
        @JavascriptInterface
        fun onToken(accessToken: String, refreshToken: String, clientId: String) {
            main.post {
                if (clientId.isNotEmpty()) lastClientId = clientId
                emitToken(accessToken, refreshToken, clientId)
            }
        }

        @JavascriptInterface
        fun needOtp() {
            main.post {
                if (otpRequested || finished) return@post
                otpRequested = true
                saChannel?.invokeMethod("pollStableAudioOtp", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        val code = result as? String
                        if (!code.isNullOrEmpty()) {
                            otpCode = code
                            injectHookAndStep()
                        }
                    }
                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (this::webView.isInitialized && webView.canGoBack()) {
            webView.goBack()
            return
        }
        completeAndClose(null)
    }

    override fun onDestroy() {
        main.removeCallbacks(ticker)
        if (!finished) {
            finished = true
            finishWith(null)
        }
        if (this::webView.isInitialized) {
            webView.destroy()
        }
        super.onDestroy()
    }
}

