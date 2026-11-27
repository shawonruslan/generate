# Team Drive Worker API Reference

- **Version:** `7.6` (health endpoint returns `{"ok": true, "service": "team-drive secure r2 gateway", "version": 7.6}`)
- **Source:** `~/workspace/user/files/worker.js` (1562 lines)
- **Base URL:** the Cloudflare Worker URL, e.g. `https://teamdriveofficial.workers.dev`
- **Auth model:** all `/api/*` routes require a session token; public routes are `/`, `/s/*`, `/dl/*`, `/av/*`, `/dimg/*` (the last four are signature-gated).

## Session / Token model

| Item | Detail |
|---|---|
| Login | `POST /api/login` with JSON `{ role: "admin" \| <anything>, username?, password }`. Role `admin` checks `env.ADMIN_PASSWORD`; otherwise member login by lowercase username against PBKDF2 hash in `__system/members.json`. |
| Token format | `base64url(payload).base64url(HMAC("session:"+payload))` — two dot-separated parts. Payload JSON: `{ u, r, v, exp }` where `v` is a session-version binding (admin password hash for admin, random `sv` per member). |
| How token is passed | `Authorization: Bearer <token>` header on every `/api/*` call. |
| Lifetime | 7 days (`SESSION_HOURS = 24 * 7`). Expired → 401. |
| Invalidation | Member sessions die when password is reset/changed or account disabled (server checks `sv` on every request). Admin sessions die when `ADMIN_PASSWORD` changes. |
| Rate limit | 10 wrong passwords / 15 min per IP (login) → 429. Failed logins sleep ~700ms. |
| Change password | Member only (`POST /api/password`); admin must change it in worker code (server rejects with 400). |
| Logout | No server endpoint — client just discards the token. |

## CORS

Applied to all responses; preflight `OPTIONS` returns 204.

| Header | Value |
|---|---|
| `Access-Control-Allow-Origin` | `*` (config `ALLOWED_ORIGINS` is empty) |
| `Access-Control-Allow-Methods` | `GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS` |
| `Access-Control-Allow-Headers` | `Authorization, Content-Type, X-File-Type, X-File-Name, X-Version-Note, Range` |
| `Access-Control-Expose-Headers` | `Content-Length, Content-Range, Content-Disposition, ETag` |
| `Access-Control-Max-Age` | `86400` |
| `Vary` | `Origin` |

## Error shape

All failures: HTTP status + JSON `{ "error": "<message>" }`. Notable statuses: 400, 401 (`Please sign in` / `Session expired...`), 403, 404, 409 (`Busy...`), 411 (missing Content-Length), 413 (quota / size limit), 423 (locked file), 429, 507 (all storage full).

## Auth legend

- **public** — no token
- **signed** — no token, but requires valid `exp` + HMAC `sig` query params in the URL
- **member** — any logged-in session (`Authorization: Bearer`)
- **admin** — session with `role == "admin"`; non-admin gets 403 `Admin only`

---

## Auth

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `POST /api/login` | public | JSON: `{ role: "admin"\|"member", username?, password }` | `{ token, username, role }` |
| `GET /api/me` | member | — | `{ username, role }` |
| `POST /api/password` | member (not admin) | JSON: `{ current, next }` (next ≥ 6 chars) | `{ ok: true }` |

---

## Drive (files & folders)

Member scoping: a member only ever sees their own home folder subtree — server filters `folders`/`files` in `/api/data` and rejects out-of-scope access everywhere (`scopeOf`). For members, folder id `root` in requests is remapped to their home folder.

### `GET /api/data` (member)
Master listing call (app state bootstrap). Returns:
```json
{
  "folders": { "<id>": { "name", "parent", "createdAt" } },
  "files": { "<id>": { "name", "folder", "size", "type", "uploadedAt", "uploadedBy",
                        "ver", "vc", "url?", "locked?", "note?", "shares?" } },
  "stats": { "used", "count", "limit", "totalUsed", "pools?", "quota?" },
  "linkExpires": 1730000000000, "maxVersions": 10,
  "announcements": [ { "id", "text", "type", "createdAt" } ],
  "avatars": { "<user>": "<signed /av/ url>" },
  "tickets": { "unread", "open" },
  "me": { "username", "role" }
}
```
- `file.url` — signed `/dl/` link, valid 12h (`LINK_HOURS = 12`), expires at `linkExpires`. **Absent** for members when the file is locked by admin.
- `file.locked` — `{ at, reason }`.
- `file.ver` — current version number; `file.vc` — count of old versions.
- `stats.quota` — member's own limit in **bytes** (`-1` = unlimited). `stats.limit`/`totalUsed` — all pools summed (bytes). `stats.pools` — pool count, admin only.
- Admin extras: `file.shares` (count of share links), own folder names = `"<username>"`.

