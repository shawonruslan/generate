# Ringtone Studio settings page (v1.19.2+45)

## Problem (his words, 2026-11-27)

The Ringtone Studio screen was one very long scroll: all settings
cards first, Generate near the bottom, results below that. Fixing a
setting meant scrolling a long way, scrolling again to Generate, and
again to see the generated results - on Android and Windows both.

## New layout

**Ringtone Studio (working screen)** - only two cards:
- **Create sounds**: the Ideas box, a one-line summary of the active
  settings as chips (type, duration/takes, genre, mood, BPM, Gemini
  enhancer / auto-publish when on, Stable Audio account + credits),
  and an "All settings" button.
- **Library**: the generated results, directly under Create.
- **Generate bar pinned to the bottom of the screen** (task status,
  live progress while running, Stop, Generate) - always visible,
  zero scrolling, same on Android and Windows.
- Generation log moved under the Library as its own card.
- Gear icon in the app bar also opens Settings.

**Ringtone Settings (new dedicated page)** - every setting that used
to be a card on the studio screen, grouped into sections:
Sound / Sound design / AI and publishing / Mastering / Stable Audio
account / Mastering engine. On wide screens (>= 900 px, Windows) a
section index stays pinned on the left and tapping a section scrolls
straight to it; on phones it is one clean grouped list.

## What did NOT change

- Same `RingtoneService`, same config object, same persistence
  (`saveConfig`), same generation pipeline, same account/token
  handling. The settings page writes to the exact config fields the
  studio screen used to; the summary chips read them back when you
  return.
- Library, edit/publish/delete/play/share behaviour identical
  (code carried over unchanged).

## Verification

- Both Dart files format/parse-checked OK. Standalone `dart analyze`
  in this VM reports the same missing-Flutter-SDK noise for the
  untouched settings_screen.dart (387 issues) as for the new files,
  so CI `flutter analyze` remains the real check.
- NOT compiled, NOT live-tested. First look: open Ringtone Studio -
  Generate should be visible at the bottom without scrolling; open
  the gear, change Genre/Duration, go back - the summary chips must
  show the new values.
