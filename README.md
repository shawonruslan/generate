# AI Image Studio

Flutter app for **Windows** and **Android** that generates images with the
[Cloudinary Image Generation API](https://cloudinary.com/documentation/image_generation_api_reference)
— no web engine, fully native.

Features:

- **Text to Image** — prompt, 23 models (nano-banana, flux, recraft, gpt-image,
  ideogram, muse, mai-image, seedream, grok-imagine, qwen-image), aspect ratio
  (1:1, 16:9, 9:16, 4:3, 3:4), resolution (0.5K–4K), format, optional seed.
- **Image to Image** — same controls plus up to 4 reference image URLs and
  edit-model selection (`-edit` variants) or Auto mode. Mention references in
  the prompt as `[1]`, `[2]`, …
- **Batch Sets** (layers icon in the top bar) — paste multiple prompts and
  generate whole wallpaper sets in one run, mirroring the Drawstock pipeline:
  - **Single** — 1 image per prompt
  - **24-Hour** — 4 per prompt: Morning, Afternoon, Evening, Night
  - **Dual** — 2 per prompt: Lock (tight close-up) + Home (pulled-back wide)
  - **Battery** — 6 per prompt: 0%, 20%, 40%, 60%, 80%, 100% charge stages
  - 3-at-a-time worker pool, live progress with cancel, per-set result grids,
    retry for failed items, Save all with organized filenames.
- **Image to Prompt browser** (image-search icon in the top bar, or
  **Batch Sets → Prompts → From web images**) — Windows desktop and Android:
  - Opens a **real Chromium window** (Chrome / Edge / Brave / Chromium
    already installed on the PC) — no WebView, so browsing is as smooth as
    normal Chrome. The app drives it over the Chrome DevTools Protocol with
    its own profile (`%APPDATA%\...\chromium-profile`).
  - Hover any picture on any website → a **Prompt** icon appears; one
    click sends it to Gemini web (cookie session) and returns a detailed
    text-to-image prompt.
  - **Tick** as many pictures as you like (or **Select all**) and press
    **Generate prompts** in the bottom bar — they are processed **one by
    one**; every picture shows its live status (Queued → Analyzing →
    Prompt ready / Failed) right on the page.
  - **Android (v1.6):** the same tool runs in a built-in **GeckoView
    (Firefox engine)** browser that shares the Google sign-in. Open it,
    tap **Select pictures**, tap the pictures you want (links do not open
    while selecting), then **Generate prompts**. Press back to return to
    the app; prompts keep generating in the background and appear in the
    list / Batch Sets.
  - Gemini cookies: *Auto* uses the live gemini.google.com sign-in of the
    Chromium window (sign in there once), otherwise the session saved in
    Settings.
  - Finished prompts are listed in the app (copy / edit / regenerate) and
    are added to the **Batch Sets prompt list** automatically (toggle in
    Options) or with **Add to Prompts list**.
  - The Gemini instruction and the browser path can be customised.
- **Export presets** — `Original` or `1620x2880 JPG`: the JPG preset upscales
  every image to exactly 1620×2880 via a Cloudinary delivery transformation
  (`w_1620,h_2880,c_fill` + `f_jpg,q_100`) for preview, save, share and copy.
  (Tip: generate at 9:16 + 2K for the cleanest upscale.)
- **Download as ZIP** — the Batch screen's **ZIP** button packs every finished
  image into one archive (`set-01/morning.jpg`, `set-01/afternoon.jpg`, …)
  with disk-streamed encoding (memory-safe for large batches), then opens the
  share sheet.
- Async generation with live status (queued → processing → done) and exact
  Cloudinary error messages (category / code / message).
- Result preview with model / dimensions / seed / quota chips; Save, Share,
  Copy URL, Open in browser.
- Recent-generations history (kept on device).
- Credentials (cloud name, API key, API secret) stored in the OS secure
  storage; one-tap connection test that spends no quota.
- Day / night mode, professional Material icons (no emoji), responsive layout
  (single column on phones, two-column on wide desktop windows).

> The Image Generation add-on must be enabled on your Cloudinary account,
> otherwise the API returns an error.

## Build on GitHub (no local setup needed)

1. Create a new GitHub repository and push this folder as the repo root:
   ```bash
   git init
   git add .
   git commit -m "AI Image Studio v1.0.0"
   git branch -M main
   git remote add origin https://github.com/<you>/ai-image-studio.git
   git push -u origin main
   ```
2. GitHub → **Actions** → **Build AI Image Studio** → **Run workflow**
   (choose `windows+android`, `windows` or `android`).
3. When it finishes, open the run → **Artifacts** → download:
   - `AIImageStudio-windows-x64-setup-v1.0.0.exe` — Windows installer
     (Next → Install; Start-menu + Desktop shortcuts; uninstall entry).
   - `AIImageStudio-windows-x64-v1.0.0.zip` — portable (extract, run
     `AIImageStudio.exe`).
   - `AIImageStudio-v1.0.0-release.apk` — Android installer.
4. For a versioned **Release** with all files attached:
   ```bash
   git tag v1.0.0 && git push --tags
   ```
   Bump `version:` in `pubspec.yaml` before tagging the next release.

### Android signing (optional but recommended)

Without secrets the workflow signs with a throwaway key (APK installs fine,
but every build gets a new key so in-place updates won't work). For a stable
signature add these repository secrets (Settings → Secrets and variables →
Actions):

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 release.jks` of your keystore |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias |
| `KEY_PASSWORD` | key password |

Generate a keystore once with:

```bash
keytool -genkeypair -v -keystore release.jks -storetype PKCS12 \
  -alias aiimagestudio -keyalg RSA -keysize 2048 -validity 10000
```

## Project layout

```
pubspec.yaml                 Flutter project (v1.0.0+1)
lib/
  main.dart                  app root + theme mode state
  app_theme.dart             light / dark Material 3 themes
  models.dart                model catalog (23 text + -edit variants), ratios
  cloudinary_api.dart         REST client: generate, task polling, errors, quota
  secure_store.dart          OS secure storage (creds) + prefs (theme, history)
  screens/home_screen.dart   generator UI (tabs, form, result, history)
  screens/settings_screen.dart  credentials, connection test, help
  screens/browser_screen.dart   Image to Prompt browser UI (queue, prompts)
  browser/cdp.dart              Chrome DevTools Protocol client (WebSocket)
  browser/chromium_browser.dart finds / launches Chromium, injects overlay,
                                downloads pictures, reads Gemini cookies
  browser/overlay_script.dart   in-page overlay (Prompt icon, tick, dock)
  browser/image_prompt_service.dart  one-by-one queue, Gemini image->prompt,
                                Batch Sets prompt-list bridge
assets/icon/app_icon.png     master icon (CI generates all platform icons)
installer/windows.iss        Inno Setup 6 script for the Windows installer
.github/workflows/build.yml CI: windows installer + android apk + releases
```

## Local development (optional)

Install Flutter 3.35+ and run:

```bash
flutter pub get
# Icons are pre-generated and committed (assets/icon/) — nothing to run.
flutter run -d windows            # or: flutter run -d <android-device>
```

## Gemini cookies that stay alive (v1.4)

* **Auto-renew (Android + Windows):** the app renews the short-lived
  `__Secure-1PSIDTS` cookie itself (Google `RotateCookies`, like the Gemini
  web app does) and saves the renewed JSON back to Settings automatically.
* **One-time sign-in (Windows):** Settings → Gemini web session →
  **Sign in with Google**. A normal Chrome/Edge window (the app's own
  profile) opens; sign in, wait for Gemini, close the window. The cookie
  JSON is filled in and saved automatically.
* **Silent refresh (Windows):** when Google ends the session, the app starts
  that signed-in profile headless for a few seconds, opens Gemini, takes the
  fresh cookies and continues — no login again. Manual button:
  **Refresh from browser**.
* **Android (v1.5):** Settings → **Sign in with Google** opens a built-in
  browser that uses the **Firefox engine (GeckoView)**, not WebView, so
  Google allows the sign-in. Sign in once and it closes by itself when
  Gemini opens. The cookie JSON is saved automatically. When the session
  ends, the app reloads Gemini in that signed-in engine without showing it
  and takes the new cookies. You don't need to sign in again or copy anything from the PC.
* **Background generation (Android, v1.7):** while Batch Sets, a single
  image, metadata or the Image to Prompt queue is running, the app runs a
  foreground service with a "Generating..." progress notification and keeps
  a wake lock + Wi-Fi lock, so turning the screen off / sleep no longer
  stops the run. Network drops are waited out (up to 8 retries after the
  internet is back) and an already running Cloudinary task keeps being
  polled for up to 10 minutes of connection loss. For long runs allow
  **Settings → Background generation → Allow running in background**
  (some phones kill apps with battery optimisation anyway).
* Only the Google session cookies gemini.google.com needs are read (SID,
  __Secure-1PSID/-TS ...). They are kept on the device only.
* Android build: `android_native/patch_android.py` adds GeckoView to the generated
  `android/` runner (the CI workflow runs it). The APK is **arm64 only**,
  and GeckoView makes it larger.

## v1.8 - UI / UX redesign (mobile first)

- **Inter font** bundled (`assets/fonts`, SIL OFL) so every phone shows the same clean type.
- **New design system** (`lib/app_theme.dart`, `lib/widgets/ui_kit.dart`): 48 dp touch targets,
  rounded cards with icon headers, `ButtonGroup` (equal-width buttons, labels never wrap),
  `AppButton`, status pills, hints, step lists, empty states.
- **Image to Prompt**: compact cards with thumbnail + status pill, icon action row,
  tap a card for the full prompt in a bottom sheet (copy / edit / add), long-press to select.
  Gemini `[cite: N]` markers are stripped from prompts.
- **Settings / Home / Batch Sets**: short single-line button labels, grouped actions,
  56 dp primary Generate buttons.
- **Android built-in browser**: dark toolbar matching the app, custom line icons,
  rounded search pill, stop/reload toggle, thin accent progress bar; overlay buttons restyled.
- UI screenshots: `AIS_SHOTS=1 flutter test test/ui_screens_test.dart --update-goldens`
  (writes `test/shots/*.png`).

## v1.8.1 - Login popups in the Android browser

"Continue with Google" on Pinterest (and other OAuth popups) opened in the
same tab, so the opener page was gone and `accounts.google.com/gsi/transform`
stayed blank. New windows now open as real popups linked to their opener;
when sign-in finishes the popup closes itself and the page logs in.
The picture overlay is not shown on sign-in pages / popups.
