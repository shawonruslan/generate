# v27 - Glass UI redesign (panel)

New look, nothing removed. Everything old still works (same ids, same Firebase paths, same buttons).

## What changed
- **Sidebar navigation** (collapsible, remembers state) instead of the tab row. Mobile: hamburger + off-canvas drawer.
- **New sticky glass header**: account switcher, LIVE SYNC, quick stat widgets (active account, queued, failed, wallpapers, ringtones, Dhaka clock), bell + menu.
- **Live notification ticker** under the header + full **Notifications** page (filters, mark read, clear). Feeds from every toast/alert the panel shows, metadata warnings, failed-upload changes. Stored per device (localStorage). Custom code can push with `window.v27Notify(text, kind, account)`.
- **Home hero** with greeting, Dhaka clock, quick actions; stat cards glass + count-up animation.
- **Asset details is now a page** (`#item`) instead of a modal - back button, breadcrumbs, sticky action bar. Browser back works.
- **Mobile preview page** (`#preview`): big phone frame, Aurora/Dark/Light/Blur stage, size slider, lock-screen overlay with real Dhaka time, fullscreen. Uses the real preview media so nothing is duplicated.
- **Theme Studio -> Element colors**: header, sidebar, cards, buttons, ticker, badges, active menu. Saved in Firebase `dashboardSettings/theme.elements` (per account, same as the rest of the theme). 4 new presets: Obsidian Glass (new default for fresh installs), Aurora, Ember, Graphite.
- Animations: page rise, hover lift, count-up, bell ring, marquee, skeleton shimmer, glow blobs. Respects `prefers-reduced-motion`.

## Files
- `index.html` only (panel). No yml / bot changes. App redesign comes separately.


## v27.1 polish
- Default theme is now **Obsidian Glass** (dark, violet/cyan). Old yellow local theme cache is cleared once; if a yellow theme was saved in Firebase pick another preset in Theme Studio.
- New favicon (bolt on dark gradient).
- Notification ticker is hidden until a real notification arrives; welcome message removed.
- Header: duplicate stat chips and duplicate bell removed; header height now measured live.
- Home hero slimmer; quick-action buttons only on mobile (sidebar covers desktop).


## v27.2
- Legacy yellow (sunflower) theme saved in Firebase by older versions is ignored -> Obsidian Glass shows by default. Saving any theme from Theme Studio (flag v271) is respected, including Sunflower if chosen on purpose.
- Header controls unified: 40px height, 12px radius, same glass border, no heavy shadows.
- Item page: preview frame no longer clips the slot chips / 24H grid.


## v27.3
- Header brand text, Today's uploads overview (counts, countdown digits, times, pills), schedule countdown and stat cards now follow the active theme text/primary/accent colors, so every preset and custom Theme Studio color stays readable. Header/Card element colors from Theme Studio apply to these too.


## v27.4
- Schedule calendar redesigned as wide glass cards (auto-fill, min 380px), gradient date tile, no text cut-off (header/day-type strip no longer wrap or overflow), gradient countdown tiles, theme-aware text everywhere.


## v27.6
- Sidebar footer (clock / Theme / collapse) no longer cut off: nav list scrolls instead; buttons use theme primary/accent + text color.
- Notifications page was rendered outside the main content area (hidden under the sidebar) - moved into the tab container.
- Asset Details preview column: no sticky/overflow clipping of slot chips / 24h grid; chip text follows theme.
- Phone preview slideshow: crossfade (ghost of previous frame fades out after new frame decodes) - no flicker.


## v27.7
- Asset Details page: removed the empty gap above the card (other container children hidden while the item page is open, tighter top padding).
- Item title gradient now clipped to text (was a solid bar).
- Collapsed sidebar: Theme / expand buttons are 40px squares stacked vertically.

## v27.10 generator fix
- Live Wallpaper / Charging Animation metadata: generator now uses the record thumbUrl JPEG directly (no video download / ffmpeg needed); falls back to frame extraction. thumbUrl also counts as a valid source in the scan.
