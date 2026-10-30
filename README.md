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

## v1.8.2 - Windows layout + fast Google sign-in

- Windows / tablets use the full window: Home 2 columns up to 1200 px, Batch Sets
  set-up | options side by side (>= 1000 px), Settings centred at 900 px.
- Phones: Home toolbar shows only the logo, so every button stays visible.
- Windows "Sign in": the sign-in window closes by itself as soon as Gemini opens
  (window title watch + graceful close, so Chrome saves the cookies), then the
  cookies are read straight from the profile without loading Gemini again
  (~2-3 s instead of waiting for the window to be closed + a Gemini page load).

## v1.9 - Pro prompts, layered sites, capture & snip

- **Professional instruction**: 9-layer image analysis (subject, setting, composition, camera/lens, lighting, colour, style/medium, texture, mood) -> one 120-200 word generation prompt. The old default is upgraded automatically; custom instructions are kept. Settings > Reset restores the new default.
- **Pinterest & layered sites**: picture detection now looks through overlay/cover layers (full element stack, open shadow roots, geometric scan, CSS background pictures). The hover bar sits top-left so it does not clash with site buttons (e.g. Pinterest Save).
- **Sharper source**: largest `srcset` candidate is used; Pinterest `236x` thumbnails are upgraded to `736x`.
- **Camera capture**: the camera button on the hover bar screenshots exactly what is on screen - works for locked/protected pictures, canvas and **video frames** (video is paused on the frame).
- **Snip area**: the "Snip" pill (bottom-left) or **Alt+Shift+S** lets you drag a rectangle anywhere on the page and turn that area into a prompt.
- **Locked picture fallback** (Windows): if a picture cannot be downloaded, the app screenshots it in the page automatically.
- **Android**: tap a video/canvas in select mode, or use Snip; captured through GeckoView `capturePixels`.

## v1.9.1 - Creative (copyright-safe) prompts

- The default Image-to-Prompt instruction is now **Creative**: it keeps the style, lighting, mood and colour harmony of the picture but changes at least four specific elements (subject identity, pose, background/props, camera angle, time of day, accent colours) and adds a fresh creative touch, so the generated image is original and never a one-to-one copy. Logos, text, recognisable characters, real people, brands and living artists are never named or copied.
- Saved v1.9 default instructions move to Creative once; custom instructions are kept.
- Instruction editor: **Exact copy** loads the faithful version, **Creative (default)** restores the new default.

## v1.9.2 - Foldable/tablet companion meets the store rule

The optional SINGLE-set companion is no longer 1:1 2000x2000. It now follows the store requirement:
JPEG only, **2800x2400 (7:6 = 1.4:1.2)**, max 25 MP, max 8 MB, and an **extension of the same artwork** as the portrait wallpaper.

- Generated via image-to-image from the portrait at 4:3 (closest widely supported ratio), resolution at least 2K.
- Prompt: the same artwork continued sideways - identical subject, palette, light and style, background extended left and right, hero centred with 12% side safe margin (no mirroring, bars or blurred fills).
- The app trims evenly to exactly 7:6, scales to 2800x2400 and encodes JPEG (quality 95, lowered automatically if needed to stay under 8 MB), in a background isolate.
- File name stays `wallpaper-landscape.jpg` next to `wallpaper` in each set folder.

## v1.10 - Smart originality + professional compare view

**Smarter Image to Prompt (less look-alike / copyright risk)**
- *Originality* level in Image to Prompt: Faithful / Balanced / Creative (default) / Bold.
- Every picture gets its own random **originality brief** (3 / 5 / 7 forced changes drawn from subject, pose, setting, time & weather, camera, colour, light, style and story-twist pools) plus a self-check ("a viewer must not think it is the same image").
- **Anti-repeat**: when a new prompt reads > 40 % like an earlier prompt of the session, Gemini rewrites it once with a "make it clearly different" note - a Pinterest board of look-alikes no longer gives look-alike prompts.
- **More original** (item sheet / compare view): rewrites a prompt at Bold level and adds it to the batch list again.
- A 768 px copy of every analysed picture is kept (app support folder `prompt_refs`) for later comparison - captures too.

