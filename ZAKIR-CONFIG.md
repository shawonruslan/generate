# Zakir build - config summary (4 accounts)

| Account | Firebase project | Realtime DB URL |
|---|---|---|
| ZEDGE1 | shimul-zedge1 | https://shimul-zedge1-default-rtdb.asia-southeast1.firebasedatabase.app |
| ZEDGE2 | shimul-zedge-2 | https://shimul-zedge-2-default-rtdb.asia-southeast1.firebasedatabase.app |
| ZEDGE3 | shimul-zedge3 | https://shimul-zedge3-default-rtdb.firebaseio.com |
| ZEDGE4 | shimul-zedge-4 | https://shimul-zedge-4-default-rtdb.firebaseio.com |

R2 worker: https://white-flower-a665zedge-r2-gateway.shawonbarba1.workers.dev

Filled in: `index.html` (panel), `app/.../core/Core.kt` (Android), `desktop/lib/config/profile_data.dart` (Windows, profile `zakir`),
`BUILD_PROFILE: zakir` in both build workflows. Bots + generator read the DB / R2 URLs from GitHub secrets - see SECRETS.txt.
Telegram greeting: "হ্যালো জাকির ভাই". `python3 check_config.py` re-checks everything.
