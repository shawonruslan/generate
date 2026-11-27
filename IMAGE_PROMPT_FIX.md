# Image to Prompt fix (v1.23.0+61)

His report (screenshot, 2026-11-27): Image to Prompt fails with
"Gemini web failed after 2 attempts. Last: Gemini web reply was
cut off before the closing marker." - session logged in fine.

## Two causes fixed

1. **Attachment shape (text asks).** Image-to-Prompt sends the
   picture with a TEXT ask. That path used the old minimal
   attachment entry `[[ref], filename]`, which Gemini's current
   backend silently ignores - the model never sees the picture,
   replies without describing it, and the reply never contains
   the `[/PROMPT]` closing marker the feature waits for, so every
   attempt "fails cut off". The entry is now the full shape the
   image-generation payload (and the current web UI) uses:
   `[[ref, 1, null, mime], filename, null x6, [0]]`.

2. **Attachments always JPG (his rule).** Whatever the source
   format, the image that reaches Gemini is now always JPEG:
   - `GeminiWebClient.uploadImage` is the single choke point -
     non-JPEG bytes (magic-byte check) are decoded, flattened
     onto white if alpha, re-encoded JPEG q90, filename forced
     to .jpg. Covers image-to-prompt, generation references and
     review asks.
   - Image-to-Prompt's `uploadCopy` no longer passes small
     PNG/WebP through untouched - always JPEG (<=1280 px).
   - `_prepare` likewise always outputs JPEG when decodable.

## Not verified

The HAR he offered (LimeWire link) could not be downloaded in
this environment (LimeWire's web app never writes the file to
disk here). The shape change is based on the app's own working
image-generation payload; if he uploads the HAR directly in
chat, the exact web-UI request will be diffed against this and
adjusted if needed. NOT compiled, NOT live-tested.

## HAR-verified corrections (v1.24.0+62)

He re-sent the capture via Filebin (HAR "vgnh", 176 entries,
Gemini web UI build 20261125.05). The HAR contains the full
upload flow for two images (the actual send was not captured).
Verified facts, now implemented:

1. **Upload endpoint changed.** The UI no longer uses
   content-push.googleapis.com. It uses the resumable protocol
   on `push.clients6.google.com/upload/`: POST with
   `X-Goog-Upload-Command: start` (+ Push-ID, X-Tenant-Id:
   bard-storage, content-length header, body `File name: x.jpg`)
   -> session URL from the `x-goog-upload-url` response header
   -> POST bytes with `X-Goog-Upload-Command: upload, finalize`
   -> response body is the ref `/contrib_service/ttl_1d/...`.
   The HTTP path now tries this first; legacy content-push
   remains as fallback (and is still the page-transport route).

2. **ProcessFile step (was missing entirely).** Right after
   each upload the UI calls
   `assistant.lamda.BardFrontendService/ProcessFile` with
   `[[<attachment entry>], null, 1, ["en"]]`; the backend then
   links the file to the session. The app now does the same
   after every upload (best-effort; the send still carries the
   attachment entry).

3. **Attachment entry field order.** Proven shape:
   `[[ref, null, 1, "image/jpeg"], filename, null x6, [0]]` -
   the 1 sits at index 2, null at index 1. The text path, the
   image-generation variant 1, and ProcessFile now all use it.

Still NOT compiled / NOT live-tested. The send itself was not
in the HAR; if v1.24 still fails, a capture that includes
pressing Send is the next evidence needed.