**Originality check (compare view)**
- Opens from a batch result (*Originality check*), the home result (*Originality*) or an Image to Prompt item (*Check originality*, pick the generated file).
- The reference is found automatically from the prompt; *Change reference* picks another history item or any file.
- Creativity score ring + verdict (Original / Inspired - safe / Review - close / Too similar).
- Side-by-side, drag **slider** and **overlay** views.
- Pixel analysis breakdown: structure fingerprint (pHash + dHash), composition (SSIM), shapes (edge correlation), colour palette (HSV histogram), tone - mirror and zoom/crop copies are detected too. Dominant colour palettes of both images.
- **AI art-director review** (Gemini): similarity score, risk level, verdict, what is shared, what was changed, and advice. The overall score blends pixels 40 % + AI 60 %.

## v1.11 - Similarity target (choose how close the prompt stays)

- The Faithful / Balanced / Creative / Bold switch is replaced by a **Similarity target** (20-90 %, presets Near copy 90 / Close 75 / Balanced 60 (default) / Inspired 45 / Fresh 30). Old settings are migrated.
- The panel shows live what **stays the same** and what **will change**. 11 aspects are ranked from least to most defining (small props -> time & weather -> pose -> background details -> camera -> lighting -> colour -> setting -> subject design -> subject type -> style). Higher targets keep more of them.
- Why the old switch was sometimes ignored: the built-in instruction itself said "change at least four elements", which conflicted with the level. The default instruction is now neutral (professional 9-layer analysis + rules), and a **SIMILARITY TARGET** block is appended to every instruction, built-in or custom. It states the exact keep/change lists and overrides any closeness wording. Saved built-in instructions are upgraded automatically.
- Anti-repeat is now a switch and only runs for targets up to 75 %. It keeps the same target when it rewrites.
- Every prompt remembers its target. The compare view shows **Target vs measured** (on target / more different / closer) with *Less similar* and *Closer to reference* rewrite buttons.

## v1.14.0 - Gemini web image engine (no Cloudinary needed)

- Settings -> **Image engine**: Cloudinary or **Gemini web**. With Gemini web, every image (Home text / image to image, Batch anchors and chained variants) is drawn by your signed-in Gemini web session. No Cloudinary keys or credits needed.
- Same request as the Gemini page (StreamGenerate). The generated `gg-dl` link is downloaded through its redirect chain (`=s2048-rj?alr=yes` -> usercontent -> `rd-gg-dl` JPEG), which the HAR capture showed. On Windows this runs inside the signed-in browser tab; it falls back to cookies, which is also the Android path.
- Reference images are uploaded to Gemini. `[n]` in the prompt becomes "attached image n".
- The result is centre-cropped to the chosen aspect ratio, saved on the device and served from `http://127.0.0.1:47823`, so preview, download, share, mockups and compare work unchanged. The 1620x2880 JPG export preset is done locally.
- Requests run one at a time (the Gemini web conversation is stateful). Gemini's own image limits apply.

## v1.13.0 - Smart generation (fast, no image_to_image)

- Image to Prompt needs **one** Gemini call: element list, keep/change plan and prompt come back in one answer. The source palette and exposure are read locally and saved with the prompt.
- A Smart prompt is generated with ONE text_to_image request: palette from 40 %, exposure from 55 %. No reference upload, no measuring, no AI judge, no regeneration.
- The Batch switch is now called "Smart generation".

## v1.12.3 - One image per anchor (no silent regenerate)

- Extra tries default to 0, so the app no longer regenerates when the similarity target is missed.

## v1.12.2 - Generation never hangs on Gemini

- If a Gemini request inside the browser tab times out or fails, the client falls back to direct cookies for the rest of the session.

## v1.12.1 - No more "logged out after 5 minutes"

- Cause: the app renewed (RotateCookies) the same Google session that was
  also open in the browser. Google saw one login renewed by two clients
  and ended it in the browser.
- App-side cookie renewal is now OFF by default (Settings > Gemini web
  session > "Renew cookies from the app", only for a dedicated account).
  The browser renews its own login; when the copied cookies expire the
  app reads fresh ones from the signed-in browser (Windows profile /
  Android built-in browser).
- Windows: while the app's Chrome/Edge window is open, Gemini requests
  run INSIDE that window (background gemini.google.com tab, page fetch
  via CDP) - same as using gemini.google.com by hand; no cookies are
  copied for them.

## v1.12.0 - Per-picture element plan

