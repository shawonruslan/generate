# Team Drive — Flutter App (Android + Windows)

Native Team Drive client. **100% Flutter widgets — no WebView anywhere.**
Talks directly to the Cloudflare Worker API (same endpoints as the web app).

## Features (full parity with the web app)

- **Login** — admin or member, session saved on device
- **My Drive** — browse folders, new folder, upload (with progress; large files use
  multipart like the web app), download, rename, delete, search, versions, previews
- **Group feed** — caption + file posts, seen-by tracking, pin/unpin (admin), delete
- **Notes** — create / edit / delete
- **Tickets** — support tickets, replies, open/close
- **Diary** — private entries, stickers, drawings, image attachments
- **Database** — records CRUD
- **Shares** — public share links, revoke
- **Announcements** — admin broadcasts
- **Members** — add / edit / remove members, quotas, pools (admin)
- **Storage indicator** — usage ring in the sidebar
- **Theme** — flat dark-gray night mode / off-white glassy day mode

## Configure the API

The worker URL and credentials live in `lib/utils/config.dart`:

```dart
const workerBaseUrl = 'https://your-worker.yourname.workers.dev';
```

Log in with your admin username/password or a member account — the app stores the
session token on-device (SharedPreferences) and sends it as the `X-Session-Token`
header on every API call, exactly like the web app.

## Build locally

```bash
flutter pub get
flutter run -d windows     # or: flutter run (android device)
```

## Build APK + EXE in CI

Push to `main` (or run manually): the workflow in
`.github/workflows/build.yml` builds a release APK (ubuntu runner) and a release
Windows build (windows runner) and uploads both as artifacts. Download them from
the Actions run page.

## Project layout

```
lib/
  main.dart            app entry, session restore, theme mode
  api/                 worker client (dio) — every endpoint, upload/download progress
  models/              typed models for all API objects
  providers/           session + theme state
  screens/             one screen per sidebar tab + login
  widgets/             shared UI: sidebar, storage ring, file tiles, dialogs
  theme/               dark-gray night / off-white glassy day themes (flat, no gradients)
  utils/               config, formatting, file helpers
```
