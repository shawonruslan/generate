# Fix: "AuthKit did not advance to the next form" (v1.19.0+43)

Supersedes the request-only HTTP signup in `REQUEST_ONLY_FIX.md` for account
**creation**. Token refresh, rotation between saved accounts, credits, and
audio generation stay HTTP — those never needed a browser.

## What was failing (from the user's screenshot, 2026-11-26 23:48)

Ringtone Studio → Create account (HTTP):

```
[23:48:16] HTTP auth: starting a fresh PKCE authorization session.
[23:48:16] Created temp-mail inbox (https://api.mail.tm): quinncollinslppc04392@euploading.com
[23:48:17] HTTP auth: submitting signup details.
→ "AuthKit did not advance to the next form… No fingerprint was fabricated."
```

## Root cause, proven from the supplied HAR (successful browser signup)

Comparing the working browser flow in the HAR against
`stable_audio_http_auth.dart`, the first `POST /sign-up` differs in ways a
plain HTTP client cannot reproduce:

1. **The `signals` field is not optional.** The browser sends
   `_1_signals` = ~3.5 KB base64 JSON collected on the page by WorkOS's
   signals worker: canvas/audio/math/Intl/WebGL hashes, fonts, voices,
   `minimalSurface` hashes, a worker cross-check, timing data and
   `collectionState: "complete"`. The HTTP client sent `signals: ''`.
2. **A signing action runs before the form post.** The browser first POSTs
   action `408b9a…` with a single hash; the sealed payload it returns becomes
   the `__wuid` cookie that the real form post then carries (together with
   `__kduid`). The HTTP client never ran it and had neither cookie.
3. **Bot-shaped client headers.** The HTTP client identified itself as
   `User-Agent: RingtoneStudio/1.18 (native HTTP client)` and sent no
   `Next-Router-State-Tree` header, unlike the browser's server-action posts.

Any one of these is enough for AuthKit to keep the user on the first form —
and the old code threw away the response body, so the server's actual reason
was never shown. (A disposable mail.tm domain being refused at the same step
cannot be ruled out for that specific attempt either; the HAR's successful
signup used a Yahoo address. The browser flow below is the same flow the HAR
proves works with the app's temp-mail inboxes in earlier builds.)

## The fix

Account creation goes back to the browser flow that was already shipped in
this codebase but disconnected by the HTTP-only build:

- **Android:** `StableAudioBrowser.autoCreateAccount` →
  `AndroidGecko.autoCreateStableAudio` → `StableAudioWebViewActivity`
  (real WebView: AuthKit's own JS collects the real signals; the activity
  auto-fills name/email/password, polls temp-mail for the OTP, accepts the
  terms page, and captures access/refresh tokens).
- **Desktop (Windows/macOS/Linux):** the existing Chrome/Edge CDP automation
  in `stable_audio_browser.dart`.
- Wiring restored in `ringtone_service.dart`
  (`onAutoCreateAccount` + `rotateStableAudioAccount(createNew: true)`)
  and in `ringtone_screen.dart` (button is "Create account" again; the
  "Request-only mode / no browser opens" copy is gone).
- The HTTP signup stays only as a fallback on platforms with no browser
  engine, and it now **logs and reports the server's own error text**
  (`AuthKitHttpPage.serverMessages()`) instead of the generic guess.

## Not live-tested

No live account was created from this VM. The browser automation code is the
same code shipped in the pre-HTTP builds; the first real test is creating an
account in the rebuilt app. If creation still stalls, send a screenshot of
where the built-in browser stops — that screen, not the log, will show why.
