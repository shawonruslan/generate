# v23 – Metadata guard, missing-metadata alerts, exact per-slot upload time

This release adds three features across the **workflows (zedge1–4.yml)**, the **web panel (index.html)** and the **Android app**.
No new secrets, no Firebase rules changes, no cron-job.org changes are required.

---

## 1. Metadata guard (workflows)

A queued file is only uploadable when **all three** fields are present:

| Field | Rule |
|---|---|
| `title` | non-empty string |
| `tags` | non-empty string or non-empty array |
| `category` | non-empty string |

`zedgeN.yml` now splits the queue into *uploadable* and *missing-metadata* items **before** choosing what to upload.
Files without metadata are **never uploaded** – they stay `queued` and are simply skipped until the metadata is added
(from the panel, the app, or by running `generator.yml` in `metadata` mode).

When only metadata-less files are left the run ends with `EMPTY … NO_METADATA => N` and the idle Telegram card says
how many files are blocked.

On every run the bot also writes a report to Firebase:

```
dashboardSettings/metadataAlerts
  count        : number of blocked files
  items/{id}   : { name, contentType, missing:["title","tags"], createdAt }
  key          : fingerprint of the blocked set
  updatedAt / updatedDhaka / runId
  notifiedKey / notifiedAt   (Telegram alert is sent once per change of the set)
```

A Bangla Telegram alert is sent **once** whenever the set of blocked files changes (not on every ping).

## 2. Missing-metadata notifications

### Web panel
* Header **bell** with a red badge = number of blocked files in the active account. Click → Upload tab filtered to *No metadata*.
* Home page **"Metadata missing"** card (amber) listing the files with the missing fields and a **Fix** button that opens the editor.
  Below it: the bot's last report for the *other* accounts (click to switch).
* Queue cards get a **No metadata** badge; the status filter has a new **No metadata** option; the item modal shows a warning box.
* Toast when new blocked files appear. **Enable browser alerts** asks for the Notification permission and pushes a desktop notification for new blocked files.

### Android app
* Home: **No metadata** stat tile and a **Metadata missing** card (tap a row → detail sheet → *Publishing fields*).
* Detail sheet: amber "Upload blocked – metadata missing" warning.
* System notification (channel *Metadata alerts*) whenever **new** blocked files appear in the active account; already-seen files are remembered so you are not re-notified on every launch. Android 13+ asks for the notification permission on first start.
* In-app snackbar for the same event.

## 3. Exact per-slot upload time (per account, 3 slots)

Each Zedge account still has **3 uploads per day**. Each slot can now be one of:

| Mode | Behaviour |
|---|---|
| **Random** (default, `exact:false`) | old behaviour – a deterministic random 30-min slot inside the 3 h window starting at `hour`, plus 0–14 min random delay |
| **Exact** (`exact:true`) | the bot uploads at **`hour:minute` sharp** (Asia/Dhaka). No random slot, no random delay. |

Firebase schema (written identically by panel and app):

```
dashboardSettings/schedule
  windows   : [4, 10, 16]                         (legacy – hours only, kept for older builds)
  slots     : [ {hour:4, minute:30, exact:true},
                {hour:10, minute:0, exact:false},
                {hour:16, minute:15, exact:true} ]
  updatedAt : 1726500000000
  updatedBy : "panel" | "app"
```

* **Panel → Schedule settings**: per slot an hour dropdown, a time input, and an **Exact** checkbox. Save writes both `windows` and `slots`.
* **App → Planner → Upload schedule**: per slot an **Exact** switch; tapping an exact slot opens a time picker.
* Validation is the same everywhere: 3 slots, hours 0–23, at least 3 h between slot hours, last slot ≤ 9 PM (so every window ends before midnight).

### How the gate honours exact times
The cron ping stays `0,30 * * * *`. On a ping inside an exact slot's window the gate
* if the exact minute is still ahead (≤ 30 min) – sleeps until that minute, then starts the upload;
* if the exact minute has already passed and the slot did not run yet – runs immediately (catch-up, within the 3 h window);
* skips the workflow's *random delay* step for exact slots.

`dashboardSettings/gate.slotsUsed` shows which slots (and exact flags) the bot evaluated on its last ping, and each
`gate.runs/{date}/{slot}` entry now carries `exact:true|false`.

---

## Upgrading from v22

1. Replace `zedge1.yml … zedge4.yml` (and `generator.yml` if you changed it) in `.github/workflows/`.
2. Replace `index.html` on your hosting.
3. Rebuild the app (`app/.github/workflows/release-apk.yml`) and install the new APK.
4. Nothing to change in Firebase, R2, Telegram or cron-job.org. Existing `windows`-only schedules keep working (they are treated as 3 random slots).

### v23.1
- Redesigned slot editor (panel + app): each slot is a stacked tile with a **Window / Exact** segmented toggle and a large hour / time field. No more cramped rows.

- **Custom window (From – To)**: in Window mode you now set your own start and end time per slot; the bot picks one random minute inside that range each day (deterministic hash, same in panel/app/bot) and sleeps until it. Schema: `slots[{hour, minute, exact, endHour, endMinute}]`. Old v23 slots without an end fall back to a 3 h window. The extra 0–14 min random delay step is no longer used (the gate already lands on the minute). Validation: window ≥ 30 min, ≥ 30 min gap between slots.
