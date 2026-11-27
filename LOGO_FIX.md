# New logo: bold triangle mark (v1.19.4+47)

## His brief (2026-11-27)

Professional bold icon, triangle-shape based, **not text**, minimal,
**no border, no background shape**. Replaces the flat-yellow "MH"
lettermark from v1.17.5.

## The mark

One flat brand-yellow (#FFD400) bold triangle with a negative-space
inner triangle cut out of the base - reads as a peak / upward mark.
Single colour, no text, no border, no background: the PNG alpha is
fully transparent everywhere outside the mark itself (verified:
corner alpha 0 on every asset). Rendered at 4x supersample with
softly rounded corners (generator: ~/workspace/logo-triangle/
make_icon.py in the build notes; preview checked on dark and light).

## Assets replaced (same paths, same sizes - CI pipeline untouched)

- `assets/icon/app_icon.png` (1024) - also the in-app logo shown on
  Home, Batch and Settings screens, so those update automatically.
- `assets/icon/app_icon.ico` - Windows exe + installer, 9 sizes
  (16-256).
- `assets/icon/android/mipmap-*/ic_launcher.png` (48-192) and
  `ic_launcher_foreground.png` - foreground mark drawn at 62% so it
  sits inside the adaptive-icon safe zone.
- Adaptive-icon background colour changed from dark navy (#0D0A24)
  to fully transparent (#00000000) - no background shape, per brief.
- The phone-mockup branding spot in `device_mockup.dart` that drew a
  bordered "MH" box now paints the same triangle mark (no border, no
  text) via a small CustomPainter.

## Verification

- All PNGs re-opened and checked: sizes unchanged, RGBA, transparent
  corners, mark present; ICO contains all 9 sizes; device_mockup.dart
  format/parse OK.
- Builds on v1.19.3 (player cards) + v1.19.2 (settings page) +
  v1.19.1 (Gemini Android fix). NOT compiled - CI is the real check.

## V2 of the mark (v1.19.5+48) - "too common"

He rejected the first mark (solid triangle / peak) as too common.
Replaced with a **segmented triangle ring**: three bold trapezoid
bars forming the triangle, clean gaps at the three corners, in three
flat tones of the yellow family (#FFD400 / #FFB000 / #E08A00 - flat
colours, no gradients). An impossible-triangle (tribar) draft was
tried and dropped - it read as crossed planks, not professional.
The segmented ring was preview-checked on dark + light and at 48 px
(mdpi launcher size) - it stays crisp and recognisable small.
Same asset paths/sizes as before; device-mockup painter updated to
the same segmented geometry (single muted tone there).
Generator: ~/workspace/logo-triangle/make_icon_v3.py (+ apply_v3.py).

## V3 of the mark (v1.19.6+49) - "MH, stylish, triangle, minimal"

He rejected the segmented ring too (common) and gave the real brief:
**MH itself, styled with triangles, minimal.** Final mark: a bold
geometric **M** (two triangular peaks, deep valley) + **H** whose
crossbar is a solid triangle (play-shaped) joining the stems -
single flat #FFD400, no border, no background. Reads clearly as MH
even at 48 px (checked). Generator: make_icon_v4.py + apply_v4.py.
Wide lockup, so the adaptive foreground uses a smaller fill (0.64)
to stay inside the safe zone. The device-mockup branding painter
keeps the small segmented-triangle geometry (subtle device-back
branding, not the app logo).

## Contrast fix (v1.19.7+50) - yellow on white

His launcher screenshot showed the transparent icon composited on a
WHITE tile by the launcher - yellow on white is unreadable ("white er
moddhe yellow very bad"). The mark itself he kept; the fix is
contrast: every full icon (app_icon.png, ICO, legacy launcher PNGs)
now carries its own flat near-black background (#121216), and the
adaptive-icon background colour is #121216 again with the
transparent MH foreground on top - so on any launcher the yellow
sits on dark and pops. Preview-checked as a dark tile on a white
page: crisp.

## V4 of the mark (v1.20.5+58) - round, audio + image

He dropped the MH monogram: wants a minimal creative ROUND icon
fusing AUDIO and IMAGE (the app's two jobs). Final mark: seven
vertical waveform bars (audio) whose tops trace a mountain
skyline - tall centre peak, smaller hill - with a sun dot over the
hill (the photo element), flat #FFD400 on a dark round disc
(#121216). An earlier filled mountain-wave silhouette draft read
as a blob and was discarded before shipping. Adaptive icons: dark
background colour + the yellow mark as foreground (mark sits at
60% width, inside the safe zone); full disc version for app_icon /
ICO / legacy launchers. Generator: make_icon_v6.py + apply_v6.py.
Preview-checked dark + light + 48 px (bars and sun stay legible).
