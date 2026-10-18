// Wafid Desktop - main process
const { app, BrowserWindow, WebContentsView, ipcMain, session, Menu, shell, Notification,
        powerSaveBlocker, nativeTheme, dialog, clipboard } = require("electron");
const path = require("path");
const fs = require("fs");
const Store = require("./store");

const TOP = 84;      // tab strip (40) + toolbar (44) in the shell UI
const BOTTOM = 26;   // status bar
const HOME = "https://wafid.com/en/book-appointment/";
const SITE_RE = /^https:\/\/([a-z0-9-]+\.)*wafid\.com\//i;

if (!app.requestSingleInstanceLock()) { app.quit(); process.exit(0); }
app.setAppUserModelId("com.shawonarts.wafiddesktop");
nativeTheme.themeSource = "dark";

let win = null;
let store = null;
const tabs = new Map();       // id -> { id, view, profileId, mon, title, url, loading, favicon }
let activeId = null;
let nextTabId = 1;
let overlay = false;          // settings / activity page covers the web view
let keepAwakeId = null;
const activity = [];          // recent monitor events (all tabs)

const DEFAULTS = {
  settings: {
    homeUrl: HOME,
    restoreTabs: true,
    keepAwake: true,
    notify: true,
    flashTaskbar: true,
    alwaysOnTop: false,
    uaMode: "auto",            // auto | custom
    customUA: "",
    acceptLanguage: "en-US,en;q=0.9",
    webrtcProtect: true,
    blockTrackers: true,
    zoom: 1
  },
  profiles: [{ id: "p1", name: "Main", color: "#3b82f6", proxy: "" }],
  lastTabs: [],
  panel: {},                   // in-page assistant storage (profiles, monitor config...)
  winBounds: null
};

/* ------------------------------------------------------------ identity */
function chromeUA() {
  const s = store.get("settings");
  if (s.uaMode === "custom" && s.customUA.trim()) return s.customUA.trim();
  const major = (process.versions.chrome || "130").split(".")[0];
  return `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${major}.0.0.0 Safari/537.36`;
}

const TRACKERS = ["googletagmanager.com", "google-analytics.com", "doubleclick.net", "facebook.net", "hotjar.com", "clarity.ms", "elastic-apm-rum"];
const configured = new Set();

function parseProxy(str) {
  // accepts: host:port | http://host:port | socks5://host:port | user:pass@host:port | scheme://user:pass@host:port
  str = (str || "").trim();
  if (!str) return null;
  let scheme = "http";
  const m = str.match(/^(https?|socks4|socks5):\/\/(.*)$/i);
  if (m) { scheme = m[1].toLowerCase(); str = m[2]; }
  let user = "", pass = "";
  const at = str.lastIndexOf("@");
  if (at > 0) { const cred = str.slice(0, at); str = str.slice(at + 1); const i = cred.indexOf(":"); user = i < 0 ? cred : cred.slice(0, i); pass = i < 0 ? "" : cred.slice(i + 1); }
  const parts = str.split(":");
  if (parts.length === 4 && !user) { user = parts[2]; pass = parts[3]; str = parts[0] + ":" + parts[1]; }
  if (!/^[^:\s]+:\d+$/.test(str)) return null;
  return { scheme, hostport: str, user, pass, rules: `${scheme}://${str}` };
}

function profileById(id) { return store.get("profiles").find(p => p.id === id) || store.get("profiles")[0]; }

async function setupSession(profile) {
  const ses = session.fromPartition("persist:" + profile.id);
  const s = store.get("settings");
  ses.setUserAgent(chromeUA(), s.acceptLanguage || "en-US,en;q=0.9");
  const px = parseProxy(profile.proxy);
  await ses.setProxy(px ? { proxyRules: px.rules, proxyBypassRules: "<local>" } : { mode: "direct" });
  await ses.closeAllConnections?.().catch(() => {});
  if (!configured.has(profile.id)) {
    configured.add(profile.id);
    ses.setPermissionRequestHandler((wc, perm, cb) => cb(["clipboard-sanitized-write", "fullscreen"].includes(perm)));
    ses.webRequest.onBeforeRequest({ urls: ["*://*/*"] }, (d, cb) => {
      const st = store.get("settings");
      cb({ cancel: !!st.blockTrackers && TRACKERS.some(t => d.url.includes(t)) });
    });
    ses.webRequest.onBeforeSendHeaders({ urls: ["*://*/*"] }, (d, cb) => {
      const h = d.requestHeaders;
      // keep client hints consistent with a regular Chrome on Windows
      const major = (process.versions.chrome || "130").split(".")[0];
      if (h["sec-ch-ua"] || h["Sec-CH-UA"]) {
        delete h["sec-ch-ua"];
        h["Sec-CH-UA"] = `"Chromium";v="${major}", "Google Chrome";v="${major}", "Not?A_Brand";v="99"`;
      }
      if (h["Sec-CH-UA-Platform"] || h["sec-ch-ua-platform"]) { delete h["sec-ch-ua-platform"]; h["Sec-CH-UA-Platform"] = '"Windows"'; }
      cb({ requestHeaders: h });
    });
    ses.on("will-download", (e, item) => {
      item.once("done", (ev, state) => { if (state === "completed") notify("Download complete", path.basename(item.getSavePath())); });
    });
  }
  return ses;
}

