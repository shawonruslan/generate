# Team Drive Web — Design Tokens
Source: `~/workspace/user/files/index-12.html` (single-file app, style block lines 14–956).
Theme mechanism: CSS variables on `:root` (= **day/light** mode) overridden by `[data-theme=dark]` (= **night** mode). JS also sets `data-theme="light"` explicitly in some sessions, with extra `[data-theme=light]` overrides noted below.
Base: `body{font-size:14px}`, font smoothing antialiased. `h1,h2{letter-spacing:-.015em}`.

> Global rule (stated in CSS as "FLAT PRO THEME (2026-11-04) — no gradients, no neon"): all app chrome (buttons, nav, panels, topbar, sidebar) is **flat solid colors**. The only gradients in the file are inside the 3D diary-book *artwork* (leather/paper textures) — not UI chrome. The Flutter diary build renders those flat.

## 1. Color palette

### Core tokens

| Token | Day (`:root`) | Night (`[data-theme=dark]`) | Used for |
|---|---|---|---|
| `--bg` | `#eceae2` | `#161616` | Page background |
| `--panel` | `rgba(255,255,255,.72)` (frosted glass w/ blur, see below) | `#1e1e1e` | Cards, tiles, topbar, modals, inputs |
| `--side` | `rgba(247,246,242,.8)` | `#111111` | Sidebar background |
| `--side2` | `rgba(255,255,255,.55)` | `#2a2a2a` | Sidebar hover, icon chips, secondary wells |
| `--sideText` | `#5d6169` | `#a6a6a6` | Sidebar nav label color |
| `--text` | `#22242a` | `#e9e9e9` | Primary text |
| `--muted` | `#868a93` | `#909090` | Secondary/muted text, captions |
| `--line` | `rgba(34,36,42,.1)` | `#2d2d2d` | Borders, dividers |
| `--line2` | `rgba(34,36,42,.06)` | `#262626` | Subtle row dividers |
| `--soft` | `rgba(255,255,255,.55)` | `#232323` | Input/search resting bg, hover fills |
| `--soft2` | `rgba(255,255,255,.6)` | `#252525` | Tab switcher track, secondary surfaces |
| `--hover` | `rgba(255,255,255,.65)` | `#2b2b2b` | Hover background |
| `--hl` | `rgba(255,255,255,.45)` | `#202020` | Row highlight |
| `--thumb` | `rgba(34,36,42,.05)` | `#1b1b1b` | File thumbnail placeholder bg |
| `--brand` | `#4a5fd0` | `#5b7cfa` | Primary brand (buttons, active states) |
| `--brandDark` | `#3d4fb8` | `#4a68e8` | Brand hover |
| `--brand2` | `rgba(74,95,208,.13)` | `#2b3242` | Brand-tinted surface (active nav, chips, avatar bg) |
| `--danger` | `#c24040` | `#e5484d` | Danger / errors / delete |
| `--ok` | `#3d8b4f` | `#46a758` | Success |
| `--warn` | `#b97a1e` | `#e8a13c` | Warning |
| `--shadow` | `0 1px 2px rgba(70,64,50,.06), 0 12px 32px rgba(70,64,50,.1)` | `0 1px 2px rgba(0,0,0,.4), 0 12px 30px rgba(0,0,0,.45)` | Card/modal shadow |
| `--r` | `12px` | `12px` | Global card radius |

Day-mode glass: `[data-theme=light] .card, .tile, .topbar, #side, .modal, .seg { background:var(--panel); backdrop-filter:blur(18px) saturate(1.25); }` — frosted off-white panels.

### Hardcoded (non-token) colors worth copying
- Auth hero: always dark — `background:#1b1b1e; color:#fff` (both modes).
- Sidebar meter track: day `rgba(34,36,42,.12)`, night `#3a3a3a` (dark override `#1e293b`); fill always `var(--brand)`.
- Scrollbar: thumb `#b9b4a8` (night `#3d3d3d`), 10px wide, radius 8px, 2px gap via `border:2px solid var(--bg)`.
- Focus ring on inputs: `box-shadow:0 0 0 3px rgba(79,70,229,.15)` + `border-color:var(--brand)`.
- Modal overlay: `rgba(15,23,42,.45)` (night `rgba(0,0,0,.6)`), `backdrop-filter:blur(2px)`.
- Context-menu sheet scrim: `rgba(2,6,23,.45)`.
- Drag-drop overlay: `background:rgba(79,70,229,.08); border:3px dashed var(--brand)`.
- Viewer (file preview): `background:rgba(8,10,18,.94)`, text `#e5e7eb`.
- Toast: `background:var(--side); color:#fff`.

