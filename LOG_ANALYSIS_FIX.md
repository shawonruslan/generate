# His batch log, read line by line (v1.27.0+65)

Log of 2026-11-27 ~19:44-19:46 (30-prompt batch), newest first.

## Where the time actually went

- Prompt 11 end-to-end: ~38 s. Metadata + enhance round ~13 s
  (incl. a 4 s token refresh), render ~15 s. Normal.
- Prompt 12: metadata ~10 s - then the batch DIED, in two steps:
  1. Credits ran out (2/50, needed 4) -> fresh account creation
     took ~77 s. Of that, ~31 s was temp-mail waste: mail.tm
     answered 403, mail.gw burned a full 15 s timeout, only then
     GuerrillaMail worked instantly.
  2. The fresh account had terms pending -> the OLD build
     halted the whole batch ("18 prompts not started"). Fresh
     accounts ALWAYS have terms pending, so rotation = death.
     (Fixed in v1.26.0: auto-accept, incl. at connect time.)

## Fixed here

- Temp-mail order: GuerrillaMail FIRST (the only provider that
  worked in the log), mail.tm / mail.gw as fallbacks.
- Provider timeouts 15 s -> 8 s: a dead provider now costs at
  most 8 s instead of 15 s.

## Not a problem

- "Stable Audio token refreshed" every ~4 min in later log
  lines is the background keep-alive (access tokens are
  short-lived); each refresh is ~4 s and off the critical path.

NOT compiled, NOT live-tested.
