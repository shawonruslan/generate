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

## v1.3.0 — Gemini Fast (Gemini HD Studio pipeline)

Open with the ⚡ button on the home screen. Uses the Gemini web session from Settings (same as Gemini HD Studio), not the Cloudinary generate + polling route.

- **Text to image** – one `StreamGenerate` call, then the full-res `=s0` image.
- **Image to image** – Gemini upload (`push.clients6.google.com`, ~1–2 s) + one `StreamGenerate` call with the image attached.
- **Image to prompt** – upload + Gemini describes the image as one detailed prompt; "Generate from this prompt" sends it to text-to-image.
- **AI Upscale** – Gemini HD Studio method: aspect pre-crop → upload to *your* Cloudinary → `f_jpg,w_512,e_upscale,q_auto` (fast 4x) → exact JPG (9:16 = 1620×2880, ≤ 8 MB). "Fast upscale" off = full `e_upscale` on the original.
- Timings for every step are shown under the Generate button.

Files: `lib/gemini_image.dart`, `lib/local_upscale.dart`, `lib/screens/gemini_fast_screen.dart`, `test/gemini_image_test.dart`.

## v1.4.0 — Google sign-in + multi-account (Gemini HD Studio parity)

- **Settings → Sign in with Google**: in-app Google login (Android WebView / Windows WebView2, desktop Chrome UA). When gemini.google.com opens, the login cookies are saved as the Gemini session automatically — no manual cookie export. "Re-sync login" refreshes an expired session.
- **+ Add Gmail** (accounts.google.com/AddSession, like the extension), **Scan accounts** (u/0–u/5 in parallel), **account picker** (Auto or a specific u/N) and **Auto-switch account on image limit** (quota / 429 / "reached your limit" → next account, image re-uploaded there).
- **Batch → Gemini engine (fast)**: sets are generated by Gemini (anchor = text-to-image, every next stage = image-to-image from the previous frame, 1:1 companions too); each =s0 original is stored in your Cloudinary so export presets, upscale, ZIP and panel upload work unchanged. No 4 s Cloudinary submit throttle.
- Gemini metadata / Set Director now use the selected account.
- Cookie paste stays under "Advanced" as a fallback.