## 2. Typography

Fonts (Google Fonts + Font Awesome 6.5.2 icons):
- UI: `Inter, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif` — weights **400/500/600/700** loaded.
- Diary handwriting: `Caveat` (400–700), `Galada` (+ `DyBangla` @font-face alias for Bengali range).
- Diary numerals/titles: `Playfair Display`, italic 600.
- Code: `ui-monospace, SFMono-Regular, Menlo, Consolas, monospace`.

| Element | Size | Weight | Notes |
|---|---|---|---|
| Page title (`.head h1`) | 22px (19px ≤900px) | default 700-ish (browser bold) | `margin:0` |
| Section title (`.sec-title`) | **11px** | 800 | uppercase, `letter-spacing:.1em`, muted, with flex rule line after |
| Card title / file name (`.tile .t`) | 13px | 600 | 2-line clamp |
| Tile meta (`.tile .m`) | 12px | 400 | muted, `margin-top:4px` |
| Body | 14px | 400/500 | |
| Table header (`th`) | 12px | 600 | uppercase, `letter-spacing:.04em`, muted |
| Table cell (`td`) | default 14px | 400 | padding 11px 16px |
| Small label (`label.lbl`) | 13px | 600 | `margin:14px 0 6px` |
| Caption / hint (`.gp-hint`, `.stg-sub`) | 11.5–12px | 400/500 | muted |
| Sidebar nav label | 13.5px | 500 (600 when active) | |
| Sidebar section label (`.nav-sec`) | 10.5px | 700 | uppercase, `letter-spacing:.1em`, muted, `padding:16px 12px 6px` |
| Brand title | 15px | 700 | + subtitle 10.5px/500 muted |
| Modal title (`.modal h3`) | 18px | 700 | |
| Toast | 13px | 400 | |
| Context menu item | 13.5px | 400 | |
| Login card h1 | 26px | 700 | hero h2 34px |

## 3. Shape

- Global radius `--r: 12px` (cards, tiles, file rows).
- Buttons: `.btn` 10px; `.btn.sm` 8px; icon buttons 34×34 (topbar ghost icons 36×36 radius 11px).
- Pills/chips/tags: full-round `20px`.
- Inputs: 10px. Segmented tab switcher: 11px track / 8px buttons.
- Modals: 16px. Context menu: 12px (mobile bottom-sheet: 18px top corners). Upload panel: 14px. Toast: 11px.
- Avatars: 50% circle (36px default; profile page 112px).
- File icon boxes (`.ficon`): 9px radius at 36px size; 12px at 52px (tile); 18px at 72px (viewer).
- Shadows: cards use `var(--shadow)`; tiles only get shadow **on hover** (resting tiles are flat, border-only). Modal: `0 30px 60px rgba(0,0,0,.2)`. Buttons: **no shadow** (flat solid). Avatar: `0 2px 10px rgba(0,0,0,.28)`.

## 4. Spacing

- Content: `padding:24px` (16px mobile), `max-width:1280px`.
- Grid: `repeat(auto-fill, minmax(170px,1fr))`, `gap:14px` (mobile: minmax 150px/10px; ≤420px: 2 cols, tile padding 10px).
- Tile padding: 16px (file tiles `10px 10px 12px`).
- Section title margin: `22px 0 10px`.
- Sidebar: `padding:20px 16px`, item gap 6px; nav item padding `7px 10px` (flat-pro override).
- Topbar: `height:68px` (60px mobile), `padding:0 24px`, gap 14px.
- Modal padding 24px; action row `margin-top:18px`, gap 8px, right-aligned.
- Table: th `12px 16px`, td `11px 16px`.

## 5. Component specs

