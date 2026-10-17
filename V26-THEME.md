# v26 — Theme Studio (panel + app)

Users can now customize the look of the web panel **and** the Android app. The theme is saved **per Zedge account** in Firebase, so the panel and the app always show the same theme for the account you are working in.

## Where
- **Panel:** header → 🎨 (palette button, next to the bell) → *Theme Studio* drawer.
- **App:** top bar → 🎨 palette icon → *Theme Studio* bottom sheet.

## What you can change
| Setting | Range / options |
|---|---|
| Presets | Sunflower (default), Dark Gold, AMOLED, Ocean, Midnight, Mint, Rose, Violet |
| Custom colors | Primary, Accent, Background, Cards, Text (color picker + hex input; app also has hue/saturation/brightness sliders) |
| Font size | 80 % – 130 % |
| Corner radius | 0 % – 160 % |
| Density | Comfortable / Compact |

Everything previews live while you edit. **Cancel / Esc** discards the preview.

## Saving
- **Save for Zedge N** → writes the theme for the account currently selected in the header (panel) / account switcher (app).
- **All accounts** → writes the same theme to every Zedge account.
- The theme is also cached on the device (panel `localStorage`, app `SharedPreferences`) so it shows instantly on the next launch, even offline.
- Switching account switches the theme automatically (each account keeps its own).

## Firebase
Path: `dashboardSettings/theme` in each account's Realtime Database.
```json
{
  "preset": "dark",              // preset key or "custom"
  "mode": "dark",                // derived from background luminance
  "primary": "#ffd400",
  "accent": "#ffab00",
  "bg": "#0e0c08",
  "surface": "#181410",
  "text": "#f7f1dc",
  "fontScale": 1.0,              // 0.8 – 1.3
  "radius": 1.0,                 // 0 – 1.6
  "density": "comfortable",      // or "compact"
  "updatedAt": 1758000000000,
  "updatedBy": "panel"           // or "app"
}
```
No database-rules change is needed if `dashboardSettings/*` is already writable (it is for the GitHub / VPN / Mix-mode settings).

## Files changed
- `index.html` — theme engine (runs before CSS), all brand colours converted to CSS variables, header button, Theme Studio drawer, Firebase sync (`dashboardSettings/theme`).
- App: `ui/theme/Theme.kt` (dynamic palette), `ui/screens/ThemeSheet.kt` (new), `data/Models.kt` (`ThemeConfig`), `data/QueueRepository.kt`, `ui/MainViewModel.kt`, `MainActivity.kt`.

## Deploy
1. Upload the new `index.html` (panel) as before.
2. Push the `app/` folder to the ZedgeApp repo and let GitHub Actions build the APK (or build locally). Install the new APK.
3. Open Theme Studio, pick a theme, **Save** — the other side updates in real time.
