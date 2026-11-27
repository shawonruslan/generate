# Ringtone Studio: request-only HTTP update

This update supersedes the Chromium/desktop-view workaround. Ringtone account creation and rotation no longer invoke a WebView, GeckoView, Chrome/CDP, a native sign-in channel, or any browser fallback.

## Captured flow implemented

The latest supplied HAR contains the missing OTP, code exchange, and audio-render requests. The implementation follows these routes:

| Step | HTTP request |
| --- | --- |
| Fresh authorization with PKCE S256 | `GET https://api.workos.com/user_management/authorize` |
| Hosted authorization session | Follow HTTPS redirects to the AuthKit host's `/bootstrap` and `/sign-up` |
| Name/email submission | `POST /sign-up`, multipart React server action |
| Password submission | `POST /sign-up/password`, multipart React server action |
| Email verification | `POST /email-verification`, using the current session's pending token and a newly received OTP |
| Callback discovery | Read `/success` and its `clientRedirect` value |
| Code exchange | `POST https://api.workos.com/user_management/authenticate`, `grant_type: authorization_code`, fresh `code_verifier` |
| Token renewal | Same endpoint, `grant_type: refresh_token`; save the rotated refresh token |
| Account terms | `PATCH https://api.stableaudio.com/v1alpha/user`, only after explicit confirmation |
| Credits | `GET https://api.stableaudio.com/v1alpha/user/balance` |
| Generate | `POST https://sessions-api.stableaudio.com/agents/wizard/compose-from-plan` |
| Poll | `GET /agents/wizard/status/{job_id}` |
| Result | `GET /agents/wizard/result/{job_id}` |
| WAV | Use the returned authenticated stem route, e.g. `/agents/wizard/stems/{job_id}/item-0` |

The temporary-mail providers already used by the project supply the email address and OTP. The code does not access any Yahoo Mail session captured in the HAR.

## How to use

1. Rebuild and reinstall the app from this source archive, using the existing Android GitHub Actions workflow or the README's local build process.
2. Open **Ringtone Studio -> Stable Audio account**.
3. Use **Create account (HTTP)** or **Rotate token**. Progress appears in the existing studio log; the account panel displays a busy indicator and disables account controls during the operation.
4. If the new account requires terms acceptance, review the terms and choose **Accept terms (required)**. This is an explicit per-account confirmation; marketing opt-in remains false.
5. Generate audio as usual. Generation, polling, result retrieval, and WAV download are HTTP requests.

Existing accounts can still be connected by pasting token JSON, an access token, or a refresh token. A refresh token can be exchanged even without a pasted access token.

## Dynamic/session handling

- PKCE verifier, challenge, and OAuth state are freshly generated for each attempt.
- Server-action IDs are discovered from live AuthKit HTML/React Flight records, including split HTML-embedded Flight chunks. They are not copied from the HAR.
- Session IDs, pending verification tokens, redirects and hidden fields come from the current response.
- Cookies are isolated per authentication attempt, with HTTPS/domain/path/expiry checks and bounded manual redirect following.
- Callback origin and state must match before exchanging an authorization code.
- Concurrent account creation and rotation are deduplicated. A failed creation restores the original saved account.
- Captured passwords, OTPs, cookies, device fingerprints, authorization codes and tokens are not embedded in the source or tests. No raw HAR is bundled.
- No additional dependencies were added; the client uses the project's existing `http` and `crypto` packages.

## Important limitation: HTTP is not a browser

The HAR includes AuthKit browser signals (canvas/WebGL and other fingerprint information) and a fingerprint-signing call. A native HTTP client cannot truthfully provide browser-only signals. This implementation sends no fabricated fingerprint and does not reuse the captured one. It omits fingerprint signing and sends an empty signals field on signup forms.

**Live server acceptance of fingerprint-free signup has NOT been established.** If AuthKit requires browser/device verification, rejects the temporary-mail domain, or changes its private web protocol, signup will fail with an explicit error. It will not secretly launch a browser, invent a security token, reuse captured credentials, or bypass a challenge. Existing-account token refresh and generation do not require this signup flow.

These are the web application's endpoints observed in the HAR, not a promise of an officially supported public signup API. A network block or server timeout can still affect direct requests.

## Validation actually performed

- **28 targeted Flutter tests passed** using Flutter 3.35.0 / Dart 3.9.0:
  - request-only signup through OTP/code exchange;
  - dynamic server actions across synthetic deployments;
  - PKCE/state validation, cookie separation, untrusted redirects, invalid OTP, and challenge failure;
  - HTML input/Flight parsing;
  - explicit terms handling, refresh-token rotation/deduplication;
  - HTTP generation -> polling -> result -> authenticated relative WAV download;
  - restoration of the original account when HTTP signup fails;
  - existing ringtone and legacy browser-bridge regression tests.
- The parser also read the actual supplied HAR response structures in an **offline mocked flow**, with fresh synthetic state/code/token values. No live request was made by that replay. This validates parsing, not acceptance of a different request by the real server.
- Flutter analysis of the modified production/test files reported **no errors or warnings**; informational style/deprecation lints remain.
- The existing Python Android packaging integration test passed.

Commands:

```sh
flutter pub get
flutter test test/stable_audio_http_auth_test.dart test/stable_audio_http_api_test.dart test/ringtone_feature_test.dart test/stable_audio_browser_startup_test.dart
python3 -m unittest discover -s android_native/tests -v
```

No live account was created, no live audio generation was submitted, and no credits were spent. A release APK and physical-device signup were not tested here. The archive contains source, not an APK.

Legacy browser source files remain for compatibility and the app's unrelated browser features, but Ringtone Studio's account service and screen no longer import or call the Stable Audio browser helper.
