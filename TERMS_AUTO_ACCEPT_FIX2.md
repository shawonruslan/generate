# Terms auto-accept, for real this time (v1.26.0+64)

His screenshot: Ringtone generation halted with "Halted: Review
and accept Stable Audio terms in the account panel before
generating audio." He has ordered auto-accept repeatedly.

## Why it still halted

v1.20.4 fixed only the BROWSER side (signup/login webview
auto-click). The API side had its own gate: acceptTerms() (a
simple PATCH /v1alpha/user) existed but was deliberately wired
to a manual Settings button only - its doc comment literally
said "Never called without explicit UI consent" - and
_requireAcceptedTerms() THREW the halt message before every
render. That design decision is removed.

## Now

- _requireAcceptedTerms() auto-accepts: when the account flags
  terms pending, it fires acceptTerms() (deduped, in-flight
  shared) and generation proceeds. Only a failed accept PATCH
  surfaces an error.
- If the render API itself rejects with a terms error
  mid-flight: auto-accept + retry the render once with the
  same seed.
- A freshly created/connected account with pending terms is
  auto-accepted at connect time in RingtoneService.
- The Settings "Accept terms" button remains as a manual
  fallback; it should rarely be needed now.

NOT compiled, NOT live-tested.
