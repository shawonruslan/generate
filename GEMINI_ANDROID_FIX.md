# Gemini "not signed in" on Android — root cause + fix (v1.19.1+44)

## Symptoms (his screenshots, 2026-11-27)

- Generate image, Image to Prompt, metadata / prompt generation — every
  Gemini-web feature fails on Android with:
  "Gemini is not signed in inside the app's own browser profile
  (signing in to Gmail in your normal Chrome does not count)…"
  `client_error / UNEXPECTED`
- Settings → Test on a pasted Playwright session (13 cookies, auth:
  SID, SSID, APISID, SAPISID, __Secure-1PSID, __Secure-3PSID) → FAIL,
  same message.
- The same build works on Windows. Gemini HD Studio (Chrome extension)
  works easily on the same account.

## Root cause (proven from the code)

1. **Android had no in-browser fallback; Windows does.**
   `GeminiSessionManager.browserTransport` returned a transport only for
   desktop Chromium and **null on Android**. The flow on Android was:
   copy cookies out of the built-in Gecko browser (or use the pasted
   session) → replay them with plain Dart HTTP → Google answers the
   `/app` page **without the `SNlM0e` token** (copied-cookie replay is
   refused) → session declared "expired" → refresh re-copies the same
   cookies → same refusal → dead end, and the final error wrongly
   blamed the browser profile ("not signed in").
   On Windows, when the copy is refused, the client escalates to
   running the request **inside real Chrome** (`ChromiumBrowser`
   page transport) — so it works there.

2. **Gemini HD Studio never copies cookies.** Its `getGeminiSession()`
   does `fetch("https://gemini.google.com/u/0/app", {credentials:
   "include"})` from inside Chrome itself — the browser's own cookie
   jar, origin and TLS. That is why it "just works".

3. **Contributing trap in his Settings screenshot:** "Renew cookies
   from the app" was ON for a browser/pasted session that is also used
   in a browser. The code's own comment warns this makes Google end
   the session: app-side RotateCookies rotates `__Secure-1PSIDTS` out
   from under the browser copy.

## Fix

- **Android page transport (the main fix):** requests can now run
  inside a signed-in `gemini.google.com` tab of the app's built-in
  GeckoView browser — the exact twin of the Windows Chromium
  transport and of HD Studio's in-Chrome fetch.
  - New content script `gemini_bridge.js` (gemini.google.com only):
    runs the fetch in the page, `credentials: "include"`, FormData
    file upload, image responses as base64.
  - `background.js`: new `gfetch` relay between the native port and
    the Gemini tab; cookie name list gained `__Secure-1/3PSIDRTS`.
  - `GeckoBridge.kt`: `geminiFetch` + a hidden, kept-alive Gemini tab
    (`ensureGeminiTab`); `MainActivity.kt` routes the channel call.
  - Dart: `AndroidGecko.geminiFetch` + `GeckoGeminiTransport`
    (`lib/browser/gecko_gemini_transport.dart`), wired as
    `GeminiSessionManager.browserTransport` on Android. Flow is now:
    copied cookies first → if Google refuses, the request moves into
    the browser tab and `preferBrowser` makes later calls go straight
    there (same as Windows).
- **Rotation guard:** `rotateCookies()` no longer runs for sessions
  that came from a browser ('Built-in browser' / 'Browser profile' /
  'Chromium profile'), even if the Settings toggle is ON.
- **Honest errors:** the final failure message now reports what Google
  actually answered (HTTP status, page size, final URL, missing
  `SNlM0e`) and states both checks that failed, instead of always
  claiming the profile is signed out.

## What he must do once after installing v1.19.1

1. Settings → Gemini web session → **Sign in** (the app's own built-in
   browser) → sign in to Google → wait until Gemini itself opens.
   Signing in to Gmail in Chrome / the Gmail app does **not** sign in
   this profile — that part of the old message was true.
2. Turn **OFF** "Renew cookies from the app" (recommended setting).
3. Tap **Test** — it should now pass via the in-browser request even
   if the copied cookies are refused.

## Verification

- Dart files format/parse-checked; JS syntax-checked (`node --check`);
  manifest JSON validated; Kotlin reviewed against the existing
  GeckoBridge request/port plumbing (same id-correlated mechanism as
  the working cookie read and picture fetch).
- NOT compiled (no Flutter SDK on the build VM — CI `flutter analyze`
  is the real check) and NOT live-tested on a phone. First live test:
  install, do the one-time built-in-browser sign-in, Test in Settings,
  then one Image to Prompt item. If Test still fails, the new error
  text now contains the real Google response detail — send a
  screenshot of it.
