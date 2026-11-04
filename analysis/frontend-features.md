# Team Drive Frontend — Complete Feature Inventory

Source: `~/workspace/user/files/index-12.html` — single-file SPA, 392,919 bytes, 3,959 lines, ~193 JS functions.
Backend it talks to: Cloudflare Worker at `https://mainstorage.jonchristiangarcia.workers.dev` (constant `R2_WORKER_URL`, local alias `R2`).
Note: UI copy is heavily Romanized-Bangla (mixed EN/BN); features are documented with their functional names.

---

## 1. Top-level tabs / screens (sidebar navigation)

Sections: **Workspace**, **Team**, **Manage** (Manage section is admin-only — both the section label and its items have class `admin-only`).

| # | Label (member) | view id | Visibility |
|---|---|---|---|
| 1 | My Drive (admin) / My Files (member) | `drive` | All |
| 2 | Recent | `recent` | All |
| 3 | Notes | `notes` | All |
| 4 | Support (member) / Tickets (admin) | `tickets` | All (badge: unread reply count) |
| 5 | Diary | `diary` | All (private per user) |
| 6 | Database | `records` | All (visibility further gated per-list by `access`) |
| 7 | Group | `group` | All |
| 8 | Shared links | `shares` | **Admin only** |
| 9 | Announcements | `announcements` | **Admin only** |
| 10 | Members | `members` | **Admin only** |
| 11 | Storage | `storage` | **Admin only** |

Beyond nav: login screen (`#auth`), profile user-menu, announcement ticker bar (all users), sidebar storage ring widget, global upload progress panel, drag-drop overlay, file preview modal ("viewer"), generic modal/dialog system, context menus.

`enterApp()` gates everything: `.admin-only` hidden unless `S.me.role === 'admin'`; `.member-only` (New ticket button, change-password menu item, separator) hidden for admin. Member label for drive is "My Files", admin sees "My Drive".

---

## 2. Per-screen feature inventory

### 2a. Login / session (`#auth`)
- Role segmented control: **Member** (default) vs **Admin**. Admin hides username field (username is implicit `admin`); member requires username.
- Username lowercased; "Keep me signed in" checkbox (checked default).
- Login flow: `POST /api/login {role, username, password}` → `{token, username, role}`; session `{token, username, role}` saved to **localStorage** (`td_session`) if remember checked, else **sessionStorage**. Password field cleared after login.
- Boot: `readSession()` → if token present, `GET /api/me` to validate; if valid → `enterApp()`, else clear session and show login.
- 401 from any API (except login) → `logout(true)` + toast + throw.
- Theme toggle also on login screen (`#authTheme`).
- Logout: clears session (both storages), clears upload queue, resets diary/records state, shows login. If an upload is in progress, asks for confirmation before sign-out.
- Member "Change password" (profile menu, member-only): modal with current + new password (min 6) → `POST /api/password {current, next}` → forced logout with "sign in with new password".

### 2b. App shell (shared)
- Sidebar: brand block (logo chip + "Team Drive / Secure file manager"), **New** button (hidden when member has upload disabled, quota=0), nav items with icon chips, unread ticket badge on Support/Tickets, storage ring widget (SVG progress ring + % + used/limit + file count + pool count).
- Topbar: hamburger (mobile sidebar), **search** (global — files in drive views, notes in notes view), "Ctrl K" kbd hint, day/night toggle, refresh button, profile pill (avatar, name, role) with dropdown menu: Profile picture, Change password (member-only), Sign out.
- Announcement **ticker** (all users): scrolling marquee of live announcements at top, color-coded by highest-ranked type (success<info<warning<urgent), hover-to-pause, dismiss button persists dismissed ids in `localStorage.td_ann_x` (last 100); reappears when new announcement arrives.
- Auto-refresh: every 60s `loadAll()` when visible, not busy, no modal open.
- Deep-linking: folder id stored in URL hash (`#/<folderId>`); hash change navigates.
- Search: debounced 200ms; in drive/searches files+folders globally; in notes searches notes; switching search text while on members/shares/storage/announcements/tickets/group jumps back to drive.
- Sort control (Name / Newest first / Largest first, persisted `td_sort`), List/Grid view toggle (persisted `td_layout`).

