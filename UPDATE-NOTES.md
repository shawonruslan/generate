# AI Upscale and result polling update

- On the main screen, generate an image and select **AI Upscale** in the result card. The generated Cloudinary-managed image is transformed with `e_upscale`; wait until it is ready before saving or sharing. Use **Use original** to revert. The selected export preset is applied after AI Upscale.
- The button is for the current single-image result, not batch images or local imports. Original history is unchanged.
- Cloudinary AI Upscale requires a source smaller than 4.2 megapixels and may consume additional transformation credits. It can be unavailable under an account's settings or limits. A 1K image is a practical starting point. Upscaling multiplies each dimension by four before any export preset, and large images can require substantial memory and bandwidth.
- Generation task polling now checks every second for the first ten checks, then every three seconds. This can reduce waiting after the server finishes but does not speed up the model itself. More frequent polling creates more API requests.
- This version still uses Cloudinary for image generation. It does not replace the generator with Gemini HD Studio's internal web RPC, and it does not add image-to-text prompt extraction.
- The source archive omits generated platform runners, as before. Follow the existing GitHub Actions instructions to build. Run `flutter test` and `flutter analyze` with Flutter 3.35+ before deploying; live Cloudinary verification requires your own credentials and account.
