# Display name: AI Image Studio -> MH Content Making Studio (v1.19.8+51)

## His question (2026-11-27)

"apps and software e ekhono nam AI Image Studio dekhacche ken?"

## Why it still showed

This code line (the New_folder / generate-main source) never got the
rename the other build line received in v1.17.5. The old name was
hardcoded in the places that decide what the user sees:

- **Android icon label**: CI (build.yml) rewrote the manifest label
  to "AI Image Studio".
- **Windows**: CI rewrote Runner.rc FileDescription / ProductName /
  CompanyName and the main.cpp window title to "AI Image Studio";
  the Inno installer (windows.iss) had MyAppName "AI Image Studio".
- **In-app**: MaterialApp title, Home header, Settings About tile,
  share-sheet text, browser-overlay toasts, background-service
  notification title - all "AI Image Studio".

## Changed to "MH Content Making Studio"

- build.yml: Android label, Windows exe metadata + window title,
  exe file name (MHContentStudio.exe), artifact + release file
  names (MHContentStudio-...), workflow + release titles.
- installer/windows.iss: MyAppName / MyAppPublisher.
- lib/main.dart (app title), home_screen.dart (header),
  settings_screen.dart (About tile; also dropped its stale hardcoded
  "Version 1.16.2" subtitle), batch_screen.dart (share text),
  overlay_script.dart (toasts), MainActivity.kt + GenerationService.kt
  (notification title), GeckoBrowserActivity.kt (back-button label),
  pubspec description, README title.

## Deliberately NOT changed

- Dart package name `ai_image_studio` and the Android/Kotlin package
  `com.aistudio...` - internal identifiers in every import; changing
  them renames nothing the user sees and risks breaking the build.
- The CI signing keystore's certificate DN (build.yml -dname) - an
  internal signing identity, never displayed.

## Verification

- All touched Dart files format/parse OK; build.yml parses as valid
  YAML; grep confirms the only remaining "AI Image Studio" in
  code/CI is the keystore DN above.
- NOT compiled - CI is the real check. First look after install:
  launcher label, Windows title bar / installer, Home header and
  Settings About must all read MH Content Making Studio. Note:
  Android may keep showing the old label until the old install is
  replaced - a fresh CI build + reinstall is what updates it.

## Name corrected by him (v1.19.9+52)

Not "MH Content Making Studio" - the final display name is
**MH STUDIO**. Every occurrence changed (app title, Android label,
Windows metadata/installer, Home header, About, toasts,
notifications), and the file-name form became MHStudio
(MHStudio.exe, MHStudio-... artifacts).
