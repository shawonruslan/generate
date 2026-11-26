# Ringtone Rotate browser-loading patch

## Changes

- Android requests the Stable Audio browser immediately, before waiting for a temporary-mail provider. Mailbox preparation happens through a callback after browser launch, with a 90-second preparation timeout.
- Shows loading status, main-page network/HTTP errors, and a Retry button instead of leaving a blank WebView without feedback.
- Adds a one-time, guarded initial-navigation fallback if the cookie-clearing callback is delayed. A late callback does not clear storage after navigation has started.
- Enables third-party cookies needed by some authentication redirects and uses the installed WebView's actual user agent rather than hard-coded desktop Chrome 131.
- Guards overlapping sign-in/Rotate calls so a second click cannot replace the active callback handler.
- Aligns Android's overall timeout (240 seconds) with Dart's timeout (250 seconds), and cancels pending native timers when the activity closes.
- Keeps the existing direct email/password bridge arguments compatible. Desktop behavior is unchanged.

## Changed production files

- `lib/android_gecko.dart`
- `lib/ringtone/stable_audio_browser.dart`
- `android_native/kotlin/StableAudioWebViewActivity.kt`

## Validation performed

- Modified native activity compiled with Kotlin 2.3.21 against Android API classes, using a minimal Flutter MethodChannel stub. This is a compilation check, not a complete APK build.
- Modified Dart source and the added Flutter regression test parsed successfully with the Dart formatter.
- Isolated production Dart bridge checks passed with a test MethodChannel implementation: deferred preparation, token decoding, OTP callback, cleanup, repeated-click guard, cancellation, failure propagation, and subsequent retry.
- Injected browser JavaScript syntax checked with Node.js.
- Android packaging integration test passed. Running the build patch twice preserves a single activity registration, Internet permission, orientation handling, and the patched Kotlin source.

## Build and device verification

Use the project's existing Android GitHub Actions build to rebuild the APK. If building locally, first generate the Android runner as described in the existing README, then run `python3 android_native/patch_android.py` before building. Updating Dart files alone or hot reloading is not enough: the native Kotlin activity must be rebuilt and the APK reinstalled.

Additional tests included:

```sh
python3 -m unittest discover -s android_native/tests -v
flutter test test/stable_audio_browser_startup_test.dart test/ringtone_feature_test.dart
```

The Flutter test suite, complete APK build, and real Android/Stable Audio sign-in were **not run** in this environment. No live account was created. The source changes address identifiable startup and error-handling problems; they cannot guarantee availability of Stable Audio or external mail services.

On a device, check:

1. Ringtone -> Rotate token opens the browser before mailbox preparation completes.
2. The page and authentication redirects load on a working connection.
3. Offline loading produces a visible error; reconnecting and tapping Retry loads the page.
4. Repeated Rotate clicks do not replace the active browser request.
5. Done/Back cancellation allows a later Rotate attempt.
6. Existing browser sign-in and normal account rotation still complete.
