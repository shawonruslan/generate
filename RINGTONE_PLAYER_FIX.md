# Library result cards as real audio players (v1.19.3+46)

## Problem (his words, 2026-11-27)

Generated-audio results in the Library looked plain: title, one meta
line, tags, and a bare play/stop icon - no progress, no time, no
player feel.

## New result card

- Big filled play/pause button; tapping the playing card pauses,
  tapping again resumes, tapping another card switches playback.
- Seekable progress slider (slim track) with **elapsed / total time**
  (m:ss) - drag to seek while a tone is loaded.
- **Playback speed** control on the active card (1x / 1.25x / 1.5x /
  2x, cycles on tap).
- Meta as chips instead of a cramped text line: category, MP3/WAV,
  file size, Take n/total (when more than one take), musical key,
  Local / Queued: account.
- Tags kept as a quiet secondary line; actions (Edit, Export, Share,
  Publish, Delete) in one evenly spaced row under a divider.
- Playback state is live from the player streams
  (position / duration / state / complete), and resets cleanly when
  a tone finishes or is deleted.

Everything else (generation, library data, edit/publish/delete
behaviour) is unchanged; this builds on v1.19.2's layout (dedicated
Ringtone Settings page + pinned Generate bar) and v1.19.1's Gemini
Android fix.

## Verification

- Dart format/parse OK. NOT compiled (CI `flutter analyze` is the
  real check), NOT live-tested. First look: generate or open the
  Library, play a tone - progress must move with time on both sides,
  pause/resume and seek must respond, speed button cycles.
