# Cloud login + sync (v1.21.0+59) - one-time Firebase setup

## What was built

MH STUDIO account (email + password) with cross-device sync, on
his Firebase project `mh-studio-official`, free Spark plan,
Realtime Database. Implemented with plain Firebase REST
(lib/cloud_sync.dart) - deliberately NO native Firebase SDK:
no google-services.json, no Gradle plugin, nothing new for CI to
break on, identical code on Android + Windows.

Syncs TEXT ONLY (his rule - free plan, small data): browser
(Gemini) session, Zedge distribution accounts + R2 worker URL,
Stable Audio account, Cloudinary credentials, ringtone settings,
image engine + theme prefs. Images/audio never sync. Stored at
/users/<uid>/sync in the Realtime Database.

Behaviour: sign in once per device -> state syncs automatically
(app start, Settings open, and ~6 s after any synced data changes
- session saved, account added, config saved). Newest-wins if two
devices disagree. "Sync now" button in Settings -> Cloud sync.
After a restore, restart the app so every screen re-reads its
stores.

## His one-time console steps (2 minutes)

1. Firebase Console -> project mh-studio-official ->
   Authentication -> Sign-in method -> enable **Email/Password**.
2. Realtime Database -> Rules -> paste exactly:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

   Publish. (Without this, sync returns "Cloud denied access" -
   the default rules deny everything, which is what we want until
   these per-user rules are in.)
3. The database URL is already the app's default
   (https://mh-studio-official-default-rtdb.firebaseio.com - from
   the config he pasted). It can be changed in the app under
   Settings -> Cloud sync if the database is ever recreated in
   another region.

Then in the app: Settings -> Cloud sync -> Create account ->
done. Sign in with the same account on the other device and the
session/accounts/settings arrive there.

## Security notes

- The API key in the code is the project's PUBLIC client key
  (from his web config) - it only identifies the project. Real
  protection = the rules above (each user can read/write ONLY
  their own /users/<uid> node) + Firebase Auth.
- Synced values include live session cookies and account tokens.
  They sit in his own database under his own account's uid; treat
  the MH STUDIO account password accordingly (it is the key to
  all of it). Password reset works from the login card
  (Firebase sends the email).

## Verification

- Dart format/parse OK on all 7 touched files. NOT compiled (CI
  flutter analyze is the real check), NOT live-tested - the first
  live test needs his 2 console steps above, then Create account
  in the app.
