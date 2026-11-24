# v25 — Mix Mode (3 slots = 3 different content types) + VPN menu fix

## 1. Mix Mode

**Firebase path (per account):** `dashboardSettings/variety`

```json
{ "enabled": true, "strict": false,
  "types": ["RINGTONE","WALLPAPER","WALLPAPER_24H","WALLPAPER_DUAL","WALLPAPER_BATTERY","LIVE_WALLPAPER","CHARGING_ANIMATION"],
  "updatedAt": 1760000000000, "updatedBy": "panel" }
```

**Bot state (written by the workflow):** `uploadState/varietyUsed = { date: "M/D/YYYY", types: ["RINGTONE", ...] }`

### Behaviour
| Setting | What the bot does |
|---|---|
| `enabled: false` / missing | **Normal mode** — unchanged. One content type per day, rotating `AUDIO → WALLPAPER → 24H → DUAL → BATTERY → LIVE → CHARGING` (with low-stock skip + day lock). |
| `enabled: true` | **Mix mode** — each of the 3 daily slots uploads a *different* content type. Order for the day = selected `types` rotated by the Dhaka day number (so slot 1 is not always the same type). Slot k picks the first type in the order that has **not been uploaded today** and **has a queued file**. Types with no stock are skipped. |
| `strict: true` | Never repeat a type on the same day. If every unused type has no stock the run waits (`MIX_MODE_WAIT` in the log / Telegram) instead of falling back to a repeat. |
| `strict: false` | If all unused types are empty, it falls back to a type already used today (so the slot is not wasted). |
| Pinned items | Always win (same as before), regardless of mode. |

- Needs ≥ 2 selected types; ≥ 1 queued file per type for a full 3-different day.
- `uploadState.uploadDayType` still rotates in the background, so turning Mix mode OFF resumes the normal cycle immediately.
- Telegram reports show `🎨 মিক্স মোড · <type>` instead of the day type while the mode is on.

### Where to switch it
- **Panel:** Schedule tab → *Mix Mode* card (one card per account, toggle + type chips + strict + Save).
- **App:** Schedule screen → *Mix mode* card (same fields, per account).
- Both save to `dashboardSettings/variety` of that account; the bot reads it on every run (no GitHub change needed).

### Files changed
- `zedgeN.yml` — `getNextWallpaperFromRealtimeDB(dayType, dayTypeLocked, variety)`, variety load in main, `varietyUsed` patch after each upload, `dayLabelBn()` for Telegram.
- `index.html` — `#varietySettings` section, `renderVarietySettings()`, Firebase listeners, CSS `.vty-*`.
- App — `data/Models.kt` (`VarietyConfig`, `VarietyUsed`), `data/QueueRepository.kt`, `ui/MainViewModel.kt`, `ui/screens/ScheduleScreen.kt` (`MixModeCard`).

## 2. VPN menu not opening — fix
- **App (root cause):** `FloatingNavBar` laid out 7 tabs with `SpaceBetween` inside a fixed-width pill. On ≤ 360 dp phones the 7th tab (VPN) was pushed outside the clip and the tap never reached it. The bar now scrolls horizontally when it does not fit (still evenly spaced when it does), paddings are slightly tighter, and the selected tab auto-scrolls into view. File: `ui/components/FloatingNav.kt`.
- **Panel (safety):** nav buttons now route on click as well as on `hashchange` (`navigateTo('#vpn')` + `vpnRender()`), and `initVpnPanel()` is wrapped in try/catch so a VPN init error can never break the other buttons.

Rebuild the app (`ZedgeApp` repo → Actions) to get the fix on the phone.