### `POST /api/folder` (member)
Body `{ name, parent = "root" }` → `{ ok: true, id }`. Parent must exist and be in scope; auto-creates missing (single level here).

### `PATCH /api/item` (member)
Body `{ id, kind: "folder"|"file", name?, parent? }` → `{ ok: true }`. Rename and/or move. 404 if out of scope; 423 if file locked (members); 400 if moving a folder into itself, or moving a member's private home folder out of root.

### `DELETE /api/item` (member)
Body `{ folders: [<ids>], files: [<ids>] }` → `{ ok: true, deleted: <R2-object count> }`. Recursive for folders. 423 if any locked file in scope (members). Also prunes share links pointing at deleted files.

### `POST /api/upload` (member) — simple upload
- Query: `?folder=<id>&path=<optional/sub/path/name.ext>` (path parts auto-create folders).
- Headers: `Content-Type` of body = raw file bytes (body IS the file); `Content-Length` **required** (members get 411 without it); `X-File-Type` (mime); `X-Version-Note` (URL-encoded, ≤200 chars, stored per version).
- Semantics: quota check before **and** after (refund deletes R2 object on DB failure); same name+folder = **new version**, old current goes into `versions[]` (max 10, oldest R2 object deleted). Locked-file precheck runs before any bytes are stored.
- → `{ ok: true, storage: "<pool name>" }`.

### Multipart upload (member) — for large files (95MB+)
1. `POST /api/mpu/create` — Body `{ path, type, size, folder = "root" }` → `{ key, uploadId, storage }`. `uploadId` is opaque client string: `"<storageId>~<realUploadId>~<sig>"` — signed per user+key+storage, so others can't inject parts.
2. `PUT /api/mpu/part?key=<key>&part=<1..10000>&uploadId=<opaque>` — body = part bytes → `{ partNumber, etag }`.
3. `POST /api/mpu/complete` — Body `{ key, uploadId, parts: [{ partNumber, etag }], folder?, path?, type?, note? }` → `{ ok: true, storage }`.
4. `DELETE /api/mpu/abort?key=<key>&uploadId=<opaque>` → `{ ok: true }`.
- Same version/quota/lock semantics as simple upload.

### File versions (member; locked files → 423)
- `GET /api/versions?id=<fileId>` → `{ id, name, maxVersions, total, versions: [ { ver, size, type, uploadedAt, uploadedBy, note, restoredFrom, origAt, current, url } ] }` sorted newest-first; `total` = bytes incl. all versions.
- `POST /api/versions` — Body `{ id, ver }` → `{ ok: true, ver: <newVersionNumber> }`. Restores an old version as new current (old current becomes history; restored version gets a **new** number).
- `DELETE /api/versions?id=<fileId>&ver=<n>` → `{ ok: true }`. Deletes one old version from R2. (To delete the current version, delete the whole file.)

### `GET|HEAD /dl/{path}` (signed — public with valid signature)
- Query: `exp=<ms epoch, hour-rounded>`, `sig=<HMAC>`, optional `st=<storage id>`, `a=1` (admin links), `name=<download filename>`, `pv=1` (preview/inline).
- `path` must start with `files/`, no `..`.
- Expired → 403; bad sig → 403.
- Member links (`dl:`) re-check the file lock in DB **at download time** (old links die too) → 423 if locked. Admin links (`dla:`, `a=1`) bypass lock.
- Supports `Range` (206), ETag/conditional GET; `pv=1` → `Content-Disposition: inline` + 1h private cache, otherwise `attachment` + no-store. Download links expire after 12h.

### `PATCH /api/lock` (admin)
Body `{ id, locked: bool, reason? }` → `{ ok: true, locked: bool }`. Locked files: members can't download/preview/rename/delete/new-version (enforced server-side, 423).

---

## Group feed

Shared space for admin + all members. Everyone sees everything; admin can pin/unpin. Files live at `files/__group/<uid>/<name>` in R2 — **not** in `db.files`, so they never appear in Drive listings, but are fetched via signed `/dl/` links.

