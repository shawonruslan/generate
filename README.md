# Automation Hub · Zedge Content Studio — Flutter Desktop

Native Flutter desktop port of the web control panel (`index.html` of the
`tarek-automation`, `shawon-vpn`, `shimul-vpn` and `tamplate-vpn` bundles).
**No WebView** – every screen, dialog, calculation and Firebase/R2/GitHub
call of the web panel is re-implemented in Dart.

One code base; each customer bundle ships with its own profile (Firebase
accounts, R2 worker URL, Google-Calendar key, default upload windows) in
`lib/config/profile_data.dart`. Other profiles can be added there and selected
with `--dart-define=BUILD=<id>`.

## Requirements

* Flutter **3.27 – 3.35** (Dart ≥ 3.6) with desktop support enabled. Newer stables make `IconData` final and break `font_awesome_flutter` 10.x – the CI workflow pins `3.35.x` for that reason
  (`flutter config --enable-windows-desktop` / `--enable-linux-desktop` / `--enable-macos-desktop`).
* Windows: Visual Studio 2022 with "Desktop development with C++".
  Linux: `clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev`.
  macOS: Xcode.
* Optional command-line tools (looked up on `PATH` at runtime):
  * `ffmpeg` + `ffprobe` – video thumbnails (5 frame chooser) for Live Wallpaper / Charging Animation uploads.
  * `unrar` or `7z` – Smart Archive Import of **.rar** files (`.zip` is handled natively).
* Network access to Firebase RTDB, the Cloudflare R2 worker and `api.github.com`.

## Build on GitHub (no Flutter on your PC) — recommended

Same flow as the Android APK (`app/.github/workflows/release-apk.yml`):

1. Create a GitHub repository and push this folder (`desktop/`) to it – the
   folder as the repo root, or the whole bundle; the workflow finds `pubspec.yaml`.
2. GitHub → **Actions** → **Build Desktop App** → **Run workflow**
   (choose *windows*, *windows+linux* or *all*).
3. Open the finished run → **Artifacts** → download
   `MetaHawladar-<profile>-windows-x64-setup-v<version>` → inside is the
   **Windows installer** (`...-setup-v<version>.exe`, Inno Setup) → run it →
   Next → Install (Start-menu + Desktop shortcut, uninstall from *Apps &
   features*, in-place upgrade). The portable
   `MetaHawladar-<profile>-windows-x64-v<version>.zip` (extract → run
   `MetaHawladar.exe`) is uploaded next to it.
4. Optional: `git tag v27.9.0 && git push --tags` → a GitHub **Release** with
   Windows / Linux / macOS builds attached.

No secrets are needed. The profile compiled in comes from `BUILD_PROFILE` at the
top of `.github/workflows/build-desktop.yml` and from `lib/config/profile_data.dart`
(this bundle ships with only its own Firebase / R2 profile there).

## Build locally

```bash
cd desktop
flutter create . --platforms=windows,linux,macos   # generates the platform runners once
flutter pub get
flutter analyze
flutter run -d windows                              # uses kDefaultProfileId
flutter build windows --release                     # build/windows/x64/runner/Release/
```

Windows installer locally (needs [Inno Setup 6](https://jrsoftware.org/isinfo.php)):
```
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=27.10.2 /DMyProfile=<profile> installer\windows.iss
```
→ `build/installer/MetaHawladar-<profile>-windows-x64-setup-v27.10.2.exe`
(script + wizard bitmaps in `installer/`).

Copy the whole `Release` folder – it contains the `.exe`, `flutter_windows.dll`,
plugins and the `data/` dir.

> **Note** – this project was written without a Flutter SDK at hand, so the
> first CI run is also its first compile. If **Analyze** fails, copy the error
> lines into the chat and they will be fixed; the logic is a 1:1 port of
> `main.js`, so keep the behaviour when you touch it.

## Feature map (web panel → Flutter)

| Web tab / widget | Dart |
|---|---|
| Header, account switcher, live ticker, notification bell, sidebar (collapse/drawer), Theme FAB | `lib/ui/shell/app_shell.dart` |
| Home (greeting, today's run timeline, stats, metadata alerts, failed uploads, recent files, toolkits) | `lib/ui/screens/home_screen.dart`, `widgets/run_timeline.dart`, `widgets/sections.dart` |
| Upload Queue (media drop, Z-Meta JSON book, Smart Archive Import, 24H/Dual/Battery sets, video with ffmpeg frame chooser, filters, bulk delete, pagination) | `lib/ui/screens/upload_queue_screen.dart` |
| Schedule Calendar (run slots window/exact, cron health, Mix Mode, 7/14/28-day calendar with drag-&-drop pins, day picker) | `lib/ui/screens/schedule_screen.dart`, `dialogs/day_picker.dart` |
| Pin Manager | `lib/ui/screens/pins_screen.dart` |
| Distribute Content (round-robin over accounts, set mode, archive import) | `lib/ui/screens/distribute_screen.dart` |
| GitHub Control (PAT, session cookies, ringtone generator & metadata workflows, runs, files, log) | `lib/ui/screens/github_screen.dart`, `data/github_api.dart` |
| VPN (modes, profiles, editor with .ovpn/.conf/.json analysis, per-account GitHub, 5-stage test) | `lib/ui/screens/vpn_screen.dart`, `domain/vpn.dart` |
| Notifications page | `lib/ui/screens/notifications_screen.dart`, `state/notifications.dart` |
| Asset details page, device-frame phone preview, auto presentation, focus zoom, v27 Mobile preview (Aurora/Dark/Light/Blur, size, lock screen, fullscreen) | `lib/ui/dialogs/asset_details.dart`, `widgets/phone_mockup.dart` |
| Verified delete overlay (v19 R2 purge) | `lib/ui/dialogs/purge_overlay.dart`, `data/queue_repository.dart` |
| Theme Studio (presets, colours, font, radius, density, element colours, save per/all accounts) | `lib/ui/dialogs/theme_studio.dart`, `domain/theme_engine.dart` |
| Dhaka time, special days / holidays, gate hash & run prediction, schedule planner | `core/dhaka_time.dart`, `domain/special_days.dart`, `domain/run_schedule.dart`, `domain/schedule_planner.dart` |
| Firebase RTDB (REST + SSE streaming), R2 worker, archive reader | `data/firebase_rtdb.dart`, `data/r2_client.dart`, `data/archive_reader.dart` |

Local state that the web kept in `localStorage` (theme, element colours,
notifications, GitHub PAT/session, preview device, presentation speed,
sidebar state, meta-alert opt-in) lives in `shared_preferences`.

## Layout

The UI is fully responsive: sidebar collapses to icons below 1200 px and
becomes a drawer below 900 px; every grid uses auto-fit columns, so
16:9, 16:10, 21:9 ultra-wide, 4:3 and portrait windows all work. Minimum window
size is 720 × 520.

## Firebase rules

Like the web panel, the app talks to the Realtime Database over REST without
authentication – the databases must keep the same open read/write rules the
web panel relies on.