### 2c. Drive (`drive`)
- Breadcrumb navigation (root + path segments, click to jump).
- List view (table rows: icon/thumbnail, name, size, version badge, share-count tag, lock tag, owner tag for member folders, uploaded-by avatar, relative + absolute dates) and Grid view (tiles with thumbnails).
- Row thumbnails: lazy-loaded; images ≤30MB (`THUMB_MAX`) show preview thumb, videos show video preview on hover; other files get type icon boxes.
- Type detection (`typeOf`): icon + color + label per extension (images, video, audio, pdf, code, archives, docs, etc.).
- **Context menu (right-click) on file**: Preview, Download, Rename, Copy download link, Share link… (admin), Move to…, File details, Version history (with version count), Upload new version, Lock file…/Unlock file (admin), Delete.
- **Locked file** (member view): shows lock notice with admin's reason, options: File details, "Ask admin to unlock" (opens ticket prefilled `subject: 'Unlock request: <name>'`, category download). No preview/download/copy.
- **Context menu on folder**: Open, Upload files here, Rename, Move to… (member folders excluded for move when owned), admin can set that member's profile picture, Delete (recursive; confirms with file count; member folder re-created empty after delete).
- **Background right-click menu** (drive/recent, empty area): New folder, File upload, Folder upload, Refresh, List/Grid view, Sort options, Go to parent folder.
- **New button / menu**: New folder, File upload, Folder upload.
- Uploads: single file picker (multiple), folder picker (`webkitdirectory`), drag & drop onto drive (with full-screen drop overlay), recursive folder traversal (`walk`) preserving relative paths.
- Upload queue panel: per-file rows with icon, relative path, progress bar, `% bytes of total · speed`, status icon; header shows count; minimize/collapse and close (blocked while busy); `beforeunload` guard while uploading.
- New folder modal (name sanitization: slashes→`-`, strip control chars, 200 char max).
- Rename modal (same sanitization).
- **Move to…** dialog: dropdown of all folders (excludes own descendants for folders), sorted by path.
- **File details** modal: type, size, location path, uploaded date (absolute + relative), uploaded-by (avatar), version info, note, lock status; buttons: Versions, Preview, Download (or "Locked" disabled).
- **Copy download link**: copies signed URL, toast says valid until link-expiry time.
- Hash/deep-link per folder; search results view shows matching files+folders with path hints.
- `loadAll()` = `GET /api/data` refreshes folders, files, stats, avatars, announcements, ticket badge, version cap; then re-renders current view.

### 2d. Recent (`recent`)
- Flat list of most recently uploaded files (server-ordered from `/api/data`), same row rendering/context menus as Drive; empty state "No files yet". Background right-click menu offers view/sort but no New folder/upload.

### 2e. Notes (`notes`) — Google Keep style
- Composer: collapsed "Take a note…" bar → click expands full editor; "New list" button starts checklist note; click-outside auto-saves.
- Notes are **private per user** ("Apnar notes private — onno keu dekhte pare na").
- Editor features: title, body textarea (auto-grow), checklist mode (checkbox items; Enter adds item, Backspace on empty removes item, per-item delete ×, toggle done w/ strikethrough), 11 background colors (separate light/dark palettes), pin/unpin, archive/unarchive, labels (comma-separated, max 10; label filter chips bar; "All" reset), delete (confirm), copy note text to clipboard.
- Card grid (masonry): pinned section on top, then others; checklist preview (undone first, max 10 shown, "+N more"); per-card quick actions: pin, background, archive, copy text, delete; edited date shown.
- Note open modal (max 600px): full editor; auto-delete if saved empty; saves only when changed.
- Archive view toggle (lightbulb / box-archive).
- Search integrates with topbar search (searches title, body, items, labels).
- Color is theme-aware (light palette vs dark palette).

### 2f. Tickets (`tickets`) — member sees "Support"
- Tabs: Open (n) / Closed (n) / All (n); sidebar badge = unread count (`9+` capped).
- Ticket list: avatar, subject, last-message preview ("You: …"/"Admin: …"), status pill, priority pill, category tag, relative time, unread dot.
- Thread view: system message (opened by/at), message bubbles (own vs other), timestamps; closed banner ("Closed by X · reply reopens").
- Reply box: auto-grow textarea, **Ctrl+Enter sends**, max 3000 chars; replying to closed ticket reopens it (tab switches to open).
- New ticket modal: subject (max 120), category (General/Upload/Download/Storage/Account/Bug), priority (Low/Normal/High), message (max 3000); submit → opens the new ticket.
- Admin: same UI titled "Support tickets"; can Mark as solved / Reopen, Delete ticket (confirm). Unread badge tracking via `S.tk.unread`.
- Opening a thread with unread → `POST /api/tickets/read` marks read, badge decremented.
- Member deep-link: locked-file context menu prefills unlock-request ticket.

