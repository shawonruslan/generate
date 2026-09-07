# Content Studio — Native Android (Kotlin + Jetpack Compose)

Fully native port of the Zedge automation dashboard. **No WebView, no HTML engine** — every
feature is re-implemented in Kotlin.

| Layer | Files |
|---|---|
| Core constants, real-time clock, type cycle | `core/Core.kt` |
| Firebase RTDB REST client (4 accounts - Shimul, server-time sync) | `data/FirebaseRtdb.kt` |
| Queue / upload state models | `data/Models.kt` |
| Media (EXIF-safe image read, video frame grab, JPEG thumbs) | `data/Media.kt` |
| Upload, sets, video, distribution, pins, copy-to-accounts, R2 gateway | `data/QueueRepository.kt` |
| GitHub Actions control (dispatch, runs, clean, repo browser, Gemini session cloud-sync) | `data/GitHubRepo.kt` |
| Publishing Layout Planner (type cycle, min-stock-3 rule, pinned overrides, overdue → today) | `domain/SchedulePlanner.kt` |
| Special days (Google Calendar IN/BD + Nager 36 countries, cached) | `domain/SpecialDays.kt` |
| Smart ZIP/RAR import (any set count, file-count auto-detect 2/4/6, folder=set, videos, ringtones) | `domain/ArchiveClassifier.kt` |
| Screens: Home, Upload Center, Planner, Pin Manager, Multi-Account Distribution, GitHub Control, Item detail | `ui/screens/*` |

## Build

1. Open this folder in **Android Studio Koala (2024.1) or newer**.
2. Let Gradle sync (needs internet the first time: AGP 8.5.2, Kotlin 2.0.20, Compose BOM 2024.09).
3. `Run ▶` on a device / emulator (Android 8.0+, API 26), or **Build → Build Bundle(s)/APK(s) → Build APK(s)**.
4. Release: **Build → Generate Signed Bundle / APK**.

Command line: `./gradlew assembleDebug` → `app/build/outputs/apk/debug/app-debug.apk`
(the wrapper jar is downloaded by Android Studio on first sync; if you build purely from CLI run `gradle wrapper` once).

## Notes

* Firebase / R2 / Google Calendar keys are the same ones the dashboard uses (see `core/Core.kt`,
  `domain/SpecialDays.kt`). Move them to `local.properties` + `BuildConfig` if you publish the APK.
* Share images / ZIPs / videos from any app → "Import to Content Studio" drops them into the Upload Center.
* The project was authored without an Android SDK on the authoring machine; if the first Gradle
  build reports a compile error, send the error text/screenshot and it will be fixed.
