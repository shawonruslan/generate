# Zedge Automation Suite – Setup Guide

This bundle contains **no credentials**. Every place you must fill in is marked with a
`<-- CONFIG` comment and a `YOUR_...` placeholder. Run `python3 check_config.py` at any time to
list what is still unfilled.

```
index.html          Web control panel (open in a browser / host on GitHub Pages, Netlify, etc.)
app/                Android app (Android Studio project, Kotlin + Jetpack Compose)
zedge1..4.yml       GitHub Actions upload bots – one per Zedge account
generator.yml       GitHub Actions ringtone / metadata generator (Gemini + Stable Audio)
r2-worker/worker.js Cloudflare Worker that stores media files in your R2 bucket
check_config.py     Verifies all placeholders are filled and URLs match across files
```

---

## 1. Firebase – one Realtime Database per Zedge account

For **each** Zedge account (up to 4):

1. <https://console.firebase.google.com> → *Add project* (e.g. `my-zedge-1`).
2. *Build → Realtime Database → Create database* (any region) → start in **test mode**.
3. *Rules* tab – the bots use the REST API without auth, so keep the DB writable:
   ```json
   { "rules": { ".read": true, ".write": true } }
   ```
   (Restrict this later, e.g. by IP or a token, if you like – but every component must then be updated.)
4. Copy the **database URL** (`https://<project>-default-rtdb.<region>.firebasedatabase.app` or
   `https://<project>-default-rtdb.firebaseio.com`).
5. *Project settings → Your apps → Add app → Web (</>)* → copy the `firebaseConfig` object.

Paste the values here – **the databaseURL must be identical in all four places**:

| Where | What |
|---|---|
| `index.html` → `const configs = { zedge1: {...}, ... }` | full `firebaseConfig` (apiKey, authDomain, databaseURL, projectId, storageBucket, messagingSenderId, appId) |
| `zedgeN.yml` → `const firebaseDatabaseURL = "..."` | databaseURL of account N |
| `generator.yml` → `FIREBASE_DB_MAP` (appears twice) | databaseURL of all accounts |
| `app/.../core/Core.kt` → `Accounts.all` | databaseURL of all accounts |

Using fewer than 3 accounts? Keep the extra entries pointing at any valid DB (they are simply unused),
or remove the extra `Account(...)` lines in `Core.kt` and the matching `zedgeN` entries in `index.html`.

## 2. Cloudflare R2 – media storage

1. Cloudflare dashboard → **R2** → *Create bucket* (e.g. `zedge-media`).
2. **Workers & Pages → Create → Worker** → replace the code with `r2-worker/worker.js` → *Deploy*.
3. Worker → *Settings → Bindings → Add → R2 bucket* – variable name **`MEDIA_BUCKET`**, pick your bucket.
4. Copy the worker URL (`https://<name>.<subdomain>.workers.dev`) into:
   - `index.html` → `R2_WORKER_URL`
   - `generator.yml` → `R2_WORKER_URL`
   - `zedge1..4.yml` → `r2WorkerUrl`
   - `app/.../core/Core.kt` → `R2_WORKER_URL`

Files are stored under `<account>/<timestamp>_<name>` so each account has its own folder.

## 3. GitHub repository + secrets (bots & generator)

1. Create a **private** GitHub repository and put `zedge1.yml … zedge4.yml` and `generator.yml`
   into `.github/workflows/`.
2. *Settings → Secrets and variables → Actions → New repository secret*:

