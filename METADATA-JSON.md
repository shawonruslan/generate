# AI Metadata JSON (v22)

Upload a `.json` **together with** your media files, or put it **inside the ZIP/RAR** next to the media (smart import reads it automatically) (panel dropzone / Choose Files, distribute dropzone, or the Android app picker).
Every file whose name matches an entry gets `title`, `tags`, `category`, `description` written to Firebase immediately
(`metadataSource: "json"`), so `generator.yml` skips Gemini metadata for it. Files without a match behave exactly as before.

Click **Copy AI prompt** in the panel/app and paste it to any AI agent together with the files -> it returns this JSON:

```json
[
  { "file": "sunrise_bells.mp3", "title": "Amber Sunrise Bells", "tags": ["morning", "bells", "calm", "soft", "bright"], "category": "CLASSICAL", "description": "A soft bell melody for calm mornings." },
  { "file": "neon_city.mp4", "title": "Neon Rain City", "tags": "neon, city, rain, night, purple", "category": "TECHNOLOGY", "description": "Rainy neon street loop." }
]
```

- `file`: exact file name, **unique per entry** (matching ignores case, extension, spaces/dashes). Files in sub-folders: use `folder/file.jpg` or add `"folder": "01_basalt_cross"`. If names repeat anyway, entries are handed out in JSON order (import runs in natural file order) and a warning is shown. For a 24H / Dual / Battery set use the first image's name.
- `tags`: array or comma string, 2-10 tags. `title` max 30 chars. `description` required.
- `category`: ringtone list or wallpaper list (see prompt). Invalid -> `OTHER` (with a warning).
- Entries with promo/link/adult wording are rejected (Zedge Content Policy) and fall back to Gemini metadata.
- Also accepted: `{ "files": [...] }` or `{ "sunrise_bells.mp3": { ... } }`.
