# Mahbub build - config summary (3 accounts) [v40.9: Zedge 2 + Zedge 3 added]

| Account | Firebase project | Realtime DB URL |
|---|---|---|
| ZEDGE1 | zedge1-2624f | https://zedge1-2624f-default-rtdb.firebaseio.com |
| ZEDGE2 | zedge-2 | https://zedge-2-default-rtdb.firebaseio.com |
| ZEDGE3 | zedge-3 | https://zedge-3-default-rtdb.firebaseio.com |

R2 worker: https://raspy-term-bb6e.salakhan101xxx.workers.dev

Workflows: `zedge1.yml` + `earning-zedge1.yml`, `zedge2.yml` + `earning-zedge2.yml`, `zedge3.yml` + `earning-zedge3.yml` (earning crons staggered :19/:29/:39). Generator targets: zedge_1 / zedge_2 / zedge_3 / all_accounts.
Filled in: `index.html` (panel, Zedge 1+2+3 in the account list, distOrder/VPN/earnings), `app/.../core/Core.kt` (Android, owner "Mahbub"),
`desktop/lib/config/profile_data.dart` (Windows, profile `mahbub`), `BUILD_PROFILE: mahbub` in both build workflows.
Telegram greeting: "হ্যালো মাহবুব ভাই". Panel: "Mahbub" in sidebar + "Good morning, Mahbub bhai".
`python3 check_config.py` re-checks everything.

Time zone: **Asia/Riyadh (UTC+3)** everywhere - bot upload windows/exact times, Telegram times + greeting, panel, Android, Windows app.
Upload window hours (e.g. 10:00) are Riyadh time. Default windows: Zedge 1 = 10/15/20, Zedge 2 = 11/16/21, Zedge 3 = 5/11/17 (staggered, same as panel DEFAULT_UPLOAD_WINDOWS).