### 2g. Diary (`diary`) — private per-user, 3D book UX
- Opens as closed book with animated cover; click cover → opening animation (single-page or two-page spread depending on width); page-curl flip animations forward/back (900ms, Web Animations), sound effects (page flip / cover, WebAudio synthesized, toggleable, persisted `td_dysound`).
- Click page → edit mode (contenteditable); toolbar appears: pen colors (5 + default ink), highlight markers (5), font sizes (sm/md/lg/xl), underline, strikethrough, clear format, drawing tools: free pen, marker brush, circle, rectangle, arrow, eraser (drag to delete strokes), undo last stroke, insert picture.
- Rich-text stored as safe mini-markup (`<c k>`, `<m k>`, `<u>`, `<s>`, `<z k>`); never raw innerHTML — parsed/serialized safely.
- Read mode renders "handwriting" style: per-word random tilt/baseline/letter-spacing seeded by date (deterministic per date), Bangla-aware (no letter-spacing for Bengali).
- **Mood stamp**: 7 moods (Happy, Calm, Love, Excited, Tired, Sad, Angry) shown as stamp on page header.
- Pictures: pick/drag-drop images onto page → shrunk to ≤1400px (WebP/JPEG), `PUT /api/diary/img` → placed as "sticky picture" with tape style, draggable, rotatable, resizable, max 20 per page, delete.
- Drawings stored as vector strokes (SVG layer), synced with save.
- Save: debounced auto-save → `PUT /api/diary {date, text, html, mood, draw, stk}`; header shows "Saving…/Saved HH:MM"; empty entry → server deletes (`r.deleted`).
- Navigation: Today button, date picker (`dyGo`), entries list modal (grouped by month, preview text, mood, picture/drawing indicators; click jumps to date), arrow keys / PageUp/PageDown flip, swipe on touch, corner click zones.
- Year lazy-loading: `GET /api/diary?year=YYYY` cached per year.
- **3D view**: rotate/zoom the book with drag + scroll/pinch, reset button, HUD hint; screenshot of current 3D pose via custom canvas perspective render.
- **PNG export** (`dyShot`): via `html-to-image` lib (lazy-loaded CDN) with font-embedding + SVG-noise-texture→PNG conversion; options: whole book / cover / open spread / left page / right page / current page / 3D view; pixelRatio 2–3; downloaded as `diary-<date>[-3d].png`.
- **Table background** customization (`dyBgModal`): 8 styles (wood, linen, gingham check, plaid, felt, velvet, solid color, custom image), color picker, optional cloth texture overlay, custom image (resized ≤1920px JPEG, stored in localStorage `td_dybgimg` — browser-local only), live preview grid, reset.
- Pen animation: floating pen nib follows typing (3 styles: pencil/hand/fountain, off option; persisted `td_dypen`).
- Day/Night theme toggle inside diary; diary has own theme button.
- Responsive: single page vs spread auto-switch on resize.
- Private badge in bar ("Private").

