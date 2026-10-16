# v24 - OpenVPN / WireGuard support (panel + app + workflows)

The runner can now change its public IP through **your own VPN** (OpenVPN `.ovpn` or WireGuard `.conf`) in addition to - or instead of - the HTTP proxy inputs.

## What changed

| Part | Change |
|---|---|
| `zedge1-4.yml` | New inputs `run_mode` (`automation` / `vpn_test`) and `vpn_profile`. New steps **Create vpn.mjs**, **VPN tunnel** (before `Create bot.js`) and **VPN disconnect** (`if: always()`). `zedge_email` / `zedge_password` are no longer *required* (blank is fine for a VPN test). |
| `index.html` (panel) | Connection card: **Repo link / path** field (auto-fills owner + repo) and per-account **workflow file** names. New **VPN (OpenVPN / WireGuard)** card. |
| Android app | Same Connection additions + new **VPN** section (`VpnRepo.kt`, `VpnSection.kt`). `GhConfig.workflows`, `Accounts.VPN_PATH`. |
| bot.js (inside yml) | VPN-aware proxy block: when the tunnel is up the HTTP proxy is ignored unless *keepProxy* is on. |

Nothing else in the automation changed - a run with VPN mode **Off** behaves exactly like v23.

## Where the configuration lives

Everything is stored **per Zedge account** in that account's Firebase Realtime Database (the same DB the workflow already reads):

```
dashboardSettings/vpn
  mode              "none" | "openvpn" | "wireguard"    <- what real runs use
  activeProfileId   id of the profile used by real runs
  keepProxy         true = also apply the HTTP proxy inputs inside the tunnel
  profiles/<id>     { name, type, config, username, password, ca, cert, key, tlsAuth, tlsCrypt, extra, createdAt, updatedAt }
  lastTest          result of the last "Test" (status queued|running|ok|fail, message, ipBefore, ipAfter, zedgeOk, runUrl, ...)
  lastRun           result of the VPN step of the last real run
```

The web panel and the Android app read/write the same node, so a profile saved on one is visible on the other. "Save to all 4 accounts" / "Copy to all" writes the profile into all four databases.

## Adding a VPN

1. GitHub tab -> **VPN** card -> choose the Zedge account.
2. Pick the `.ovpn` / `.conf` file (or paste it). The panel detects:
   * OpenVPN vs WireGuard,
   * whether the `.ovpn` needs a username/password (`auth-user-pass`),
   * whether it references **external files** (`ca ca.crt`, `cert`, `key`, `tls-auth ta.key`, `tls-crypt`). Upload those in the CA / Cert / Key / TLS fields - they are inlined into the config on the runner. `.ovpn` files with inline `<ca>...</ca>` blocks need nothing extra.
3. Enter username/password only if the config asks for them (certificate-only configs work without).
4. **Save profile** (or **Save & test**).
5. Click **Set active** on the profile -> `mode` switches to that profile's type and the next real run uses it.

### Switching to another VPN
Save any number of profiles and press **Set active** on the one you want. Choose Mode **Off** (+ Save mode) to go back to proxy / direct. Editing a profile (pencil) and saving overwrites it in place.

### keepProxy
Normally the whole runner exits through the tunnel and the proxy inputs are ignored. Tick **Keep HTTP proxy inside the VPN** if you want proxy -> VPN chaining.

## Testing a profile (`run_mode=vpn_test`)

**Test** (panel or app) dispatches that account's own workflow (`zedgeN.yml`, name configurable in the Connection card) with `run_mode=vpn_test` and `vpn_profile=<id>`.

The workflow understands the mode:

* the `gate` job is skipped and the `automation` job runs anyway,
* delay / Playwright / ffmpeg / identity / device info / bot.js steps are **skipped**,
* only **Create vpn.mjs -> VPN tunnel (test) -> VPN disconnect** run,
* `vpn.mjs test` records the public IP before, connects, verifies the IP **changed** and that `zedge.net` is reachable, then disconnects.

The result is written to `dashboardSettings/vpn/lastTest` (live in the VPN card, polled in the app), to the run's **step summary**, and to **Telegram** (if the bot secrets exist). Typical test time: 1-3 min (first run on a fresh Windows runner installs OpenVPN/WireGuard via chocolatey).

