# 💰 Hourly Earning Report — Setup Guide

Standalone GitHub Actions workflows that **only log in and collect the earning
report** — no uploads. One file per Zedge account:

| File | Account | Secrets it uses |
|---|---|---|
| `earning-zedge1.yml` | Zedge 1 | `ZEDGE1_DB_URL`, `ZEDGE1_EMAIL`, `ZEDGE1_PASSWORD` |
| `earning-zedge2.yml` | Zedge 2 | `ZEDGE2_DB_URL`, `ZEDGE2_EMAIL`, `ZEDGE2_PASSWORD` |
| `earning-zedge3.yml` | Zedge 3 | `ZEDGE3_DB_URL`, `ZEDGE3_EMAIL`, `ZEDGE3_PASSWORD` |
| `earning-zedge4.yml` | Zedge 4 | `ZEDGE4_DB_URL`, `ZEDGE4_EMAIL`, `ZEDGE4_PASSWORD` |

Plus the shared `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` (same as the upload bot).

## What it does (every run)

1. **VPN first** — reads the VPN profile from the panel/app
   (`Firebase dashboardSettings/vpn`, same as the upload bot) and brings the
   tunnel up. If the VPN fails, the run aborts before touching Zedge
   (real IP is never used). Mode `"none"` = direct/proxy as before.
2. Logs in to `upload.zedge.net` with the account's email/password.
3. Runs the **MH-EARNINGS v33** collector (same logic as the upload bot,
   including the v33.1 portal-home navigation fix).
4. Pushes to that account's Firebase `dashboardSettings/earnings`
   (+ daily `earningsHistory`) and sends the Telegram report.
5. Disconnects the VPN.

**Safety (v33.2):** if the dashboard can't be read (no stat cards), the run
**fails loudly instead of pushing `$0.00`** — your last good data in Firebase
is never overwritten by a bad read.

## Setup (per account repo)

1. Copy the matching file into the account's repo:
   `.github/workflows/earning-zedgeN.yml` (must be on the **default branch** —
   GitHub only runs `schedule` triggers there).
2. Make sure the repo has the secrets listed above
   (Settings → Secrets and variables → Actions). They are the same secrets the
   upload workflow already uses.
3. Done. It runs **every hour at :19 UTC** automatically.

To change the interval, edit the `cron:` line, e.g. every 30 min:
`cron: "7,37 * * * *"`.

## Manual run

Actions tab → 💰 Earning Report → **Run workflow**.
Optional inputs: VPN profile override, proxy, headless true/false.

## Notes

- The upload bot still collects earnings at the end of every upload run —
  this is an extra hourly safety net so the panel/apps always show fresh data.
- Each account's report goes to **its own Firebase** (`ZEDGEN_DB_URL`), so the
  panel and apps pick it up with no changes.
