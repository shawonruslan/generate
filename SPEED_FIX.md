# Speed fix - ringtone metadata / prompt enhance (v1.25.0+63)

His call: if image attach was broken, ringtone metadata
generation and prompt enhancing (same Gemini client) must be
affected too - and they are slow.

## What was actually slow (code-verified)

All Gemini features share ONE client core, so they share its
weaknesses:

1. **Sticky browser transport.** The first time Google refuses
   the copied cookies, the client escalates into the hidden
   browser and set a STATIC preferBrowser=true - for the rest
   of the app run EVERY call from EVERY feature (ringtone
   metadata, prompt enhance, wallpaper metadata) crawled
   through the browser relay, even after the cookies had
   renewed themselves. Fixed: the preference now lasts
   10 minutes, then clients try the fast direct-HTTP
   (background, no browser) path again.

2. **Retry stacking.** Ringtone: generateCompliant x3 attempts
   x ask x2 attempts x 90 s timeout = up to 9 minutes for one
   prompt when replies come back incomplete. Timeouts for
   these text rounds cut 90 s -> 60 s (ringtone _askGemini and
   the generator's _askWeb), capping the worst case at ~6 min
   while normal rounds (10-30 s) are unaffected.

3. Image-carrying metadata (Batch queue auto-scan) rides on
   askWithImage, so it also inherits the v1.24 upload +
   ProcessFile + attachment-shape fixes.

NOT compiled, NOT live-tested.