### `GET /api/group` (member)
**Side effect (seen-by):** every GET marks the caller on each post's `seen` map (`{ username: timestamp }`); writes only when a new viewer appears; capped at 60 viewers/post (oldest evicted).
Returns:
```json
{ "posts": [ { "id", "by", "role", "caption", "pinned", "pinnedAt", "ts",
               "seen": { "<user>": <ts> },
               "file?": { "key", "st", "name", "size", "type", "url" } } ],
  "avatars": { "<user>": "<signed url>" } }
```
Pinned posts first (by `pinnedAt` desc), then the rest in feed order.

### `POST /api/group/upload` (member) — 2-step file attach
- Headers: `Content-Length` required (411 without), `X-File-Name` (URL-encoded; `?name=` query is the CORS fallback), `X-File-Type`.
- Body = raw file bytes. Max **512 MB** per file (413 above).
- Member quota is enforced here too.
- → `{ key, st, name, size, type, storage }` — pass this object as `file` into `POST /api/group`.

### `POST /api/group` (member)
Body `{ caption?, file? }` (caption ≤ 500 chars; at least one required; `file` must be a valid `files/__group/...` key).
Auto-eviction: > 1000 posts → oldest **unpinned** posts deleted (with their R2 files).
→ `{ ok: true, post: <published post object> }`.

### `DELETE /api/group?id=<postId>` (member)
Members: own posts only. Admin: any post. Deletes the attached R2 file too. → `{ ok: true }`.

### `PATCH /api/group/pin` (admin)
Body `{ id, pinned }` → `{ ok: true }`.

---

## Notes (per-user private, Keep-style)

- `GET /api/notes` (member) → `{ notes: [ { id, title, body, items?, color, pinned, archived, labels, createdAt, updatedAt } ] }`.
- `PUT /api/notes` (member) — Body `{ id?, title (≤500), body (≤50000), items?: [{ t (≤2000), d: bool }] (≤500), color (one of 11), pinned, archived, labels: [≤10 × ≤40 chars] }`. Omit `id` to create. Max 2000 notes/user. → the saved note `{ id, ...fields, createdAt, updatedAt }`.
- `DELETE /api/notes?id=<id>` (member) → `{ ok: true }`.

---

## Support tickets (member ↔ admin)

Ticket: `{ id, user, subject, cat, pri, status: "open"|"closed", createdAt, updatedAt, closedBy, unread, msgs: [{ by, text, at }] }`.
Categories: `general, upload, download, storage, account, bug`; priorities: `low, normal, high`.
Limits: 20 open tickets/member, 200 messages/ticket, 1000 tickets total (oldest closed auto-deleted).

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/tickets` | member | — | own tickets (member) / all (admin), newest-first |
| `POST /api/tickets` | member only (admin → 400) | `{ subject (≤120), text (≤3000), cat?, pri? }` | `{ ok: true, id }` |
| `POST /api/tickets/reply` | member | `{ id, text (≤3000) }` — replying a **closed** ticket reopens it | `{ ok: true }` |
| `POST /api/tickets/read` | member | `{ id }` — marks own read side (`seenU`/`seenA`) | `{ ok: true }` |
| `PATCH /api/tickets` | member | `{ id, status: "open"\|"closed" }` | `{ ok: true }` |
| `DELETE /api/tickets?id=<id>` | admin | — | `{ ok: true }` |

`unread` counts messages from the other side newer than the reader's `seen` timestamp. The `tickets: { unread, open }` badge is embedded in `GET /api/data`.

---

## Database / record lists

List schema: `{ name, desc, cols: [{ k, name, match }], access: "all"|"own"|"admin", memberAdd, count, createdAt, updatedAt }`.
Access: `all` = members see all rows; `own` = members see only their rows (match-check tells them *whose* it matches without showing other rows); `admin` = hidden from members.
Caps: 50 lists, 12 cols, 5000 rows/list, 200 rows/member, 300 chars/cell. Values normalized (case/space/dash-insensitive) for matching.

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/records` | member | — | visible lists: `{ id, name, desc, cols, access, memberAdd, updatedAt, createdAt, count? }` |
| `GET /api/records/rows?id=<listId>` | member | — | `{ list, rows: [{ id, owner, cells, at, by, dup: [{ col, n, with: [owners≤10] }], canEdit }], mine }` |
| `POST /api/records/row` | member | `{ id, cells: {<colKey>: value}, owner? }` — members need `memberAdd` true; admin may set `owner` | `{ ok: true, id: <rowId> }` |
| `PATCH /api/records/row` | member | `{ id, rid, cells, owner? }` — only editable own/allowed rows | `{ ok: true }` |
| `DELETE /api/records/row?id=<listId>&rid=<r1,r2,...>` | member | — | `{ ok: true, deleted: <n> }` |
| `POST /api/records/check` | member | `{ id?, value }` — match-check; without `id` searches all visible lists; value ≥ 2 chars; max 100 hits (`more: true` if capped) | `{ value, matches: [{ list, listName, col, colName, rid, owner, own, at, cells?, cols? }], more? }` |
| `POST /api/records` | admin | `{ name, desc?, cols: [{k?, name, match?}], access?, memberAdd? }` | `{ ok: true, id }` |
| `PATCH /api/records` | admin | `{ id, name?, desc?, cols?, access?, memberAdd? }` | `{ ok: true, id }` |
| `DELETE /api/records?id=<id>` | admin | — (also deletes rows file) | `{ ok: true }` |
| `POST /api/records/import` | admin | `{ id, rows: [{ owner?, cells }], replace? }` — invalid rows skipped; `replace: true` wipes first | `{ ok: true, added, skipped }` |