### Sidebar
- Width **260px** (desktop grid col), full-height sticky; mobile: fixed drawer `min(290px,86vw)` sliding from left.
- **Logo block**: 38×38 rounded-12 brand chip (`background:var(--brand)`) with 24px logo; title 15px/700 + subtitle 10.5px/500 muted; block padding `4px 8px 18px`. (Brand text is `#fff` in night, `var(--text)` in day via `[data-theme=light] aside .brand`.)
- **"+ New" button**: full width, `padding:12px`, radius 11px, primary style; circled plus icon `.new-ic` 22px, `background:rgba(255,255,255,.22)`; `margin-bottom:14px`.
- **Nav item**: `padding:7px 10px`, `gap:11px`, radius 11px, 13.5px/500, color `var(--sideText)`; **icon chip** `.nav-ic` 31×31 radius 10 `background:var(--soft)`, icon 14px muted. Hover: bg `var(--side2)`. **Active**: bg `var(--brand2)`, label 600 (+ `#fff` in dark), icon chip becomes solid `var(--brand)` with white icon.
- **Section labels** (WORKSPACE/TEAM/MANAGE): `.nav-sec` — 10.5px/700, uppercase, ls .1em, muted, `padding:16px 12px 6px`.
- **Unread badge** (`.nav .nb`): `margin-left:auto`, `#ef4444` bg, white, radius 20px, 11px/700, min 20×20.
- **Storage widget** (`.side-foot.stg`): `margin-top:auto`, bg `var(--side2)`, radius 12px, `padding:14px 16px`, flex gap 13px. 58px SVG **progress ring** (stroke-width 5.5, track `var(--line)`, value `var(--brand)`, round caps, % centered 11px/800). Label 11px/700 uppercase muted; numbers 16px/800 (`337 MB / 19.0 GB`, limit part 12px/500 muted); sub-line 11.5px muted, ellipsis. Old meter variant: 6px bar, radius 6px.

### Topbar
- Height 68px, bg `var(--panel)` (+day glass blur), bottom border `var(--line)`, sticky, z 10.
- **Search**: `flex:1; max-width:560px`; input resting bg `var(--soft)` border transparent; focus bg `var(--panel)` border brand; right padding 70px for the **kbd hint** — `Ctrl K` pill: 10.5px/600 muted, bg `var(--soft)`, border `var(--line)`, radius 6px, `padding:2px 7px`, absolute right 12px.
- **Actions** (`.tb-actions`): ghost icon buttons 36×36 radius 11px, 1px divider `.tb-div` (1×26px `var(--line)`, margin 0 8px).
- **Profile chip** (`.user`): `border:1px solid var(--line); background:var(--soft)`, radius 30px, `padding:4px 12px 4px 4px`; 36px avatar + name 13px/600 + role 10.5px muted capitalized; hover border brand. Dropdown `.menu`: min-width 200px, radius 12px, items `padding:9px 10px` radius 8px.

### Buttons
- `.btn`: inline-flex, gap 8px, `padding:9px 14px`, radius 10px, 500, border `1px solid var(--line)`, bg `var(--panel)`; transition .15s.
- **Primary**: `background:var(--brand); border:0; color:#fff; font-weight:600`; hover `filter:brightness(1.08)` (older rule: `background:var(--brandDark)`); disabled opacity .55. **No shadow, no gradient.**
- **Ghost** (`.btn.ghost`): transparent border+bg; hover `var(--hover)`.
- **Danger** (`.btn.danger` / `.ctx button.danger`): `color:var(--danger)`.
- **Small**: `padding:6px 10px; font-size:13px; radius:8px`.
- **Icon**: 34×34, padding 0.

### Drive tiles/cards
- `.tile`: bg panel, 1px `var(--line)` border, radius 12px, padding 16px, pointer; hover: border brand, `translateY(-2px)`, shadow, icon scales 1.05. **No resting shadow.**
- Icon box `.ficon`: 52×52, radius 12px, 24px glyph, `margin-bottom:14px`. Tint rule: day `background:var(--b); color:var(--c)`; night `background:color-mix(in srgb, var(--c) 22%, transparent); color:color-mix(in srgb, var(--c) 70%, #fff)` — i.e. **night = 22%-opacity tint wash, glyph lightened 30% toward white**.
- File name `.t`: 13px/600, 2-line clamp. Meta `.m`: 12px muted, `size · date`.
- **3-dot** (`.more`): absolute `top:10px; right:10px`, opacity .55 → 1 on hover. **File tiles differ**: `.tile.file{padding:10px 10px 12px}` with a 130px `.thumb` (radius 9px, bg `var(--thumb)`); `.more` moves to `bottom:8px; right:6px`; meta gets `padding-right:30px`; title becomes single-line ellipsis row.
- **Folder tiles**: blue folder glyph; member folders show avatar photo (`.fav` 52px + purple badge `.b` 19px overlapping bottom-right, bg `#9333ea`).
- **Owner badge** (`.tag`): 11px/600, `padding:2px 8px`, radius 20px, `margin-left:8px`; default purple `bg:#f3e8ff; color:#7e22ce` (night `#3b1d5a`/`#d8b4fe`); `.blue` `#e0f2fe`/`#0369a1`; `.warn` `#fef3c7`/`#b45309`; `.lock` (locked) `#fee2e2`/`#b91c1c`.
- **Version badge** (`.vbadge`): 11px/700, `padding:2px 7px`, radius 20px, `bg:#eef2ff; color:var(--brand)` (night `#2b3242`/`#aebaff`), `margin-left:8px`.
- List rows: `th` 12px/600 uppercase ls .04em muted, bg `var(--soft)`; `td` 11px/16px, divider `var(--line2)`; row hover `var(--hl)`.

