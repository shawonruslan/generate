# v27 - App redesign (Glass UI)

Same features, new look. All screens, view-models, Firebase paths and buttons are unchanged.

- **Aurora background**: slowly drifting primary/accent glow blobs behind every screen (follows the active theme, per account).
- **Glass cards**: every SectionCard / StatTile / nav pill is now translucent with a hairline border; stat numbers count up/down.
- **Header**: gradient brand mark, transparent glass top bar.
- **Bottom nav**: floating glass pill (still scrolls on small phones, VPN tab always reachable).
- **Home hero**: gradient hero with live Dhaka clock (bot time).
- **Asset details is a full page** (was a bottom sheet): back gesture / Close returns to the list. Mobile preview (fullscreen phone) stays.
- **Page transitions**: slide + fade + subtle zoom.
- **New presets** in Theme Studio: Obsidian Glass, Aurora, Ember, Graphite (same keys as the web panel, so the Firebase-synced theme matches).

Files touched: `MainActivity.kt`, `ui/components/Glass.kt` (new), `ui/components/Common.kt`, `ui/components/FloatingNav.kt`,
`ui/screens/HomeScreen.kt`, `ui/screens/ItemDetailSheet.kt`, `data/Models.kt`. Rebuild the APK (same Gradle setup).

## v27.8 - app: Theme Studio elements + dark-theme contrast pass
- `ThemeConfig.elements` (header, sidebar, card, button, ticker, badge, navActive) now round-trips with Firebase `dashboardSettings/theme.elements` - the same per-element colours you set in the web panel apply in the app, and saving from the app keeps them.
- Theme Studio sheet: new "Element colors" section (Auto / custom hex / HSV sliders / Auto reset).
- Palette: `card` -> all glass cards + Material surface, `button` -> primary buttons, `header` -> home hero + logo, `sidebar` -> floating nav bar, `navActive` -> selected nav pill / chip, `badge` -> pin badge + TODAY chip.
- Contrast: Schedule planner pills/badges/passed-state, calendar day cards, countdown blocks (calendar + upload overview) no longer use fixed cream/gold colours - they derive from the active theme so text stays readable on dark themes. Phone mockup bezel is neutral graphite.
- Rebuild the APK to get this (web panel unchanged in v27.8).

## v27.9
- StatTile: icon inside the coloured square (type icons on Home queue tiles, hourglass/check on Planner, pin/clock on Pin Manager). Fallback = dot.
- Today's uploads carousel: snap-per-card, starts on the active account, width leaves a peek of the next card.
