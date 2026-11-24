# Build All Apps - one run, Android + Windows

`.github/workflows/build-all.yml` builds **everything in a single Actions run**:
the Android APK (`app/`) and the Windows desktop app (`desktop/`), optionally
Linux + macOS too.

## One-time setup

1. Create **one** GitHub repository (private is fine).
2. Push the **whole bundle** to it - the repo root must contain the `desktop/`
   and `app/` folders side by side (plus `index.html`, `zedge1..4.yml`, ...).
3. Set `BUILD_PROFILE` at the top of `.github/workflows/build-all.yml`
   to your profile (`shawon` / `tarek` / ...). It is compiled into the
   desktop app and used in the artifact file names.
4. For a properly signed APK (so users can update in place), add the four
   repository secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
   `KEY_PASSWORD`. Without them the workflow generates a throwaway keystore
   and the APK is still installable for testing.

## Build

- GitHub -> **Actions** -> **Build All Apps** -> **Run workflow** ->
  pick targets (`android+windows` is the default) -> **Run workflow**.
- When it finishes, open the run -> **Artifacts**:
  - `MetaHawladar-<profile>-v<version>-release.apk` - Android (min API 26)
  - `MetaHawladar-<profile>-windows-x64-setup-v<version>` - Windows installer
    (recommended: Next -> Install; unsigned, so SmartScreen may ask for
    *More info -> Run anyway*)
  - `MetaHawladar-<profile>-windows-x64-v<version>` - Windows portable zip
    (extract + run `MetaHawladar.exe`)
- Pick `all` as the target to also build Linux (tarball) and macOS.

## Release

`git tag v27.13.0 && git push --tags` -> **one** GitHub Release with the APK
and every desktop build attached.

## Notes

- The two old per-folder workflows
  (`desktop/.github/workflows/build-desktop.yml`,
  `app/.github/workflows/release-apk.yml`) still work if you push each folder
  as its own repo. GitHub only reads workflows from the repo root's
  `.github/workflows`, so they are ignored when you use `build-all.yml`.
- Desktop version comes from `desktop/pubspec.yaml` (`version: x.y.z+b` -
  bump it for every new build). APK version comes from
  `app/app/build.gradle.kts` (`versionName`).
- The first run also compiles everything for the first time: the
  **Analyze** step (`flutter analyze`) runs before the Windows build - if it
  reports errors, copy the red lines from the log into the chat.
