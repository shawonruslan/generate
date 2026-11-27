# Upscale + resize to 1620x2880 for Gemini images (v1.20.0+53)

## His report (2026-11-27)

The Gemini HD Studio Chrome extension upscales every generated
image and resizes it ready (1620x2880); in MH STUDIO that feature
was effectively missing: any image generated below 1620x2880 must
be upscaled and resized to exactly 1620x2880.

## Extension pipeline (background.js, read from his v2.5.3 ZIP)

`upscaleResizeAndSaveBlob`: pre-crop to target aspect ->
`upscaleViaCloudinary` (Cloudinary `e_upscale`) -> on ANY
Cloudinary failure, fall back to local progressive super-sampling ->
`resizeImageToJpg100`: exact target W x H JPG, quality stepped to
keep the file <= 8 MB (Zedge). The extension carries its own
Cloudinary setup, so this always runs, for every image.

## Why the app did not deliver the same

The pieces existed (crop -> CloudinaryUpscaler -> fitToAspect at
2880 long side) but were unusable in practice:

1. Generation was BLOCKED without Cloudinary credentials - Home
   and Batch refused to start ("Add Cloudinary credentials for
   Gemini AI upscale first"), and GeminiImageApi._draw threw
   CREDENTIALS_REQUIRED before drawing anything.
2. Upscale was Cloudinary-ONLY: any upscale error (no credits,
   e_upscale not permitted, timeout) failed the whole generation.
   No local fallback like the extension's.
3. The final JPG had no <= 8 MB guarantee (fixed q95), so a
   1620x2880 output could exceed Zedge's per-file limit.

## Fix (mirrors the extension's shape)

- `gemini_image_api.dart` _draw: hard credential gate removed.
  Upscale = Cloudinary AI when credentials are set; on any error,
  or with no credentials, the pre-cropped image goes straight to
  the local fit, which upscales it (cubic + light sharpen - the
  on-device equivalent of the extension's super-sampling fallback).
  The final fit ALWAYS resizes to the exact target size for the
  chosen ratio: 9:16 -> exactly 1620x2880, whatever size Gemini
  returned.
- `fitToAspect`: JPG size guarantee added - encode at q95, step
  quality down (90...60) until <= 8 MB. Dimensions never change.
- Home + Batch start gates: Cloudinary credentials now gate only
  the Cloudinary engine; Gemini generation always runs.
- Settings copy updated: Cloudinary section is "Optional - enables
  Cloudinary AI upscale for Gemini images"; engine hint explains
  the on-device fallback and the exact-size guarantee. Home/Batch
  engine hints updated to match.

## Verification

- Dart format/parse OK on all 4 touched files. NOT compiled (CI
  flutter analyze is the real check), NOT live-tested.
- His test: with the Gemini engine, generate a 9:16 image WITHOUT
  any Cloudinary credentials in Settings - it must complete and
  the saved JPG must be exactly 1620x2880 (check the result card's
  dimensions / file properties). With credentials added, the same
  flow uses Cloudinary AI upscale first.

## Correction (v1.20.1+54) - the extension needs NO credentials at all

He pointed out the real miss: in the extension the upscale runs
with NO Cloudinary credentials entered by anyone. Reading
background.js properly this time: the extension ships a public
tools cloud (dtz0urit6) + public API key + the "cloudinary-tools"
upload preset, and the upload signature comes from a public
Netlify function (cloudinary-tools.netlify.app/.../sign-upload-params)
that holds the secret server-side. Delivery chain:
f_jpg,w_512,e_upscale,q_auto/<public_id>.jpg, polled until ready
(423 = still processing).

LIVE-VERIFIED from this machine before porting: signed, uploaded
a 540x960 test JPG through that exact flow, polled the delivery
URL, and got back a 2048x3640 AI-upscaled JPG. No user credentials
anywhere in the flow.

Port: new lib/extension_upscale.dart (ExtensionUpscaler) mirrors
the flow in Dart (sign -> multipart upload -> poll delivery URL,
423/404 = keep waiting, result must decode). _draw now tries it
FIRST; fallbacks: user's own Cloudinary account if added, then
on-device upscale. v1.20.0's gate removal and exact-size/8MB
guarantees stay. Settings/Home/Batch copy updated: Gemini upscale
is built in, Cloudinary keys only serve the Cloudinary engine.

## Order correction (v1.20.2+55) - "Age upscale then 1620x2880"

His explicit order: FIRST upscale, THEN resize to 1620x2880. One
step in the app violated the spirit of that: the pre-upscale crop
also shrank the image to a 1024 long side before the AI upscale
ever saw it. Now the pre-step is crop-to-aspect ONLY at native
resolution (no resize), then the AI upscale, then the final fit
resizes to exactly 1620x2880 (9:16) - the extension's exact order:
preCropBlobToTargetAspect -> upscaleViaCloudinary ->
resizeImageToJpg100.
