# Zedge Studio

Fully native **Flutter** desktop + mobile client for the Zedge upload automation
queue. One codebase builds:

| Platform | Artifact |
| --- | --- |
| Windows | `ZedgeStudio-Setup-<version>.exe` (Inno Setup installer) + `ZedgeStudio-<version>-windows-x64-portable.zip` |
| Android | `ZedgeStudio-<version>-android-universal.apk`, per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) and `ZedgeStudio-<version>-android.aab` |

## No WebView. At all.

There is no `webview_flutter`, no local HTML, no embedded browser anywhere in
this repo. Every screen is hand written Flutter UI:

* phone mock-up, notches and cut-outs -> `CustomPainter` + decorated boxes
* auto rotating wallpaper presentation -> `Timer` + `AnimatedSwitcher`
* calendar day cards -> `GridView` + `DragTarget`
* data layer -> **Firebase Realtime Database REST + Server-Sent Events**
  (`lib/services/rtdb_client.dart`)

FlutterFire's `firebase_database` plugin has **no Windows support**, so the app
speaks to RTDB over its plain HTTP API instead. Same code, same behaviour on
Windows and Android, and no `google-services.json` or Firebase plugin setup is
needed.

## Run the GitHub Action

1. Push this folder to a GitHub repo (public or private).
2. Open **Actions -> Build Windows + Android -> Run workflow**.
3. Wait ~10-15 minutes. Artifacts appear at the bottom of the run:
   `windows-build` and `android-build`.

Tagging also builds and publishes a GitHub Release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### The action sets up everything by itself

`android/` and `windows/` are intentionally **not** committed (see
`.gitignore`). On every run the workflow:

1. installs the Flutter SDK (cached), JDK 17 and the Android SDK,
2. runs `flutter create --platforms=android,windows .` to regenerate the native
   shells (hand written sources are backed up and restored around this step),
3. patches them with `tool/patch_platforms.py`
   (app label, permissions, `minSdk 23`, window title/size, `ZedgeStudio.exe`,
   optional release signing),
4. generates launcher icons from `assets/icon/`,
5. builds, renames and uploads every artifact.

So a fresh clone needs **zero local setup** to produce installable builds.

## Secrets (all optional)

The first run is green with **no secrets configured**.

| Secret | Effect if missing |
| --- | --- |
| `GOOGLE_CALENDAR_API_KEY` | India/Bangladesh holiday feeds stay off until a key is pasted in **Settings** inside the app |
| `ANDROID_KEYSTORE_BASE64` | APK/AAB are signed with the debug key (still installable) |
| `ANDROID_KEYSTORE_PASSWORD` | as above |
| `ANDROID_KEY_ALIAS` | as above |
| `ANDROID_KEY_PASSWORD` | as above |

Create an upload keystore locally and base64 it:

```bash
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
base64 -w0 upload.jks > upload.jks.b64   # macOS: base64 -i upload.jks -o upload.jks.b64
```

## Which APK should I install?

* Normal phone -> `arm64-v8a` (smallest, covers every modern device)
* Old 32-bit phone -> `armeabi-v7a`
* Emulator / Chromebook -> `x86_64`
* Not sure -> `universal`

## Local development

```bash
flutter pub get
flutter create --platforms=android,windows .
python tool/patch_platforms.py all
flutter run -d windows          # or: flutter run -d <android-device>
```

Pass the calendar key while developing:

```bash
flutter run -d windows --dart-define=GOOGLE_CALENDAR_API_KEY=YOUR_KEY
```

## Repo layout

```
lib/
  app_config.dart          accounts, R2 worker, DB paths, holiday config
  main.dart                window_manager setup + app root
  models/queue_item.dart    queue row + upload state models
  theme/app_theme.dart      gold palette, Material 3 theme
  services/
    rtdb_client.dart        RTDB REST + SSE (auto fallback to polling)
    r2_service.dart         Cloudflare R2 worker uploads
    holiday_service.dart    Google Calendar (IN/BD) + Nager (rest), 7-day cache
  state/app_state.dart      single ChangeNotifier store
  screens/                 dashboard, queue, schedule, settings
  widgets/                 phone preview, queue card, editor, uploader
.github/workflows/build.yml  the whole CI pipeline
tool/patch_platforms.py      native shell patcher
installer/zedge_studio.iss   Inno Setup script for the Windows installer
```

## Note (Banglish)

* Action ekbar run korlei sob setup nije kore - tumi kichu install korte hobe na.
* Kono WebView nai, puro Flutter native code.
* Windows e `.exe` installer + portable zip, Android e `.apk` + `.aab` pabe.
* Google Calendar key ta app er **Settings** theke o dite paro, build e na dilew cholbe.
* Purono ja key chat e paste korecho ta rotate kore niyo.

## Troubleshooting

**`CMake Error ... Generator Visual Studio 16 2019 could not find any instance of Visual Studio`**
The Windows job is pinned to `windows-2022` on purpose: VS 2022 (major 17) is the
newest toolchain Flutter 3.24 can translate into a CMake generator. On
`windows-latest` a newer Visual Studio is installed, Flutter cannot map it and
falls back to the 2019 generator, which does not exist on the image. If GitHub
ever retires the `windows-2022` image, either bump `flutter_version` to a
release that knows the newer Visual Studio, or let the
"Align Flutter with a newer Visual Studio" step handle it.

**`PathNotFoundException: android/app/src/main/AndroidManifest.xml` during icon generation**
The icon config covers Android and Windows, so the Windows job generates both
native shells. The icon steps are also `continue-on-error`, so a bad icon run
can never fail a build.

**Plugin requires Android SDK 35**
`tool/patch_platforms.py` forces `compileSdk = 35` (and `minSdk = 23`) into the
generated Gradle file.
