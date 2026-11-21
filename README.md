# MH Virtualcam v1.0.0

A virtual camera for Windows. Feed **multiple images and multiple video clips**
as your camera in Zoom, Microsoft Teams, Discord, Google Meet (Chrome), OBS
and any app that uses a DirectShow camera.

## What it does

- **Playlist** - mix images (JPG/PNG/BMP/WebP/GIF) and video clips
  (MP4/MOV/AVI/MKV/WebM/WMV) in one playlist. Drag & drop files or a whole
  folder into the window, reorder with buttons or Ctrl+Up/Down, double-click
  an item to jump to it.
- **Auto change** - images auto-advance after a hold time you set
  (1-60 sec). Videos advance when they end.
- **Loop modes** - Loop Playlist / Loop Current Clip / Off (stop at end).
- **Aspect ratio** - 16:9, 9:16, 1:1, 4:3, 3:4, 21:9.
- **Resolution** - matched to the ratio: e.g. 16:9 = 1920x1080 / 1280x720 /
  854x480, 9:16 = 1080x1920 / 720x1280 / 540x960, 1:1 = 1080x1080 / 720x720...
- **Frame rate** - 24 / 30 / 60 fps.
- **Fit modes** - Fill (crop to ratio), Fit (letterbox bars), Stretch.
- **Transitions** - Fade or Cut between clips/images.
- **Zoom & pan** - digital zoom 100%-400% (slider, +/- keys, mouse wheel),
  pan by dragging the preview or with W/D keys.
- **Keyboard shortcuts** - full control in-app, plus **global Ctrl+Alt
  hotkeys** that work while Zoom/Teams is focused. See `SHORTCUTS.md`.
- **Professional UI** - flat dark-gray theme, single yellow accent, vector
  SVG-style icons only. No emoji, no gradients.

## How it works

```
Playlist files
      |
MHVirtualCam.exe  (WPF controller, OpenCV decode + zoom/pan/fit render)
      |  BGRA frames via shared memory  Local\MHVirtualCamFrame
MHVirtualCamFilter.dll  (DirectShow source filter, C++)
      |
Zoom / Teams / Discord / Chrome  ->  camera named "MH Virtualcam"
```

## Quick start

1. Build both projects - see `BUILD.md` (Visual Studio 2022, one-time setup).
2. Run `register-filter.bat` **as Administrator**.
3. Run `MHVirtualCam.exe`, add clips/images, press
   **Start Virtual Camera**.
4. In your meeting app, choose camera **MH Virtualcam**.

## Status

v1.0.0 source release. The code was written and structure/syntax-checked,
but it has **not yet been compiled or live-tested on a Windows machine** -
the first VS2022 build + a Zoom/Teams test is the next step. If the build
shows an error, send the error log and it will be fixed against it.