---

## Diary (per-user private)

**Privacy: strictly per-user — the server never exposes another user's diary, not even to admin** (all reads/writes keyed by `me.u`).
Entry schema per date (`YYYY-MM-DD`): `{ text (≤6000), mood, html?, draw?, stk?, at }`.
- `mood`: one of `happy, calm, love, excited, tired, sad, angry` (or empty).
- `html`: mini-markup for colored/highlighted/underline/strike text (server strips control chars).
- `draw`: ≤300 sanitized vector shapes (`t`: p/b/e/r/a; `c`: 9 colors; coordinates clamped).
- `stk`: ≤20 sticky pictures `{ id, x, y, w, a, r, k }` referencing uploaded images.

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/diary?year=<YYYY>` | member | — (defaults to current year) | `{ year, entries: { "<date>": <entry> }, years: { "<year>": <entryCount> } }` — sticky pictures get signed `u` (image URL) injected server-side |
| `PUT /api/diary` | member | `{ date, text?, mood?, html?, draw?, stk? }` — saving an **empty** entry deletes it for that date | `{ ok: true, at, deleted: bool }` |
| `DELETE /api/diary?date=<YYYY-MM-DD>` | member | — | `{ ok: true }` |
| `PUT /api/diary/img` | member | Raw image bytes; max **1500 KB**; only JPG/PNG/WEBP (magic-byte sniffed, not by extension) | `{ ok: true, id, url }` — `id` is a 24-hex string; reference it in `stk` |
| `GET /dimg/<user>/<id>?exp=&sig=` | signed | — | the image; signed HMAC `dimg:<user>:<id>:<exp>`; 24h browser cache |

Removing a sticky picture from an entry (or deleting the entry) deletes the underlying R2 object.

---

## Announcements

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/announcements` | admin | — | all: `{ id, text, type, active, createdAt, exp, expired }`, newest-first (max 50) |
| `POST /api/announcements` | admin | `{ text (1–300 chars), type: info|success|warning|urgent, expiresHours? (≤1yr) }` | `{ ok: true, id }` |
| `PATCH /api/announcements` | admin | `{ id, active }` | `{ ok: true }` |
| `DELETE /api/announcements?id=<id>` | admin | — | `{ ok: true }` |

Active, unexpired announcements are embedded in every `GET /api/data` response (all users see them).

---