### 2h. Database (`records`)
- **Match check** card: input token/number/ID (min 2 chars) + optional list selector → `POST /api/records/check`; normalization ignores case/space/`-_.​/`; results show match count, owner names, per-hit list name/column/row cells (private details hidden for non-owners), click a hit jumps to that list.
- List tabs (chips with row counts) + list header: name, description, access tag, "member can add" tag, row count, updated time.
- Access levels (admin-set per list): `all` (members see all rows read-only), `own` (members see only own rows; match check reveals whose data matched), `admin` (members don't see list at all, excluded from match check).
- Row table: Member column (owner chip w/ avatar, admin/all only), data columns, Match column (Unique ✓ / N matches ⚠ with tooltip listing matched columns + other owners), Added (relative time + "by X"), edit/delete (permission-gated via `r.canEdit`).
- Filters: in-list search (normalized), "Match / duplicate" toggle with duplicate count badge; table capped at first 1000 rows with notice.
- Add/Edit row modal: per-column inputs (max 300 chars), admin can assign owner (member dropdown); warns if new value matches another row.
- Admin: New list, Edit list (name, desc, up to 12 columns each with name + "Match" toggle, access level picker, "members can add/edit own rows" checkbox max 200 rows/member), Delete list (confirm, shows row count), Import CSV (≤3MB, header-matched columns, optional member/owner column, optional "replace all" mode, reports added/skipped), Export CSV (BOM + member, columns, match count, added ISO date).
- `rcNew` button admin-only; member "Add row" only when `memberAdd` enabled.

### 2i. Group (`group`) — shared feed
- Composer: avatar, caption textarea (max 500, file optional), Attach button (file picker chip with name/size + remove), Post button; file ≤512MB; upload via `POST /api/group/upload` (binary, `X-File-Name`, `X-File-Type` headers) → `POST /api/group {caption, file:{key,st,name,size,type}}`.
- Feed: pinned section first (thumbtack header), then "Recent"; stagger-in animation.
- Post card: author avatar + name (admin shown as "Admin" + ADMIN badge), relative timestamp, caption, file attachment (icon, name, type label, size; click = preview; preview + download buttons), **seen-by** row: avatar stack (up to 5) + "Seen by a, b, c +N more" (author excluded, "you" for self; tooltip full list; "No views yet" fallback).
- Pin/unpin (admin), Delete (admin or own post; confirm modal with caption preview).
- Refresh button; empty state CTA; worker-version error hint if 404 (needs Worker v7.2+).
- Viewing marks seen implicitly via server (GET marks viewer).

### 2j. Shared links (`shares`) — admin only
- Table: file (icon+name+created date; status line if deleted/disabled/expired/limit-reached), Protection (Password / Public pill), Downloads (n / max), Expires (datetime / Never), actions: Copy link, Enable/Disable toggle, Delete link (confirm; file untouched).
- **Create share** (from Drive context menu → Share link…): password field (optional, min 4) with show/hide + strong-password generator (12 chars, unambiguous alphabet), expiry select (Never/1h/1d/7d/30d; default 7d), max downloads (optional, blank=unlimited); on create shows read-only URL box + Copy button + protection explainer; auto-copies; reloads data (file shows share-count tag).
- Share URL format: server-issued `r.url` (opaque signed link, login-free).

### 2k. Announcements (`announcements`) — admin only
- Composer: message textarea (max 300, live char counter), type picker (Info / Good news / Notice / Urgent with distinct colors), expiry select (until off / 6h / 1d / 3d / 1w / 30d; default 1d), **live ticker preview**, Publish button → toast + reloads (ticker updates for everyone via `/api/data`).
- List: all announcements with type icon, text, status pill (Live / Paused / Expired), created + expiry times; actions: Pause/Resume, Delete. Header count "N live · M total".

### 2l. Members (`members`) — admin only
- Stats bar: default storage limit per member + Change button.
- Add member form: username (pattern `a-z 0-9 . _ -`, lowercased) + password (min 6) → creates member + private folder.
- Table: member (avatar w/ hover camera button → set profile picture for that member, file count, last login/never), Storage (used/limit bar, Unlimited/Upload-off states, "(default)" tag), Added date, Status (Active/Disabled pill); actions: **Folder** (open member's private folder in Drive), **Limit** (per-member quota dialog), **Reset** (password reset modal), Enable/Disable toggle, Remove (confirm; notes deleted, folder kept as "<user> (removed)").
- Quota dialog (`limitPicker`): Default (follows global), Custom (MB/GB numeric + unit), Unlimited, Upload off; same dialog used for global default.
- Default limit dialog via stats bar.

### 2m. Storage (`storage`) — admin only
- Pool summary cards: Total capacity, Used (file count), Free, next-upload target pool; overall progress bar (red >90%, amber >75%); warnings: disconnected pools, "missing" pools (removed from config but still hold files).
- Per-pool cards: name, kind (worker's own bucket vs extra R2 with id + bucket), status pill (Connected / Error + message), usage bar, used/limit, file count, read-only flag, access tag (Admin only vs Members + admin).
- **Member storage** card: toggle "Main R2 shudhu admin er jonno" (switches member uploads to extra pools only; disabled when no extra pools) → `PATCH /api/settings {membersOnExtra}`; summary: default limit/member, allocated total vs extra capacity, member usage; over-allocation warning.
- Per-member table: avatar+name+file count, used/limit bar, **pool selector** (Auto / specific extra R2 per member) → `PATCH /api/members/quota {username, pool}`, Set limit button.
- "Check again" refresh button; "add new R2" how-to card (R2 → Create bucket → API token → add to worker's `EXTRA_STORAGE` → Deploy).
- Sidebar widget + member quota enforcement driven by `/api/storage` + `/api/settings`.

### 2n. Profile / avatar
- Profile picture modal: choose photo (JPG/PNG/WEBP) → client-side square crop to 256×256 (canvas, tries WebP q.86 / JPEG q.86 / q.70, must be <480KB) → preview → Save `PUT /api/avatar[?user=]` (binary, Content-Type = blob type); Remove button (if picture exists) → `DELETE /api/avatar[?user=]`; admin can set any member's picture from Members table or folder context menu.
- Avatars shown across app (drive rows, group posts, seen-by, tickets, notes owner chips, member table); colored-initial fallback (8 colors, deterministic by username hash) with lazy img + error fallback.

### 2o. File preview ("viewer") modal
- Opens for any file with `url` (locked files → unlock prompt instead).
- Header: icon, name, type label, size, version, position (i of n), Details button, Copy download link, Download (primary), Close (Esc).
- Gallery mode: prev/next arrows + ArrowLeft/ArrowRight keys, click backdrop closes, Esc closes.
- Renderers by kind:
  - **Image**: zoom on click (toggle class), error fallback message.
  - **Video**: autoplay, controls, `nodownload`, cleanup pauses on close.
  - **Audio**: card with icon, name, size, player.
  - **Code/text**: fetches with `Range: bytes=0-2097151` if >2MB (truncation banner), binary detection (NUL byte) → "binary" fallback, syntax highlighting via lazy-loaded highlight.js (CDN, github-dark theme), line numbers, language label, Copy button.
  - **PDF**: lazy-loaded pdf.js (CDN) with worker; page-by-page canvas render (IntersectionObserver, 800px prefetch), zoom in/out (30%–400%), fit-to-width, page counter on scroll, DPR-aware (max 2), progress % while loading.
  - **Other**: "no preview" card.
- Preview URLs use `pvUrl = url + '&pv=1'` (tells worker to serve preview-friendly headers).
- Library loads are lazy via CDN (`cdnjs.cloudflare.com`): highlight.js 11.9.0, pdf.js 3.11.174, html-to-image 1.11.11 (diary), Font Awesome 6.5.2 webfonts.

---

## 3. Worker API calls (frontend → worker), exhaustive

Base: `R2 = https://mainstorage.jonchristiangarcia.workers.dev`. All via `api(method, path, json)` → `fetch(R2+path, {headers: {Authorization: 'Bearer <token>', 'Content-Type': 'application/json'}, body, cache:'no-store'})`, except binary uploads noted.

| # | Method | Endpoint | Payload / notes |
|---|---|---|---|
| 1 | POST | `/api/login` | `{role, username, password}` → `{token, username, role}` |
| 2 | GET | `/api/me` | session validation on boot |
| 3 | GET | `/api/data` | master state → `{folders, files, stats, linkExpires, avatars, announcements, maxVersions, tickets}` |
| 4 | POST | `/api/password` | `{current, next}` (member change password) |
| 5 | POST | `/api/folder` | `{name, parent}` |
| 6 | PATCH | `/api/item` | rename `{id, kind, name}` / move `{id, kind, parent}` |
| 7 | DELETE | `/api/item` | `{folders:[ids]}` or `{files:[ids]}` |
| 8 | PATCH | `/api/lock` | `{id, locked, reason?}` |
| 9 | POST | `/api/upload?folder=&path=` | **binary** XHR; headers `X-File-Type`, optional `X-Version-Note`; ≤95MB only; progress via `xhr.upload.onprogress` |
| 10 | POST | `/api/mpu/create` | `{path, type, size, folder}` → `{key, uploadId}` |
| 11 | PUT | `/api/mpu/part?key=&uploadId=&part=` | **binary** chunk via XHR (progress); retried |
| 12 | POST | `/api/mpu/complete` | `{key, uploadId, parts, folder, path, type, note?}` |
| 13 | DELETE | `/api/mpu/abort?key=&uploadId=` | fire-and-forget on failure |
| 14 | GET | `/api/versions?id=` | → `{versions[], maxVersions}` |
| 15 | POST | `/api/versions` | `{id, ver}` restore → `{ver}` |
| 16 | DELETE | `/api/versions?id=&ver=` | delete old version |
| 17 | GET | `/api/shares` | list |
| 18 | POST | `/api/shares` | `{fileId, password|null, expiresHours, maxDownloads}` → `{url}` |
| 19 | PATCH | `/api/shares` | `{id, disabled}` |
| 20 | DELETE | `/api/shares?id=` | |
| 21 | GET | `/api/notes` | → `{notes[]}` |
| 22 | PUT | `/api/notes` | full note `{id?, title, body, items[]|null, color, pinned, archived, labels[]}` |
| 23 | DELETE | `/api/notes?id=` | |
| 24 | GET | `/api/storage` | → `{pools[], missing[]?}` |
| 25 | GET | `/api/members` | list (used in 3 places) |
| 26 | POST | `/api/members` | create `{username, password}` / reset `{username, password, reset:true}` |
| 27 | PATCH | `/api/members` | `{username, disabled}` |
| 28 | DELETE | `/api/members?username=` | |
| 29 | GET | `/api/settings` | → `{defaultQuotaGB, membersOnExtra, ...}` |
| 30 | PATCH | `/api/settings` | `{defaultQuotaGB}` or `{membersOnExtra}` |
| 31 | PATCH | `/api/members/quota` | `{username, quotaGB}` or `{username, pool}` |
| 32 | PUT | `/api/avatar[?user=]` | **binary** image blob, `Content-Type: blob.type` |
| 33 | DELETE | `/api/avatar[?user=]` | |
| 34 | GET | `/api/announcements` | list |
| 35 | POST | `/api/announcements` | `{text, type, expiresHours}` |
| 36 | PATCH | `/api/announcements` | `{id, active}` |
| 37 | DELETE | `/api/announcements?id=` | |
| 38 | GET | `/api/group` | → `{posts[], avatars{}}` (marks viewer seen) |
| 39 | POST | `/api/group/upload` | **binary** via fetch; headers `X-File-Name`, `X-File-Type`, `Content-Type: application/octet-stream`; ≤512MB |
| 40 | POST | `/api/group` | `{caption, file:{key,st,name,size,type}|null}` |
| 41 | PATCH | `/api/group/pin` | `{id, pinned}` |
| 42 | DELETE | `/api/group?id=` | |
| 43 | GET | `/api/tickets` | list + unread |
| 44 | POST | `/api/tickets` | `{subject, text, cat, pri}` → `{id}` |
| 45 | POST | `/api/tickets/reply` | `{id, text}` |
| 46 | POST | `/api/tickets/read` | `{id}` |
| 47 | PATCH | `/api/tickets` | `{id, status}` |
| 48 | DELETE | `/api/tickets?id=` | |
| 49 | GET | `/api/records` | lists |
| 50 | GET | `/api/records/rows?id=` | list + rows |
| 51 | POST | `/api/records` | `{name, desc, access, memberAdd, cols[]}` |
| 52 | PATCH | `/api/records` | `{id, ...same}` |
| 53 | DELETE | `/api/records?id=` | |
| 54 | POST | `/api/records/row` | `{id, cells, owner?}` |
| 55 | PATCH | `/api/records/row` | `{id, rid, cells, owner?}` |
| 56 | DELETE | `/api/records/row?id=&rid=` | |
| 57 | POST | `/api/records/import` | `{id, rows:[{owner,cells}], replace}` |
| 58 | POST | `/api/records/check` | `{value, id?}` → `{value, matches[], more}` |
| 59 | GET | `/api/diary?year=` | → `{entries{}, years{}}` |
| 60 | PUT | `/api/diary` | `{date, text, html, mood, draw[], stk[]}`; empty → server deletes (`r.deleted`) |
| 61 | PUT | `/api/diary/img` | **binary** image blob → `{id, url}` |

That's **61 distinct API operations** across 24 base paths. Binary-body calls bypass `api()` and use raw `fetch`/XHR with `Authorization: Bearer` header (upload, mpu part, avatar, group upload, diary img).

---

## 4. Theme / design tokens

Flat design — user explicitly hates neon/gradients; all surfaces solid. Font: Inter/system stack. Icons: Font Awesome 6.5.2 (CDN). Radius var `--r` (cards/tiles), soft shadows `var(--shadow)`, borders `1px solid var(--line)`.

**Light (day) mode** (`:root`, frosted-glass panels):
- `--bg:#eceae2` (warm off-white page)
- `--panel:rgba(255,255,255,.72)`, `--side:rgba(247,246,242,.8)`, `--side2:rgba(255,255,255,.55)` (frosted sidebar)
- `--sideText:#5d6169`, `--text:#22242a`, `--muted:#868a93`
- `--line:rgba(34,36,42,.1)`, `--soft:rgba(255,255,255,.55)`
- `--brand:#4a5fd0`, `--brand2:rgba(74,95,208,.13)` (tint), `--brandDark:#3d4fb8` (hover)
- `--danger:#c24040`, `--ok:#3d8b4f`, `--warn:#b97a1e`

**Dark (night) mode** (`[data-theme="dark"]`, flat dark gray — NOT pure black):
- `--bg:#161616`, `--panel:#1e1e1e`, `--side:#111111`, `--side2:#2a2a2a`
- `--sideText:#a6a6a6`, `--text:#e9e9e9`, `--muted:#909090`
- `--line:#2d2d2d`, `--soft:#232323`, `--hover:#2b2b2b`, `--thumb:#1b1b1b`
- `--brand:#5b7cfa`, `--brand2:#2b3242`, `--brandDark:#4a68e8`
- `--danger:#e5484d`, `--ok:#46a758`, `--warn:#e8a13c`
- meta theme-color: dark `#0b1120`, light `#4f46e5`

Shared: `.btn.primary` = solid brand bg, white text, hover → brandDark; active sidebar nav = brand2 pill + solid brand icon chip; avatar circle = brand2 bg + brand text (or photo); progress bars/meters solid brand (red >90%, amber >75%); no gradients anywhere in app CSS (logo SVG itself contains a gradient, cosmetic only).

Theme: toggled via `#themeBtn`, `#authTheme`, diary `#dyTheme`; persisted `localStorage.td_theme`; initial from stored value or `prefers-color-scheme`; follows OS changes only if no stored choice. Notes have independent light/dark color palettes (11 colors).

---

## 5. Session handling

- Token: opaque string from `POST /api/login`; sent as `Authorization: Bearer <token>` on every request (JSON API via `api()`, binary via raw fetch/XHR).
- Storage: `localStorage.td_session` ("Keep me signed in" checked, default) or `sessionStorage.td_session`. Shape: `{token, username, role}`. Cleared on logout and on 401.
- Roles: `admin` vs `member`; `isAdmin()` gates UI + (server-side) endpoints. Admin logs in with password only (no username field); member needs username (lowercased).
- Session restore on boot via `GET /api/me`; failure → clear + show login.
- Diary/records state explicitly reset on logout.

---

## 6. Keyboard shortcuts & special UX

- **Ctrl+K / Cmd+K**: focus + select topbar search (global). Esc in search blurs.
- **Esc**: close context menu, close preview viewer, close mobile sidebar.
- **Ctrl+Enter**: send ticket reply.
- Viewer: **←/→** prev/next file; **Esc** close; backdrop click closes.
- Diary (when book open, not editing, no modal): **→/PageDown** next pages, **←/PageUp** previous; swipe left/right on touch flips; page corner click zones flip.
- Context menu: ↑/↓ arrow-key navigation, Enter activates.
- Notes checklist editor: **Enter** inserts new item below; **Backspace** on empty item deletes it and focuses previous.
- Diary editor: **Enter** inserts line break (overrides default paragraph split).
- Diary toolbar tooltips document Ctrl+U (underline).
- Upload: `beforeunload` blocks accidental navigation mid-upload.
- Toasts: bottom notifications (`ok`/`err`), auto-dismiss.
- Confirm modals for all destructive actions (delete file/folder, delete share, delete note, delete ticket, remove member, delete list/row, delete version, delete post, delete announcement).
- `prompt()` fallback when clipboard API unavailable.
- Mobile: sidebar drawer with backdrop + swipe-left to close; context menus become bottom sheets ≤640px; `hide-sm`/`hide-xs` responsive hiding.

---

## 7. File upload mechanics (Drive)

- Threshold: `SINGLE_MAX = 95MB` → single `POST /api/upload?folder=<id>&path=<relpath>` (XHR, `X-File-Type` header, `X-Version-Note` for version uploads); `xhr.upload.onprogress` drives per-file bar + speed (`fmtSize(bytes)/s`).
- Larger files → **multipart**: `POST /api/mpu/create {path,type,size,folder}` → `{key, uploadId}`; file sliced into `PART_SIZE = 25MB` chunks; `PARALLEL = 3` concurrent PUT workers to `/api/mpu/part?key=&uploadId=&part=N`; per-part retry up to 4 attempts with backoff `1500ms × attempt`, progress aggregated across parts; then `POST /api/mpu/complete {key,uploadId,parts,folder,path,type,note?}`; on failure `DELETE /api/mpu/abort?key=&uploadId=` (best-effort).
- Version upload: "Upload new version" → modal (optional change note, warns if extension differs) → enqueued with `rel = original filename`, `target = file's folder`, `note`; server versions it (`as vN` in completion text).
- Targets: current folder (drive) or 'root'; `uploadInto(folderId)` targets a specific folder (from folder context menu).
- Quota gate: `canUpload()` = admin OR member quota ≠ 0; enqueue no-ops otherwise; New button hidden.
- After every 5 uploads and at queue end → `loadAll()` refresh.
- Folder upload preserves relative paths (`webkitRelativePath`); drag-drop uses `webkitGetAsEntry` recursive `walk()`.

## 8. Download / link mechanics

- `f.url` is a **server-signed download URL** (worker-issued, time-limited). `fileUrl(f) = f.url`.
- Download: `location.href = f.url` (drive), `<a href download>` (group, versions).
- Copy download link: copies `f.url` to clipboard; toast shows expiry: "Link copied — valid until <linkExpires>" (`S.linkExpires` from `/api/data`).
- Preview media uses `pvUrl = f.url + '&pv=1'` (inline/preview disposition).
- Version list: each version has its own `v.url` for download.
- **Share links**: server-issued opaque `r.url` from `POST /api/shares` — public, login-free; optional password (min 4), expiry hours, max downloads; statuses tracked: active/disabled/expired/limit-reached/file-deleted. Copy/enable-disable/delete from Shares table.
- Signed-link refresh: links expire; code comment at line ~3197 notes fetching a fresh signed link when expired (viewer refetches via `loadAll` data).
- Resume support advertised on login page ("Fast downloads with resume support" — Range-capable R2 URLs).

---

## 9. Miscellaneous / cross-cutting

- Relative-time formatter (`rel()`: just now … years ago), absolute `fmtDateTime`, size formatter `fmtSize` (B→TB).
- File-type registry `TYPES` (regex → icon/color/label) + folder types (normal vs member-owned "Member folder" purple tag).
- Avatar system: server `S.avatars` map (from `/api/data`, `/api/group`) + deterministic colored-initial fallback; lazy loading.
- Announcements double as ticker (all) + admin CRUD.
- Settings surface: only via Members/Storage screens (`/api/settings`): `defaultQuotaGB`, `membersOnExtra`.
- 60s background refresh keeps multi-tab/multi-user state fresh (skipped while busy/modal open).
- All API errors surface as toasts; modals show inline `.err`.
- localStorage keys: `td_session`, `td_theme`, `td_layout`, `td_sort`, `td_ann_x`, `td_dysound`, `td_dypen`, `td_dybg`, `td_dybgimg`.

---

## Feature count estimate

- Screens/tabs: **11** (+ login screen)
- Distinct worker API operations: **61** (24 base paths)
- JS functions: **~193**
- Modals/dialogs: generic `modal()` + ~20 bespoke (share, versions, details, move, lock, avatar, member add/reset/limit, announcements n/a, ticket new, list/row, CSV import, group delete confirm, diary entries list, diary bg, diary shot menu, note editor modal, change password, delete confirms ×10)
- Estimated discrete user-facing features: **~120–140** (Drive ~25, Notes ~15, Tickets ~12, Diary ~35, Database ~18, Group ~10, Shares ~8, Announcements ~6, Members ~10, Storage ~10, shell/auth ~12).