### Inputs / selects / switches
- `.input`: 100% width, 1px `var(--line)` border, bg `var(--panel)`, radius 10px, `padding:10px 12px`; focus border brand + `0 0 0 3px rgba(79,70,229,.15)` ring.
- `select.input`: auto width, `height:36px`, `padding:7px 10px`.
- Icon field: 38px left icon padding.
- Checkbox: `accent-color:var(--brand)`.
- Option cards (`.opt`): 1px border, radius 12px, `padding:11px 14px`; selected: border brand, bg `var(--hl)`, `0 0 0 3px rgba(79,70,229,.1)` ring.
- Filter chips (`.chip`): 1px border, bg panel, radius 20px, `padding:5px 12px`, 12px/500; on: bg `var(--brand2)`, border `#c7d2fe`, color brand.

### Modals / dialogs
- Overlay `.modal-bg`: fixed inset 0, `rgba(15,23,42,.45)` (night black .6), `blur(2px)`, z 70, 20px padding; fade-in .18s.
- `.modal`: bg panel (+day glass), radius **16px**, `padding:24px`, `max-width:420px` (`.wide` 620px), 1px `var(--line)` border, `0 30px 60px rgba(0,0,0,.2)`; pop-in (translateY 14px + scale .97, .24s).
- Title `h3` 18px; body `p` muted; action `.row`: flex-end, gap 8px, `margin-top:18px`.

### Context menu
- `.ctx`: fixed, bg panel, 1px border, radius 12px (mobile sheet: full-width bottom, 18px top radius, grabber), shadow, `min-width:240px`, `padding:6px`; items `padding:8px 16px`, 13.5px, radius 8px (sheet: 12px/20px, 15px); icon 18px muted; kbd hint right-aligned 12px muted; danger items red; scale-in .12s.

### Toasts
- `#toast`: fixed `bottom:26px`, centered, bg `var(--side)`, white text, `padding:12px 18px`, radius 11px, 13px, z 80, shadow, flex gap 10px.

### Login page
- Layout `#auth`: `grid-template-columns:1.05fr 1fr`, min-height 100vh; hero **always `#1b1b1e` dark** with `padding:56px`, h2 34px/1.2, feature rows (32px icon chips `rgba(255,255,255,.12)` radius 9px); hidden ≤900px.
- Card: `max-width:380px`, h1 26px, sub muted `margin-bottom:24px`.
- **Tab switcher** (`.seg`): 2-col grid, bg `var(--soft2)`, radius 11px, `padding:4px`; buttons transparent, `padding:9px`, radius 8px, 600, muted; active: bg panel, text color, `0 1px 3px rgba(0,0,0,.08)` shadow.
- Inputs standard; primary button **full width**, `margin-top:18px`, `padding:12px`; error text 13px danger, `margin-top:12px`, min-height 18px.

### Avatars
- `.avatar`: 36px circle, bg `var(--brand2)`, color brand, 700 uppercase initials; `box-shadow:0 2px 10px rgba(0,0,0,.28)`; `overflow:hidden`, img cover. Seen-by stacks overlap `-7px` with 2px panel ring.