- Image to Prompt first asks Gemini for an element inventory of THIS
  picture (10-24 rows: subjects, props, background layers, textures,
  text, effects + global composition, camera, lighting, colour, time,
  style, mood), each with impact and identity weights 1-10.
- The app picks which elements change so the kept share of visual
  weight equals the target (least defining first; style and main subject
  last; camera/time/mood early). The prompt gets the exact KEEP / CHANGE
  element lists, and the Cloudinary image_to_image instruction ([1] +
  prompt) uses the same lists, re-planned for corrected tries.
- The prompt sheet shows the plan (kept / changed chips). Falls back to
  the generic 10-aspect plan when the inventory cannot be read.

## v1.11.6 - AI judge + recalibrated target plan

- Pixel analysis under-reads "same scene, slightly moved" (54 % pixels vs
  90 % to a human). When a Gemini session exists the target loop now uses
  the AI art-director score to decide hit / retry; pixels are the
  fallback. Tolerance tightened to +-10 %.
- Target plan recalibrated: keeping camera, framing and background
  already reads ~90 %, so 65 % now changes small props, time/weather,
  pose, background details and camera/framing (90 -> 1 change,
  80 -> 3, 65 -> 5, 50 -> 7, 30 -> 9). Applies to Image to Prompt and to
  the image_to_image instruction.

## v1.11.5 - Source picture + generated prompt -> image_to_image

- With "Match similarity target" on, every prompt that came from Image to
  Prompt is generated via Cloudinary image_to_image: the source picture
  the prompt was made from is sent as reference [1] together with the
  full generated prompt and the similarity % (any target, 20-90).
- The measure-and-retry loop stays image_to_image and only corrects the
  % asked for. Text-only is used only if the source picture cannot be
  uploaded.

## v1.11.4 - Reference [1] + colour lock for accurate targets

- Guided attempts address the reference as `[1]` (Cloudinary
  image_to_image syntax). Targets >= 70 % send an edit-only instruction
  (no full re-description that made the model re-imagine colours and
  framing); the reference palette (hex) and exposure/contrast are written
  into the prompt whenever colour / lighting are "kept" by the target.
- Colour & tone lock: Lab (Reinhard) transfer of the reference look onto
  the result, strength from the target (90 % -> 0.9, 60 % -> 0.45, <= 30 %
  off). The matched copy is uploaded and becomes the result, so display,
  export and the other images of the set use it.
- Home (text mode) uses the same target engine when the prompt came from
  Image to Prompt and "Match similarity target" is on.

## v1.11.3 - Similarity target is actually matched

- Why targets were missed: prompts from Image to Prompt were generated
  text-only, so the model invented a new layout and pixel similarity
  landed around 8-25 % whatever the target.
- New "Match similarity target" (Batch options, on by default): for set
  anchors whose prompt came from Image to Prompt, targets >= 38 % start
  from the reference picture (signed upload -> image_to_image with a
  keep/change instruction). Each result is measured; if it is outside
  +-12 % the strength is corrected and it is regenerated (0-3 extra tries,
  default 2). The closest image is kept and its score shows on the card.
- Colour palette metric: saturation-weighted soft hue bins + value bins
  (the same purple/orange palette no longer reads 0 %).

## v1.11.2 - Batch prompts persist + originality on result cards

- Batch Sets prompt rows are saved as a draft (memory + prefs). Leaving the
  Batch screen (tab switch, Settings, back) or restarting the app no longer
  clears prompts that came from Image to Prompt.
- Image to Prompt: already-sent prompts can be sent again ("Add again" on
  the card / sheet, "Add all again" on the queue card).
- Every finished Batch result card has an originality badge: "% new"
  coloured by verdict when the prompt came from Image to Prompt (computed
  in the background, one image at a time), otherwise a compare icon.
  Tap opens the full Originality check.

## v1.11.1 - Faster result pickup + timing breakdown

- Task polling is adaptive: first check after 1.2 s, then every 1.5 s for the first 30 s, 2.5 s up to 90 s, then 4 s. The old fixed 3 s step added about 1.5-3 s of dead time to every image (and to every stage of a set).
- Live timer while generating (home and batch): "queued on Cloudinary 6s" / "rendering 14s".
- Each result shows where the time went: total / queue (waiting on Cloudinary) / render (the model working). A long queue time is Cloudinary-side load; a long render time comes from the model and resolution (2K/4K and premium models are slower).
