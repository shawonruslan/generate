# Fully copyright-safe ringtone metadata (v1.29.0+67)

His absolute rule: ringtone title / tags / description must
NEVER contain anything copyrighted - no band names, no company
names, no created/coined names. Fully safe metadata only.

## Three layers now

1. **Generation side.** zedgePolicyRules (the policy text every
   metadata prompt carries, incl. per-take variations) gained a
   GENERIC WORDS ONLY rule: every word in title/tags/description
   must be a common descriptive English word (moods, generic
   instruments, textures, nature, scenes, times of day); never a
   proper noun, never an invented/coined word, never a word
   that could be somebody's name.

2. **Second protected-names net (policyNames).** A new guard
   regex beside policyIp: ~340 major recording artists/bands,
   record labels, tech/product companies, streaming platforms
   and audio/instrument brands (Radiohead, Queen, Yamaha,
   Roland, Bose, Spotify-class names, labels...). Wired into
   RingtonePolicy.issues (title/tags/description/prompt) and
   cleanTags (a protected tag is dropped, not published).

3. **Existing loop does the rest.** Any hit makes
   generateCompliant regenerate the metadata (up to 3 rounds)
   instead of publishing it; tags are cleaned before upload.

Verified by running the real guard in Dart:
- "Gentle Marimba Morning" + marimba tag -> clean (the
  instrument stays allowed after the v1.28 fix)
- "Radiohead Dreams" -> flagged (title)
- tag "yamaha" -> flagged and stripped
- description with "spotify" -> flagged
- "Midnight Steel Transit" -> clean

Note: no finite wordlist can contain every name on Earth; the
generic-words-only generation rule is the catch-all, the lists
are the hard backstop. NOT compiled, NOT live-tested.