| Secret | Used by | Required? |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | zedge1-4.yml – success/failure reports with screenshots | optional (skipped if missing) |
| `TELEGRAM_CHAT_ID` | zedge1-4.yml – your Telegram user/group id | optional |
| `GEMINI_SESSION` | generator.yml – Gemini web storageState JSON (export from the panel's GitHub tab) | required for generator |
| `STABLE_AUDIO_TOKEN` | generator.yml – Stable Audio bearer token (auto-refreshed by the workflow) | required for ringtone generation |

Telegram: create a bot with [@BotFather](https://t.me/BotFather) → token; send the bot a message and
open `https://api.telegram.org/bot<TOKEN>/getUpdates` to read your `chat.id`.

3. Zedge login, proxy, headless mode, profile count and runner OS are **workflow inputs** – enter them
   when you trigger the workflow (*Actions → zedgeN → Run workflow*) or from the panel/app GitHub tab.
   Set `total_profiles` to the number of profiles that account really has on upload.zedge.net.

## 4. Upload schedule (cron)

The workflow files only have `workflow_dispatch`. Trigger **every** account's workflow every 30 minutes,
all day, with any scheduler (e.g. cron-job.org) set to the **Asia/Dhaka** timezone:

| Account | Cron (same for all) |
|---|---|
| zedge1 - zedge4 | `0,30 * * * *` |

The workflow's `gate` job decides when to really upload: it reads each account's 3 upload windows
(3 hours each) from Firebase `dashboardSettings/schedule`, picks one random half-hour slot per window
per day (deterministic hash, so panel/app can predict it) and skips every other ping in a few seconds.
If a ping was missed (scheduler hiccup), the next ping inside the same window **catches up**.

- **Change the schedule** from the panel/app *Schedule* tab -> "Upload Schedule & Cron Health" -> pick
  3 start hours -> *Save schedule*. No yml/cron edit needed; the bot uses it on the next ping.
- Defaults (used until you save one): zedge1 `10,15,20`, zedge2 `11,16,21`, zedge3 `5,11,17`, zedge4 `4,9,14`
  (`DEFAULT_WINDOWS` in each `zedgeN.yml`, `DEFAULT_UPLOAD_WINDOWS` in `index.html`, `RunSchedule.DEFAULT_WINDOWS` in the app).
- **Cron health**: the same card shows the last ping time, the gate's last decision and today's runs
  per account. Red "ping missing" = your scheduler is not calling the workflow.
- Cost: the skipped gate pings are ~10 s each (48/day/account). Free on public repos; on a private repo
  you can limit the cron to your awake hours, e.g. `0,30 4-23 * * *`, as long as it covers all windows.

## 5. Control panel (`index.html`)

A single static file – open it locally or host it (GitHub Pages / Netlify / Cloudflare Pages).
In the **GitHub** tab enter your repo owner, name and a Personal Access Token (scope: `repo` +
`workflow`) to trigger workflows from the panel; these are stored in your own Firebase DB under
`dashboardSettings/ghPanel`.

Optional: `GOOGLE_CALENDAR_API_KEY` (Google Cloud → Calendar API key) enables India/Bangladesh
public-holiday feeds on the calendar. Leave empty to skip – other countries use a free feed.

## 6. Android app

1. Open `app/` in Android Studio (Ladybug or newer, JDK 17).
2. Fill `core/Core.kt` (DB URLs + R2 worker URL). Optional: `domain/SpecialDays.kt` Google key.
3. *Build → Generate Signed APK* (or run on a device).

## 7. Final check

```bash
python3 check_config.py
```
Must print `OK - all config filled and consistent.` Then: open the panel → pick an account → upload a
test file → *Actions → zedgeN → Run workflow* with `force_run = true` to upload immediately.


## v23 additions

See **V23-CHANGES.md**: metadata guard (files without title/tags/category are skipped by the bot), missing-metadata alerts in panel + app, and exact per-slot upload times (`dashboardSettings/schedule.slots`). No new secrets or cron changes are needed.


## v24 - VPN (OpenVPN / WireGuard)

The GitHub tab now has a **VPN** card: upload an `.ovpn` (with optional username/password and CA/cert/key files) or a WireGuard `.conf` per Zedge account, **Test** it (the workflow runs in `vpn_test` mode and only checks the tunnel), then **Set active** so real runs go through the VPN. Also fill the **Repo link / path** and, if your workflow files are renamed, the per-account **workflow file** names in the Connection card. Details: `V24-VPN-CHANGES.md`.