## Real runs

`vpn.mjs connect` runs before `Create bot.js`. If the tunnel or the IP verification fails the **step fails and the run aborts** - the runner's real IP is never used for Zedge. On success it exports `VPN_ACTIVE=1`, `VPN_TYPE`, `VPN_PROFILE_NAME`, `VPN_PUBLIC_IP`, `VPN_KEEP_PROXY` for bot.js. The tunnel is always torn down at the end.

## Panel / app connection fields

* **Repo link / path** - paste `https://github.com/owner/repo`, `owner/repo` or a `git@github.com:owner/repo.git` URL; owner and repo are filled automatically.
* **Workflow files per account** - only needed if your workflow files are not named `zedge1.yml` ... `zedge4.yml`.

## Notes

* Workflow inputs are now 12 (GitHub limit 25).
* `os` for tests is forced to `windows-latest`; real runs keep using the `os` input.
* OpenVPN runner-safety directives are appended automatically (`auth-retry none`, Azure metadata route `168.63.129.16` bypass, DNS 1.1.1.1 if none pushed, `verb 3`). Interactive/unsafe directives (`askpass`, `management`, `up`/`down` scripts ...) are stripped.
* WireGuard: a `DNS =` line is added when missing; `AllowedIPs` without `0.0.0.0/0` is reported as a warning because the IP will not change for all traffic.
* The Android code was written to match the existing project structure but was not compiled here - build once in Android Studio and fix any import the IDE flags.

## v24.1 - dedicated VPN page + per-account GitHub connection

* **VPN is now its own tab / page** (panel: `#vpn` tab next to GitHub Control; app: VPN in the bottom nav). Layout: 4 account tiles (mode + last-test status at a glance) -> profiles & mode | editor -> GitHub connection | live test.
* **Per-account GitHub connection** (`dashboardSettings/vpn/github`): each Zedge account can use the shared GitHub Control connection *or* its own repo link / owner / repo / branch / workflow file / token. Test and real runs of that account are dispatched with it. **Check repo & workflow** verifies token, repo, workflow state and that the yml on GitHub is v24 (`run_mode` input present).
* **Realtime test status**: the runner writes each stage (dispatch -> load -> connecting -> connect -> verify) to `dashboardSettings/vpn/lastTest` in *that account's* Firebase; the panel streams it live (stepper + IP before/after + zedge.net + run link), the app polls every 10 s while a test is busy.
* **Smart editor**: drop the `.ovpn` / `.conf` (extra files like `ca.crt` / `ta.key` can be dropped together). Username/password fields appear only when the config has `auth-user-pass` (or you add them manually); certificate uploads appear **only for files the config actually references** - configs with inline `<ca>`/`<cert>`/`<key>` blocks need nothing. Unsupported external directives (`pkcs12`, `crl-verify`) are flagged.

## v24.2 - VPN page follows the header account

* The VPN tab (panel) and VPN page (app) no longer have their own account selector. They always work on the **account selected in the header switcher** (Zedge 1-4) - exactly like every other tab. Profiles, mode, GitHub connection and tests are read from / written to **that account's Firebase only**; nothing is shared or mixed between accounts unless you explicitly use "Save to all 4 accounts" / "Copy to all".
* The four tiles at the top are a read-only overview (mode + last test per account); clicking one switches the header account.

## v24.3 - one GitHub connection per Zedge account (no sharing)

* Removed the "Same repo as GitHub Control / GitHub page" option. Each Zedge account has a **different GitHub account, repo and token**, so the VPN page now has one mandatory connection per account: Repo link (auto-fills owner + repo), Owner, Repository, Branch, Workflow file, Token.
* Stored only at that account's Firebase `dashboardSettings/vpn/github` (+ browser copy). There is **no fallback** to the GitHub Control tab / GitHub page connection - the Test button and the real-run dispatch of an account use only that account's own connection; if it is missing the page tells you exactly which field to fill.
* Panel + Android app both updated (`VpnScreen.kt`, `VpnRepo.effectiveGithub`).
