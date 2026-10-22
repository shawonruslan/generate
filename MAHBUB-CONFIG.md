# Mahbub build - config summary (1 account)

| Account | Firebase project | Realtime DB URL |
|---|---|---|
| ZEDGE1 | zedge1-2624f | https://zedge1-2624f-default-rtdb.firebaseio.com |

R2 worker: https://raspy-term-bb6e.salakhan101xxx.workers.dev

Only Zedge 1 exists: `zedge1.yml` + `earning-zedge1.yml` (zedge2-4 removed).
Filled in: `index.html` (panel, only Zedge 1 in the account list), `app/.../core/Core.kt` (Android, owner "Mahbub"),
`desktop/lib/config/profile_data.dart` (Windows, profile `mahbub`), `BUILD_PROFILE: mahbub` in both build workflows.
Telegram greeting: "হ্যালো মাহবুব ভাই". Panel: "Mahbub" in sidebar + "Good morning, Mahbub bhai".
`python3 check_config.py` re-checks everything.
