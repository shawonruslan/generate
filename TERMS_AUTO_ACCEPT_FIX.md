# Stable Audio terms: auto-accept everywhere (v1.20.4+57)

## His complaint (2026-11-27, screenshot)

The "Review / accept terms" button in the built-in-browser Stable
Audio signup needed a MANUAL click - why isn't it automatic?

## Cause

Both signup drivers only auto-accepted terms when the URL
contained /terms or onboarding:
- Android: StableAudioWebViewActivity.kt injected JS
- Desktop: stable_audio_browser.dart step 5

Stable Audio also shows terms as a modal/banner with a
"Review / accept terms" button on OTHER pages (no /terms in the
URL), so the automation never scanned for it, the flow stalled,
and he had to tap it himself.

## Fix (both drivers, same logic)

On ANY stableaudio.com page (not login/authkit), before any other
action, scan visible buttons/links: text matches accept|agree AND
(terms page OR text mentions term/review OR an unchecked checkbox
is present). Tick unchecked checkboxes first, then click - 
throttled to one click per 5 s so it cannot loop. The /terms-page
fallback (Continue / Get started / submit) is kept. Desktop loop
keeps waiting while clicks are happening instead of breaking at
the first stableaudio page.

## Verification

- Dart format/parse OK; both new JS blocks pass `node --check`
  (desktop snippet checked after Dart string unescaping).
- NOT compiled, NOT live-tested. His test: Create account - the
  "Review / accept terms" step should now click itself on both
  Android and Windows.
