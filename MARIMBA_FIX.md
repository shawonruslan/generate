# Marimba fix (v1.28.0+66)

His question: why do marimba-related words not work?

## Cause

The Zedge IP/brand guard regex (policyIp in ringtone_texts.dart)
banned the BARE word "marimba" - it sits in the list because
Apple's stock iPhone ringtone is NAMED "Marimba". But marimba
is also a real wooden percussion instrument - and one of the
app's own instrument chips. So picking the Marimba chip (or
typing marimba in a prompt line) made the enhanced prompt and
the "marimba" tag trip the IP guard: RingtonePolicy.enforce
flagged it (metadata rounds regenerated/burned) and the
keyword cleaner stripped the tag.

## Fix

- policyIp: bare `marimba` replaced with the stock-ring
  phrases only: `iphone marimba`, `apple marimba`,
  `stock marimba`. The instrument word is free again.
- zedgePolicyRules (the text Gemini itself reads) gained a
  clarification line: marimba the INSTRUMENT is fully allowed
  in prompts/titles/tags; only Apple's stock ringtone of that
  name is banned - so the enhancer stops avoiding the word too.

Verified by running the real regex in Dart: "warm marimba
melody", "Marimba", "piano and marimba duet" = allowed;
"iphone marimba ringtone", "Apple Marimba tone",
"stock marimba alert" = still banned.

NOT compiled into the app here (no Flutter SDK), NOT live-tested.