## Members (admin)

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/members` | admin | — | `[{ username, createdAt, lastLogin, disabled, folder, files, size, quotaGB, quota, pool }]` — `quotaGB` null = default; `quota` in bytes / `-1` = unlimited |
| `POST /api/members` | admin | `{ username (3–32, a-z0-9_.-), password (≥6), reset? }` — `reset: true` = change existing member's password (invalidates their sessions); max 200 members; creates private home folder on new member | `{ ok: true }` |
| `PATCH /api/members` | admin | `{ username, disabled }` — toggling invalidates sessions | `{ ok: true }` |
| `DELETE /api/members?username=<u>` | admin | — folder is **kept** (renamed `"<u> (removed)"`, becomes normal admin folder); notes, avatar, diary deleted | `{ ok: true }` |
| `PATCH /api/members/quota` | admin | `{ username, quotaGB?: number\|null, pool?: "<extraR2Id>"\|null\|"auto" }` — `quotaGB: -1` unlimited, `0` = upload disabled, `null` = reset to default; pool pins the member's files to a specific extra R2 | `{ ok: true }` |

Member quota enforced server-side on `/api/upload`, `/api/mpu/*`, `/api/group/upload` (403 when 0, 413 when over).

---

## Shares

Share links: 144-bit random ids (`/s/<id>`, id length 16–64 chars), optional PBKDF2 password, optional expiry, optional max downloads.

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /api/shares` | admin | — | `[{ id, url, fileId, fileName, size, hasPassword, expiresAt, maxDownloads, downloads, disabled, createdAt }]` newest-first (max 5000) |
| `POST /api/shares` | admin | `{ fileId, password? (4–200 chars), expiresHours? (≤10yr), maxDownloads? (≤1e6) }` | `{ id, url }` |
| `PATCH /api/shares` | admin | `{ id, disabled }` | `{ ok: true }` |
| `DELETE /api/shares?id=<id>` | admin | — | `{ ok: true }` |
| `GET /s/<16-64 chars>` | public | — | server-rendered HTML page (password form or download button); 404 page if invalid/expired/disabled |
| `POST /s/<id>` | public | `{ password? }` | `{ url, name, size }` — `url` is a signed `/dl/` link valid **10 minutes**. Each successful unlock increments the download counter (so `maxDownloads` is enforced); **wrong passwords are rate-limited server-side: 5/IP/15min → lock, 30/hr across all IPs → link locked 1h**. Admin-made links bypass file lock. |

---

## Profile pictures

- `PUT /api/avatar[?user=<u>]` (member; `user` param is admin-only — admin can set any member's avatar) — Raw image bytes; max **500 KB**; JPG/PNG/WEBP magic-byte sniffed → `{ ok: true, url }` (signed URL).
- `DELETE /api/avatar[?user=<u>]` (member) → `{ ok: true }`.
- `GET /av/<user>?v=<version>&exp=<ms>&sig=<HMAC>` (signed) → the image. HMAC is over `av:<user>:<v>:<exp>`. The version bumps on each upload so URLs are cache-busting; 24h browser cache.
- Avatar URLs for admin/self/admin-user are embedded in `/api/data` and `/api/group` responses (member can't get other members' URLs).

---

## Settings (admin)

- `GET /api/settings` → `{ defaultQuotaGB, membersOnExtra }`.
- `PATCH /api/settings` → body `{ defaultQuotaGB?, membersOnExtra? }`; returns the updated settings. `defaultQuotaGB` default 500/1024 GB (~500MB); `membersOnExtra: true` routes member uploads to extra R2 pools first (keeps main R2 for admin).

---

## Storage (admin)

`GET /api/storage` → `{ pools: [{ id ("main" for primary), name, kind: "binding"|"s3", bucket, used, limit, files, readOnly, ok, error }], missing: [<pool ids referenced by data but no longer configured>] }`.
Each pool is live-tested on call (`ok`/`error`). Sizes in bytes; limits default 9.5 GB per pool.

**Pool routing:** new uploads go to the first pool with free space. If `membersOnExtra` is on and extra R2s exist, member files never go to main R2; a member with a pinned `pool` prefers it. Old files are never moved.

---

## Misc

| Method+Path | Auth | Request | Response |
|---|---|---|---|
| `GET /` | public | — | `{ ok: true, service: "team-drive secure r2 gateway", version: 7.6 }` |

## Desktop/native-only endpoints

**None.** Every endpoint is shared with the web app — the worker has no native-client-specific routes, headers, or user-agent checks. Notes for Flutter planning:
- The existing Go/Fyne native v1.0.0 (per project memory) only implements **auth + drive + group feed**; the worker fully supports notes, tickets, diary, database, shares, announcements, and members too — all available to a Flutter client with no extra backend work.
- Multipart upload endpoints (`/api/mpu/*`) are the recommended path for large files from desktop.
- Signed `/dl/`, `/av/`, `/dimg/` URLs are plain GETs — trivially consumable by Flutter's HTTP/image widgets; just store the full signed URL (expires in 12h, refresh via `/api/data` / `/api/group` / `/api/diary`).
- No push/notification API exists; badge counts (tickets, seen-by) come from polling `/api/data` and `/api/group`.