/* ------------------------------------------------------------ inject sources */
const INJECT = {};
function loadInject() {
  const dir = path.join(__dirname, "..", "inject");
  INJECT.core = fs.readFileSync(path.join(dir, "core.js"), "utf8");
  INJECT.panel = fs.readFileSync(path.join(dir, "panel.js"), "utf8");
}

/* ------------------------------------------------------------ tabs */
function shellSend(ch, data) { if (win && !win.isDestroyed()) win.webContents.send(ch, data); }

function tabInfo(t) {
  const wc = t.view.webContents;
  const p = profileById(t.profileId);
  return {
    id: t.id, title: t.title || "New tab", url: t.url || "", loading: t.loading, favicon: t.favicon || "",
    canBack: wc.navigationHistory ? wc.navigationHistory.canGoBack() : wc.canGoBack(),
    canForward: wc.navigationHistory ? wc.navigationHistory.canGoForward() : wc.canGoForward(),
    profile: { id: p.id, name: p.name, color: p.color, proxy: !!parseProxy(p.proxy) },
    mon: t.mon ? summarizeMon(t.mon) : null,
    zoom: wc.getZoomFactor()
  };
}
function summarizeMon(m) {
  const dest = m.cfg && m.cfg.dest;
  const live = dest && m.live ? m.live[dest] : null;
  return { running: !!m.running, phase: m.phase, note: m.note || "", dest: dest || "", live, polls: m.polls || 0,
           errors: m.errors || 0, lastErr: m.lastErr || "", checkedAt: m.checkedAt || 0, nextAt: m.nextAt || 0,
           targets: (m.cfg && m.cfg.targets) || [], fired: m.fired || null, result: m.result || null };
}
let pushTimer = null;
function pushTabs() {
  clearTimeout(pushTimer);
  pushTimer = setTimeout(() => {
    shellSend("tabs", { tabs: [...tabs.values()].map(tabInfo), activeId });
    saveTabs();
  }, 40);
}
function saveTabs() {
  store.set("lastTabs", [...tabs.values()].map(t => ({ url: t.url, profileId: t.profileId, active: t.id === activeId })));
}

function layout() {
  if (!win) return;
  const [w, h] = win.getContentSize();
  for (const t of tabs.values()) {
    const show = t.id === activeId && !overlay;
    t.view.setVisible(show);
    if (show) t.view.setBounds({ x: 0, y: TOP, width: w, height: Math.max(0, h - TOP - BOTTOM) });
  }
}

