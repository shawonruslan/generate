# v27.12.0 - Desktop app (Windows / Linux / macOS) - Flutter

The web panel (`index.html`) is now also a **native desktop application** in the
`desktop/` folder - Flutter, no WebView. Every tab, dialog, calculation and
Firebase / R2 / GitHub call of the panel is re-implemented: Home, Upload Queue
(Z-Meta JSON, Smart Archive Import, 24H / Dual / Battery sets, video with frame
chooser), Schedule Calendar (slots, cron health, Mix Mode, drag-&-drop pins),
Pin Manager, Distribute, GitHub Control, VPN, Notifications, Asset details with
phone preview / auto presentation / focus zoom / Mobile preview, verified R2
delete, Theme Studio (synced with the app + web panel through
`dashboardSettings/theme`).

This bundle's profile (`zakir`) - Firebase accounts, R2 worker URL, calendar key,
default upload windows - is compiled in from `desktop/lib/config/profile_data.dart`
(same values as the top of `index.html`). Keep both in sync when you change keys.

## Build it on GitHub - exactly like the Android APK

The Android app has `app/.github/workflows/release-apk.yml`; the desktop app has
`desktop/.github/workflows/build-desktop.yml`. Nothing to install on your PC.

1. Create a new GitHub repository (private is fine).
2. Push the **`desktop` folder** to it - either the folder contents as the repo
   root, or the whole bundle; the workflow finds `pubspec.yaml` by itself.
   (Push it as a separate repo from `app/` so the two workflows stay simple.)
3. Repo -> **Actions** -> **Build Desktop App** -> **Run workflow** ->
   pick *windows* (default), *windows+linux* or *all* -> **Run**.
4. Wait ~10-15 min. Open the run -> **Artifacts**. Two Windows downloads:
   * `MetaHawladar-zakir-windows-x64-setup-v27.12.0` -> **Windows installer**
     (recommended). Unzip the artifact, run
     `MetaHawladar-zakir-windows-x64-setup-v27.12.0.exe` -> Next -> Install.
     It installs to Program Files (or the per-user *Programs* folder when you
     pick "only for me" - no admin needed), adds Start-menu + Desktop
     shortcuts, an *Apps & features* entry with uninstaller, and upgrades in
     place when a newer version is installed later. The build is unsigned, so
     SmartScreen may show "Windows protected your PC" -> *More info -> Run
     anyway*.
   * `MetaHawladar-zakir-windows-x64-v27.12.0` -> **portable zip** (no install):
     extract anywhere and run `MetaHawladar.exe` (keep all files of
     the folder together - the dlls and `data/` are needed).
5. Releases: `git tag v27.12.0 && git push --tags` -> a GitHub Release with
   the Windows installer + portable zip + Linux + macOS builds attached
   (`generate_release_notes`).

No repository secrets are required. `BUILD_PROFILE: zakir` at the top of the
workflow picks the profile; the version in the file name comes from
`desktop/pubspec.yaml` (`version: 27.12.0+6` - bump it for every new build).

### First run of the workflow
The desktop project was written without a Flutter SDK on the authoring machine,
so the first Actions run is also its first compile. The **Analyze** step runs
`flutter analyze` before building - if it reports errors, copy the red lines
from the log into the chat and they will be fixed (same as the Android note in
`app/README.md`).

## Runtime requirements (the PC that runs the app)
- Windows 10/11 x64 - installer (`...-setup-v<version>.exe`, Inno Setup) or the
  portable extracted folder; both are produced by the workflow.
- Optional on `PATH`: `ffmpeg` + `ffprobe` (video cover-frame chooser for Live
  Wallpaper / Charging Animation), `unrar` or `7z` (Smart Archive Import of .rar;
  .zip works without them).
- Linux build additionally needs `libmpv` (`sudo apt install mpv`).
- Same open Firebase rules the web panel uses (REST + SSE, no auth).

## Local development (optional)
```
cd desktop
flutter create . --platforms=windows
flutter pub get
flutter run -d windows
```
See `desktop/README.md` for the full feature map (web tab -> Dart file).