### Misc components
- **Stat cards** (`.stat`): panel/border/radius 12, `padding:16px`, flex gap 14px; big number 20px/700; 44px icon.
- **Notes** (`.note`): radius 12px, hover shadow; title 15px/600 `padding:14px 16px 4px`; tag chips 11px `rgba(0,0,0,.07)` (night white .1).
- **Tickets**: list/thread grid `minmax(260px,360px) 1fr`; message bubbles radius 14px (own: brand bg, white, `14px 14px 4px 14px`); status pills `.tst` 11px/700 uppercase radius 20px — open `#dcfce7`/`#15803d`, closed `var(--soft2)`/muted, high `#fee2e2`/`#b91c1c`, normal `#e0e7ff`/`#4338ca` (night variants in §1 table pattern: green `#0f2e22`/`#4ade80` etc.).
- **Ticker** (announcement bar): height 42px, bg `#eef2ff` color `#3730a3` (night `#2b3242`/`#c7d2fe`); success `#ecfdf5`/`#065f46`; urgent `#fef2f2`/`#991b1b`; label 12px/700 uppercase.
- **Upload panel**: fixed right/bottom 20px, width 380px, radius 14px; header bg `var(--side)` white 600 `padding:12px 16px`; per-file progress bar 4px radius 4px (done → `--ok`).
- **Group feed**: composer 3px brand accent bar on top; attach chip dashed border; post button flat brand; role badge 10px/800 uppercase white-on-brand radius 6px `padding:2px 7px`; pinned post `border-left:3px solid #f59e0b`; seen-by row 12px muted with overlapping avatars.

## 6. File-type icon tint map (from JS `TYPES`)

`{icon color, bg}` — day uses bg as-is; night uses the 22%/70%-white color-mix rule (§5 tiles).

| Type | Extensions | Glyph color | Tile bg |
|---|---|---|---|
| Archive | zip rar 7z tar gz tgz bz2 xz | `#b45309` | `#fef3c7` |
| Document | doc docx odt rtf | `#2b579a` | `#e0eaff` |
| Spreadsheet | xls xlsx xlsm csv ods | `#217346` | `#dcfce7` |
| Presentation | ppt pptx odp | `#c2410c` | `#ffedd5` |
| PDF | pdf | `#dc2626` | `#fee2e2` |
| Image | png jpg gif webp svg bmp psd ai eps heic raw | `#7c3aed` | `#ede9fe` |
| Video | mp4 mkv mov avi webm wmv flv | `#db2777` | `#fce7f3` |
| Audio | mp3 wav flac ogg m4a aac | `#0891b2` | `#cffafe` |
| Windows app | exe msi bat cmd | `#0078d4` | `#e0f2fe` |
| Android app | apk aab xapk | `#16a34a` | `#dcfce7` |
| Apple | dmg pkg ipa | `#334155` | `#f1f5f9` |
| Linux | deb rpm appimage run | `#1f2937` | `#f3f4f6` |
| Disk image | iso img vhd vmdk | `#475569` | `#e2e8f0` |
| Code | js ts py java kt c cpp go rs php rb dart html css json yml sh sql vue lua… | `#0284c7` | `#e0f2fe` |
| Text | txt md log ini cfg conf | `#475569` | `#f1f5f9` |
| Font | ttf otf woff woff2 | `#9333ea` | `#f3e8ff` |
| Default file | — | `#64748b` | `#f1f5f9` |
| **Folder** | — | `#d97706` | `#fef3c7` |

## 7. Diary palette (book artwork — textures in web, render flat in Flutter)

Paper `#fbf5e6` (dark mode: `brightness(.9)` filter), ink `#1e2f6e`, leather `#4a2112`/`#3b190d`/`#5a2a17`, gold `#e7c27a`/`#d9b468`/`#c99a3c`, ribbon red `#b91c1c`, margin red `rgba(214,70,70,.45)`, date-header brown `#7c2d12`, page size `min(540px,(100vw-450px)/2)` × `min(700px,100vh-236px)`. Handwriting font Caveat 600 at 31px/40px line; date numerals Playfair Display italic 600 54px. Mood ring colors: happy `#15803d`, love/angry `#be123c`, sad/calm `#1d4ed8`, tired `#6b7280`, excited `#7c3aed`.

## 8. Distinctive global rules
1. **Flat solid colors everywhere in chrome** — no gradient buttons/backgrounds, no neon; hover = `brightness(1.08)` filter or bg token swap, never a gradient.
2. Theme = CSS variables swapped by `data-theme`; transitions `background-color .2s, border-color .2s, color .2s` on chrome elements.
3. Day mode is **frosted glass** (18px blur + 1.25 saturate on panel/sidebar/topbar/modal); night mode is opaque dark grays.
4. Borders are hairlines: `var(--line)` 1px; dividers inside tables `var(--line2)`.
5. Motion is subtle: .15–.2s ease hovers, tile lift 2px, modal pop .24s; diary is the only place with rich animation.
6. Icon font: Font Awesome 6.5.2 (`fa-solid`/`fa-regular`/brands) — Flutter should map to nearest Material icons.