async function createTab(url, profileId, activate = true) {
  const profile = profileById(profileId);
  const ses = await setupSession(profile);
  const view = new WebContentsView({
    webPreferences: {
      session: ses,
      preload: path.join(__dirname, "..", "preload", "site-preload.js"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      backgroundThrottling: false,   // monitor keeps running when tab / window is in background
      spellcheck: false
    }
  });
  view.setBackgroundColor("#ffffff");
  const id = nextTabId++;
  const t = { id, view, profileId: profile.id, mon: null, title: "Loading…", url: url || "", loading: true, favicon: "" };
  tabs.set(id, t);
  win.contentView.addChildView(view);
  const wc = view.webContents;
  const s = store.get("settings");
  if (s.webrtcProtect) wc.setWebRTCIPHandlingPolicy("disable_non_proxied_udp");

  wc.on("page-title-updated", (e, title) => { t.title = title; pushTabs(); });
  wc.on("page-favicon-updated", (e, f) => { t.favicon = f[0] || ""; pushTabs(); });
  wc.on("did-start-loading", () => { t.loading = true; pushTabs(); });
  wc.on("did-stop-loading", () => { t.loading = false; t.url = wc.getURL(); pushTabs(); });
  wc.on("did-navigate", (e, u) => { t.url = u; if (!SITE_RE.test(u)) t.mon = null; pushTabs(); });
  wc.on("did-navigate-in-page", (e, u) => { t.url = u; pushTabs(); });
  wc.on("did-fail-load", (e, code, desc, u, isMain) => {
    if (!isMain || code === -3) return;
    wc.loadURL("data:text/html;charset=utf-8," + encodeURIComponent(errorPage(desc, u)));
  });
  wc.on("render-process-gone", (e, d) => { notify("Tab crashed", d.reason + " - reloading"); setTimeout(() => wc.reload(), 1000); });
  wc.setWindowOpenHandler(({ url: u }) => { createTab(u, t.profileId, true); return { action: "deny" }; });
  wc.on("context-menu", (e, p) => contextMenu(t, p));
  wc.on("before-input-event", (e, i) => { if (handleKey(i)) e.preventDefault(); });
  wc.setZoomFactor(s.zoom || 1);

  if (activate) activate_(id);
  layout();
  pushTabs();
  wc.loadURL(url || s.homeUrl || HOME).catch(() => {});
  return id;
}

function activate_(id) {
  if (!tabs.has(id)) return;
  activeId = id;
  layout();
  pushTabs();
}

function closeTab(id) {
  const t = tabs.get(id);
  if (!t) return;
  if (t.mon && t.mon.running) {
    const r = dialog.showMessageBoxSync(win, { type: "warning", buttons: ["Close tab", "Cancel"], defaultId: 1, cancelId: 1,
      title: "Monitor running", message: "Live monitor is running in this tab.", detail: "Closing the tab will stop it." });
    if (r !== 0) return;
  }
  win.contentView.removeChildView(t.view);
  t.view.webContents.close();
  tabs.delete(id);
  if (activeId === id) {
    const rest = [...tabs.keys()];
    activeId = rest.length ? rest[rest.length - 1] : null;
  }
  if (!tabs.size) createTab(null, store.get("profiles")[0].id);
  updateKeepAwake();
  layout();
  pushTabs();
}

function active() { return tabs.get(activeId); }

function errorPage(desc, u) {
  return `<!doctype html><html><body style="font:14px Segoe UI,Arial;background:#0f172a;color:#e2e8f0;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
  <div style="max-width:520px"><h2 style="margin:0 0 8px">This page could not load</h2>
  <p style="color:#94a3b8">${String(desc).replace(/</g, "&lt;")}</p><p style="color:#64748b;word-break:break-all">${String(u).replace(/</g, "&lt;")}</p>
  <p style="color:#94a3b8">Check the internet connection or the proxy of this profile, then press Reload (F5).</p></div></body></html>`;
}

/* ------------------------------------------------------------ input / menus */
function handleKey(i) {
  if (i.type !== "keyDown") return false;
  const c = i.control || i.meta, k = (i.key || "").toLowerCase();
  const t = active();
  if (c && k === "t") { createTab(null, t ? t.profileId : undefined); return true; }
  if (c && k === "w") { if (t) closeTab(t.id); return true; }
  if ((c && k === "r") || k === "f5") { if (t) (i.shift ? t.view.webContents.reloadIgnoringCache() : t.view.webContents.reload()); return true; }
  if (c && k === "l") { shellSend("focus-address"); win.webContents.focus(); return true; }
  if (i.alt && k === "arrowleft") { navBack(); return true; }
  if (i.alt && k === "arrowright") { navForward(); return true; }
  if (k === "f12") { if (t) t.view.webContents.toggleDevTools(); return true; }
  if (c && k === "tab") {
    const ids = [...tabs.keys()]; const ix = ids.indexOf(activeId);
    activate_(ids[(ix + (i.shift ? -1 : 1) + ids.length) % ids.length]); return true;
  }
  if (c && (k === "=" || k === "+")) { zoom(0.1); return true; }
  if (c && k === "-") { zoom(-0.1); return true; }
  if (c && k === "0") { zoom(0); return true; }
  return false;
}
function zoom(d) {
  const t = active(); if (!t) return;
  const wc = t.view.webContents;
  const z = d === 0 ? 1 : Math.min(2, Math.max(0.5, Math.round((wc.getZoomFactor() + d) * 10) / 10));
  wc.setZoomFactor(z); pushTabs();
}
function navBack() { const t = active(); if (!t) return; const wc = t.view.webContents; (wc.navigationHistory || wc).canGoBack() && (wc.navigationHistory ? wc.navigationHistory.goBack() : wc.goBack()); }
function navForward() { const t = active(); if (!t) return; const wc = t.view.webContents; (wc.navigationHistory || wc).canGoForward() && (wc.navigationHistory ? wc.navigationHistory.goForward() : wc.goForward()); }

function contextMenu(t, p) {
  const wc = t.view.webContents;
  const tpl = [];
  if (p.linkURL) tpl.push({ label: "Open link in new tab", click: () => createTab(p.linkURL, t.profileId) },
                         { label: "Copy link", click: () => clipboard.writeText(p.linkURL) }, { type: "separator" });
  if (p.isEditable) tpl.push({ role: "cut" }, { role: "copy" }, { role: "paste" }, { role: "selectAll" }, { type: "separator" });
  else if (p.selectionText) tpl.push({ role: "copy" }, { type: "separator" });
  tpl.push({ label: "Back", enabled: (wc.navigationHistory || wc).canGoBack(), click: navBack },
           { label: "Forward", enabled: (wc.navigationHistory || wc).canGoForward(), click: navForward },
           { label: "Reload", click: () => wc.reload() }, { type: "separator" },
           { label: "Inspect", click: () => wc.inspectElement(p.x, p.y) });
  Menu.buildFromTemplate(tpl).popup({ window: win });
}

/* ------------------------------------------------------------ monitor events */
function notify(title, body, urgent) {
  const s = store.get("settings");
  if (s.notify && Notification.isSupported()) {
    const n = new Notification({ title, body, icon: path.join(__dirname, "..", "renderer", "logo.png"), urgency: urgent ? "critical" : "normal" });
    n.on("click", () => { if (win) { if (win.isMinimized()) win.restore(); win.show(); win.focus(); } });
    n.show();
  }
  if (urgent && s.flashTaskbar && win && !win.isFocused()) win.flashFrame(true);
}

function logActivity(tab, kind, text) {
  activity.unshift({ at: Date.now(), tab: tab.id, profile: profileById(tab.profileId).name, kind, text });
  if (activity.length > 300) activity.length = 300;
  shellSend("activity", activity);
}

function onMon(tab, info) {
  const prev = tab.mon;
  tab.mon = info;
  const dest = info.cfg && info.cfg.dest;
  const p = prev || {};
  if (info.running && !p.running) logActivity(tab, "start", `Monitor started: ${dest}, targets ${(info.cfg.targets || []).map(x => "#" + x).join(", ")}`);
  if (!info.running && p.running && info.phase === "idle" && p.phase === "watching") logActivity(tab, "stop", "Monitor stopped");
  // live center changes
  if (prev && prev.live && info.live) {
    for (const k of Object.keys(info.live)) {
      const a = prev.live[k], b = info.live[k];
      if (b && (!a || String(a.id) !== String(b.id))) logActivity(tab, "change", `${k}: ${a ? "#" + a.id + " " + a.name : "-"} -> #${b.id} ${b.name}`);
    }
  }
  if (info.phase !== p.phase) {
    const c = info.fired || {};
    if (info.phase === "submitting") { notify("Target center is live", `#${c.id} ${c.name} (${c.dest}) - submitting now`, true); logActivity(tab, "match", `MATCH #${c.id} ${c.name} - submitting`); }
    if (info.phase === "matched") { notify("Target center is live", `#${c.id} ${c.name} - press Submit now`, true); logActivity(tab, "match", `MATCH #${c.id} ${c.name} - auto submit off`); }
    if (info.phase === "blocked") { notify("Monitor stopped", info.note || "Blocked", true); logActivity(tab, "error", info.note || "Blocked"); }
  }
  if (info.lastErr && info.lastErr !== p.lastErr) logActivity(tab, "warn", info.lastErr);
  const r = info.result;
  if (r && r.status === "reached_pay" && !(p.result && p.result.status === "reached_pay")) {
    notify("Booked - payment page", `#${r.id} ${r.name} (${r.dest})`, true); logActivity(tab, "match", `Reached payment page for #${r.id} ${r.name}`);
  }
  updateKeepAwake();
  pushTabs();
}

function updateKeepAwake() {
  const want = store.get("settings").keepAwake && [...tabs.values()].some(t => t.mon && t.mon.running);
  if (want && keepAwakeId === null) keepAwakeId = powerSaveBlocker.start("prevent-app-suspension");
  if (!want && keepAwakeId !== null) { powerSaveBlocker.stop(keepAwakeId); keepAwakeId = null; }
}

function tabFromSender(e) { for (const t of tabs.values()) if (t.view.webContents.id === e.sender.id) return t; return null; }

/* ------------------------------------------------------------ IPC */
function ipc() {
  // site preload
  ipcMain.on("site:inject-src", e => {
    const t = tabFromSender(e);
    e.returnValue = t ? { core: INJECT.core, panel: INJECT.panel } : null;
  });
  ipcMain.handle("site:store-get", (e, keys) => {
    const all = store.get("panel") || {};
    if (keys == null) return all;
    const list = Array.isArray(keys) ? keys : typeof keys === "string" ? [keys] : Object.keys(keys);
    const out = {};
    for (const k of list) if (k in all) out[k] = all[k]; else if (keys && typeof keys === "object" && !Array.isArray(keys)) out[k] = keys[k];
    return out;
  });
  ipcMain.handle("site:store-set", (e, obj) => { store.set("panel", Object.assign({}, store.get("panel"), obj || {})); return true; });
  ipcMain.on("site:mon", (e, info) => { const t = tabFromSender(e); if (t && info) onMon(t, info); });

  // shell
  ipcMain.handle("shell:init", () => ({ settings: store.get("settings"), profiles: store.get("profiles"),
    version: app.getVersion(), chrome: process.versions.chrome, electron: process.versions.electron, ua: chromeUA(), activity,
    dataPath: app.getPath("userData") }));
  ipcMain.on("tab:new", (e, a = {}) => createTab(a.url || null, a.profileId || (active() && active().profileId)));
  ipcMain.on("tab:close", (e, id) => closeTab(id));
  ipcMain.on("tab:activate", (e, id) => activate_(id));
  ipcMain.on("nav", (e, a) => {
    const t = active(); if (!t) return;
    const wc = t.view.webContents;
    if (a.cmd === "back") navBack();
    else if (a.cmd === "forward") navForward();
    else if (a.cmd === "reload") wc.reload();
    else if (a.cmd === "stop") wc.stop();
    else if (a.cmd === "home") wc.loadURL(store.get("settings").homeUrl || HOME);
    else if (a.cmd === "devtools") wc.toggleDevTools();
    else if (a.cmd === "zoom") zoom(a.d);
    else if (a.cmd === "go") {
      let u = String(a.url || "").trim();
      if (!u) return;
      if (!/^[a-z]+:\/\//i.test(u)) u = /\s/.test(u) || !/\./.test(u) ? "https://www.google.com/search?q=" + encodeURIComponent(u) : "https://" + u;
      wc.loadURL(u).catch(() => {});
    }
  });
  ipcMain.on("win", (e, cmd) => {
    if (cmd === "min") win.minimize();
    else if (cmd === "max") win.isMaximized() ? win.unmaximize() : win.maximize();
    else if (cmd === "close") win.close();
  });
  ipcMain.on("overlay", (e, on) => { overlay = !!on; layout(); });
  ipcMain.handle("settings:save", async (e, s) => {
    store.set("settings", Object.assign({}, store.get("settings"), s));
    win.setAlwaysOnTop(!!store.get("settings").alwaysOnTop);
    for (const p of store.get("profiles")) await setupSession(p);
    for (const t of tabs.values()) {
      t.view.webContents.setWebRTCIPHandlingPolicy(store.get("settings").webrtcProtect ? "disable_non_proxied_udp" : "default");
    }
    return { settings: store.get("settings"), ua: chromeUA() };
  });
  ipcMain.handle("profiles:save", async (e, list) => {
    if (!Array.isArray(list) || !list.length) return store.get("profiles");
    const clean = list.map(p => ({ id: String(p.id || "p" + Date.now()).replace(/[^\w-]/g, ""), name: String(p.name || "Profile").slice(0, 40),
      color: /^#[0-9a-f]{6}$/i.test(p.color) ? p.color : "#3b82f6", proxy: String(p.proxy || "").trim() }));
    store.set("profiles", clean);
    for (const p of clean) await setupSession(p);
    // tabs whose profile was removed move to the first profile
    for (const t of tabs.values()) if (!clean.find(p => p.id === t.profileId)) t.profileId = clean[0].id;
    pushTabs();
    return clean;
  });
  ipcMain.handle("profiles:test-proxy", async (e, proxy) => {
    const px = parseProxy(proxy);
    if (!proxy.trim()) return { ok: true, msg: "No proxy (direct connection)" };
    if (!px) return { ok: false, msg: "Format not recognised. Use host:port, user:pass@host:port or socks5://host:port" };
    const ses = session.fromPartition("proxytest-" + Date.now());
    await ses.setProxy({ proxyRules: px.rules });
    const started = Date.now();
    try {
      const r = await Promise.race([ses.fetch("https://wafid.com/en/", { method: "HEAD" }), new Promise((_, j) => setTimeout(() => j(new Error("timeout")), 15000))]);
      return { ok: r.status < 500, msg: `HTTP ${r.status} in ${Date.now() - started} ms` };
    } catch (err) { return { ok: false, msg: String(err.message || err) }; }
  });
  ipcMain.handle("profiles:clear", async (e, id) => {
    const ses = session.fromPartition("persist:" + id);
    await ses.clearStorageData(); await ses.clearCache();
    return true;
  });
  ipcMain.handle("panel:reset", () => { store.set("panel", {}); return true; });
  ipcMain.on("open-data-folder", () => shell.openPath(app.getPath("userData")));
}

/* proxy authentication */
app.on("login", (event, wc, details, authInfo, cb) => {
  if (!authInfo.isProxy) return;
  let t = null; for (const x of tabs.values()) if (wc && x.view.webContents.id === wc.id) t = x;
  const p = t ? profileById(t.profileId) : null;
  const px = p && parseProxy(p.proxy);
  if (px && px.user) { event.preventDefault(); cb(px.user, px.pass); }
});

/* ------------------------------------------------------------ window */
function createWindow() {
  const b = store.get("winBounds") || { width: 1360, height: 860 };
  win = new BrowserWindow({
    width: b.width, height: b.height, x: b.x, y: b.y, minWidth: 900, minHeight: 600,
    frame: false, backgroundColor: "#0b1220", show: false, title: "Wafid Desktop",
    icon: path.join(__dirname, "..", "renderer", "logo.png"),
    webPreferences: { preload: path.join(__dirname, "..", "preload", "shell-preload.js"), contextIsolation: true, sandbox: true }
  });
  if (b.maximized) win.maximize();
  win.setAlwaysOnTop(!!store.get("settings").alwaysOnTop);
  win.loadFile(path.join(__dirname, "..", "renderer", "index.html"));
  win.once("ready-to-show", () => win.show());
  win.on("resize", layout);
  win.on("maximize", () => { layout(); shellSend("maximized", true); });
  win.on("unmaximize", () => { layout(); shellSend("maximized", false); });
  win.on("focus", () => win.flashFrame(false));
  win.webContents.on("before-input-event", (e, i) => { if (handleKey(i)) e.preventDefault(); });
  win.on("close", e => {
    const running = [...tabs.values()].filter(t => t.mon && t.mon.running).length;
    if (running) {
      const r = dialog.showMessageBoxSync(win, { type: "warning", buttons: ["Exit", "Cancel"], defaultId: 1, cancelId: 1,
        title: "Monitor running", message: `${running} live monitor(s) running.`, detail: "Exiting will stop them." });
      if (r !== 0) { e.preventDefault(); return; }
    }
    store.set("winBounds", Object.assign(win.getNormalBounds(), { maximized: win.isMaximized() }));
    saveTabs();
    store.flush();
  });
  win.on("closed", () => { win = null; });

  win.webContents.once("did-finish-load", async () => {
    const s = store.get("settings");
    const last = (store.get("lastTabs") || []).filter(x => x.url && /^https?:/.test(x.url));
    if (s.restoreTabs && last.length) {
      let act = null;
      for (const x of last) { const id = await createTab(x.url, x.profileId, false); if (x.active) act = id; }
      activate_(act || [...tabs.keys()][0]);
    } else {
      await createTab(null, store.get("profiles")[0].id);
    }
  });
}

app.on("second-instance", () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
app.whenReady().then(() => {
  store = new Store(app.getPath("userData"), DEFAULTS);
  Menu.setApplicationMenu(null);
  loadInject();
  ipc();
  createWindow();
});
app.on("window-all-closed", () => { store && store.flush(); app.quit(); });
