/* Wafid Desktop - shell UI (tabs, toolbar, settings, activity) */
const $ = id => document.getElementById(id);
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const tm = t => { const d = new Date(t); return d.toLocaleTimeString([], { hour12: false }); };

let S = { tabs: [], activeId: null, settings: {}, profiles: [], activity: [], meta: {} };
let page = null; // "settings" | "activity" | null
let editingUrl = false;

/* ---------- static icons ---------- */
$("newTab").innerHTML = icon("plus", 16);
$("bBack").innerHTML = icon("back", 18);
$("bFwd").innerHTML = icon("fwd", 18);
$("bReload").innerHTML = icon("reload", 16);
$("bHome").innerHTML = icon("home", 16);
$("bActivity").innerHTML = icon("activity", 17);
$("bSettings").innerHTML = icon("settings", 17);
document.querySelector('[data-w="min"]').innerHTML = icon("min", 14);
document.querySelector('[data-w="max"]').innerHTML = icon("max", 13);
document.querySelector('[data-w="close"]').innerHTML = icon("x", 15);

document.querySelectorAll(".winctl button").forEach(b => b.onclick = () => app.win(b.dataset.w));
$("titlebar").addEventListener("dblclick", e => { if (e.target.classList.contains("drag") || e.target.id === "titlebar") app.win("max"); });
$("newTab").onclick = () => app.newTab();
$("bBack").onclick = () => app.nav("back");
$("bFwd").onclick = () => app.nav("forward");
$("bReload").onclick = () => { const t = cur(); app.nav(t && t.loading ? "stop" : "reload"); };
$("bHome").onclick = () => { closePage(); app.nav("home"); };
$("bSettings").onclick = () => page === "settings" ? closePage() : openPage("settings");
$("bActivity").onclick = () => page === "activity" ? closePage() : openPage("activity");
$("zoomBadge").onclick = () => app.nav("zoom", { d: 0 });
$("url").addEventListener("focus", () => { editingUrl = true; setTimeout(() => $("url").select(), 0); });
$("url").addEventListener("blur", () => { editingUrl = false; renderToolbar(); });
$("addr").addEventListener("submit", e => { e.preventDefault(); closePage(); app.nav("go", { url: $("url").value }); $("url").blur(); });
document.addEventListener("keydown", e => {
  if (e.key === "Escape" && page) closePage();
  if (e.key === "Escape" && editingUrl) $("url").blur();
});

const cur = () => S.tabs.find(t => t.id === S.activeId);

/* ---------- monitor state helpers ---------- */
function monState(m) {
  if (!m) return null;
  if (m.result && m.result.status === "reached_pay") return { cls: "hit", text: `Booked: #${m.result.id} ${m.result.name}` };
  if (m.phase === "submitting") return { cls: "hit", text: `Match #${m.fired ? m.fired.id : ""} - submitting` };
  if (m.phase === "matched") return { cls: "hit", text: "Match - press Submit" };
  if (m.phase === "blocked") return { cls: "blocked", text: "Stopped: " + (m.note || "blocked") };
  if (!m.running) return null;
  const live = m.live ? `#${m.live.id} ${m.live.name}` : "-";
  if (m.lastErr) return { cls: "slow", text: `${m.dest}: slowing down (${m.lastErr.replace(/\s*\(.*\)$/, "")})` };
  return { cls: "watching", text: `${m.dest} live ${live}` };
}

/* ---------- tabs ---------- */
function renderTabs() {
  const box = $("tabs");
  const ids = S.tabs.map(t => String(t.id));
  [...box.children].forEach(el => { if (!ids.includes(el.dataset.id)) el.remove(); });
  S.tabs.forEach((t, i) => {
    let el = box.querySelector(`[data-id="${t.id}"]`);
    if (!el) {
      el = document.createElement("div");
      el.className = "tab"; el.dataset.id = t.id;
      el.innerHTML = `<span class="pcol"></span><span class="fav"></span><span class="t"></span><span class="md hide"></span><button class="x" title="Close tab (Ctrl+W)">${icon("x", 13)}</button>`;
      el.addEventListener("mousedown", e => { if (e.button === 1) { e.preventDefault(); app.closeTab(t.id); } });
      el.addEventListener("click", e => { if (e.target.closest(".x")) app.closeTab(t.id); else { closePage(); app.activate(t.id); } });
    }
    if (box.children[i] !== el) box.insertBefore(el, box.children[i] || null);
    el.classList.toggle("active", t.id === S.activeId);
    el.title = `${t.title}\n${t.url}\nProfile: ${t.profile.name}`;
    el.querySelector(".t").textContent = t.title || "New tab";
    el.querySelector(".pcol").style.background = S.profiles.length > 1 ? t.profile.color : "transparent";
    const fav = el.querySelector(".fav");
    const favHtml = t.loading ? '<span class="spin"></span>' : t.favicon ? `<img src="${esc(t.favicon)}" alt="">` : icon("globe", 14);
    if (fav.dataset.h !== favHtml) { fav.innerHTML = favHtml; fav.dataset.h = favHtml; }
    const st = monState(t.mon), md = el.querySelector(".md");
    md.className = "md" + (st ? " " + st.cls : " hide");
  });
}

/* ---------- toolbar / status ---------- */
function renderToolbar() {
  const t = cur();
  $("bBack").disabled = !t || !t.canBack;
  $("bFwd").disabled = !t || !t.canForward;
  $("bReload").innerHTML = icon(t && t.loading ? "stop" : "reload", 16);
  if (!editingUrl) $("url").value = t ? t.url : "";
  const secure = t && /^https:/.test(t.url);
  $("lock").innerHTML = icon(secure ? "lock" : "globe", 14);
  $("lock").className = secure || !t || !t.url ? "" : "insecure";
  if (t) {
    $("profileBadge").innerHTML = `<i style="background:${esc(t.profile.color)}"></i>${esc(t.profile.name)}${t.profile.proxy ? " · proxy" : ""}`;
    const z = Math.round((t.zoom || 1) * 100);
    $("zoomBadge").textContent = z + "%"; $("zoomBadge").classList.toggle("hide", z === 100);
  }
  const st = monState(t && t.mon);
  const pill = $("monPill");
  pill.className = "pill " + (st ? st.cls : "idle");
  pill.querySelector("span").textContent = st ? st.text : "Monitor idle";
  pill.title = t && t.mon ? (t.mon.note || st && st.text || "") : "Open the Live tab in the assistant panel to start the monitor";
  renderStatus();
}
function renderStatus() {
  const t = cur(), m = t && t.mon;
  const running = S.tabs.filter(x => x.mon && x.mon.running).length;
  let left = running ? `<b>${running} monitor${running > 1 ? "s" : ""} running</b>` : "No monitor running";
  if (m && m.running) {
    const next = m.nextAt ? Math.max(0, Math.round((m.nextAt - Date.now()) / 1000)) : 0;
    left += ` · this tab: ${esc(m.dest)} · ${m.polls} checks · last ${m.checkedAt ? tm(m.checkedAt) : "-"} · next in ${next}s` +
            (m.targets.length ? ` · targets ${m.targets.map(x => "#" + esc(x)).join(", ")}` : "");
  } else if (t && t.loading) left = "Loading " + esc(t.url);
  $("sbLeft").innerHTML = left;
  $("sbProxy").textContent = t ? (t.profile.proxy ? "Proxy on" : "Direct connection") : "";
}
setInterval(renderStatus, 1000);

/* ---------- pages ---------- */
function openPage(p) {
  page = p;
  app.overlay(true);
  $("page-settings").classList.toggle("hide", p !== "settings");
  $("page-activity").classList.toggle("hide", p !== "activity");
  $("bSettings").classList.toggle("on", p === "settings");
  $("bActivity").classList.toggle("on", p === "activity");
  if (p === "settings") renderSettings();
  if (p === "activity") renderActivity();
}
function closePage() {
  if (!page) return;
  page = null;
  $("page-settings").classList.add("hide"); $("page-activity").classList.add("hide");
  $("bSettings").classList.remove("on"); $("bActivity").classList.remove("on");
  app.overlay(false);
}

function toast(msg) {
  const d = document.createElement("div"); d.className = "toast"; d.textContent = msg;
  document.body.appendChild(d); setTimeout(() => d.remove(), 1800);
}

/* settings */
let setSec = "general";
const sw = (id, on) => `<label class="sw"><input type="checkbox" id="${id}" ${on ? "checked" : ""}><span></span></label>`;
const row = (title, desc, ctl) => `<div class="row"><div class="l"><b>${title}</b><small>${desc}</small></div>${ctl}</div>`;

function renderSettings() {
  const s = S.settings;
  const secs = [["general", "sliders", "General"], ["profiles", "user", "Profiles & proxy"], ["identity", "shield", "Identity & privacy"], ["about", "info", "About"]];
  let body = "";
  if (setSec === "general") body = `
    <h3>General</h3><p class="sub">Startup, notifications and window behaviour.</p>
    <div class="card">
      ${row("Home page", "Opened by new tabs and the Home button.", `<input class="txt wide" id="sHome" value="${esc(s.homeUrl)}">`)}
      ${row("Restore tabs on start", "Reopen the tabs that were open when the app was closed.", sw("sRestore", s.restoreTabs))}
      ${row("Desktop notifications", "Windows notification when a target center goes live or a booking reaches payment.", sw("sNotify", s.notify))}
      ${row("Flash taskbar on match", "Flash the taskbar button when the window is in the background.", sw("sFlash", s.flashTaskbar))}
      ${row("Keep PC awake while monitoring", "Prevents Windows from sleeping while a live monitor is running.", sw("sAwake", s.keepAwake))}
      ${row("Always on top", "Keep the window above other windows.", sw("sTop", s.alwaysOnTop))}
      ${row("Default zoom", "Zoom used for new tabs.", `<select class="txt" id="sZoom">${[0.8, 0.9, 1, 1.1, 1.25].map(z => `<option value="${z}" ${Number(s.zoom) === z ? "selected" : ""}>${Math.round(z * 100)}%</option>`).join("")}</select>`)}
    </div>
    <div class="card">
      ${row("Assistant data", "Auto Fill profiles, monitor settings and change history.", `<button class="btn danger" id="sResetPanel">${icon("trash", 14)} Reset</button>`)}
      ${row("App data folder", esc(S.meta.dataPath || ""), `<button class="btn" id="sOpenData">${icon("folder", 14)} Open</button>`)}
    </div>
    <button class="btn pri" id="sSave">${icon("check", 14)} Save</button>`;
  if (setSec === "profiles") body = `
    <h3>Profiles & proxy</h3>
    <p class="sub">Each profile is a separate browser with its own cookies, login and (optional) proxy. Use different proxies to run monitors on different IPs. Proxy formats: <code>host:port</code>, <code>user:pass@host:port</code>, <code>host:port:user:pass</code>, <code>socks5://host:port</code>.</p>
    <div class="card" id="profList">${S.profiles.map(p => `
      <div class="prof" data-id="${esc(p.id)}">
        <input type="color" value="${esc(p.color)}" class="pc">
        <input class="txt pn" value="${esc(p.name)}" placeholder="Name">
        <input class="txt pp" value="${esc(p.proxy)}" placeholder="Proxy (empty = direct)">
        <div class="acts">
          <button class="btn pt" title="Test proxy">Test</button>
          <button class="btn po" title="Open a tab with this profile">Open tab</button>
          <button class="btn pclr" title="Clear cookies and cache">Clear data</button>
          ${S.profiles.length > 1 ? `<button class="btn danger pd" title="Delete profile">${icon("trash", 14)}</button>` : ""}
        </div>
      </div><div class="msg" data-msg="${esc(p.id)}"></div>`).join("")}
    </div>
    <div style="display:flex;gap:8px"><button class="btn" id="pAdd">${icon("plus", 14)} Add profile</button><button class="btn pri" id="pSave">${icon("check", 14)} Save profiles</button></div>`;
  if (setSec === "identity") body = `
    <h3>Identity & privacy</h3>
    <p class="sub">The app presents itself as a normal Google Chrome on Windows. These options keep that identity consistent.</p>
    <div class="card">
      ${row("User agent", "Auto = the same Chrome version the app is built on (recommended).", `<select class="txt" id="sUaMode"><option value="auto" ${s.uaMode !== "custom" ? "selected" : ""}>Auto (Chrome ${esc((S.meta.chrome || "").split(".")[0])})</option><option value="custom" ${s.uaMode === "custom" ? "selected" : ""}>Custom</option></select>`)}
      <div class="row ${s.uaMode === "custom" ? "" : "hide"}" id="uaRow"><div class="l"><b>Custom user agent</b><small>Must look like a real Chrome on Windows.</small></div><input class="txt wide" id="sUa" value="${esc(s.customUA)}"></div>
      ${row("Accept-Language", "Language header sent to websites.", `<input class="txt" id="sLang" value="${esc(s.acceptLanguage)}">`)}
      ${row("WebRTC leak protection", "Stops WebRTC from revealing your real IP when a proxy is used.", sw("sRtc", s.webrtcProtect))}
      ${row("Block trackers", "Blocks analytics/tracking scripts (Google Tag Manager, APM and similar). Pages load faster.", sw("sTrk", s.blockTrackers))}
    </div>
    <div class="card"><div class="kv"><span>Current user agent</span><b>${esc(S.meta.ua)}</b></div></div>
    <button class="btn pri" id="sSave">${icon("check", 14)} Save</button>`;
  if (setSec === "about") body = `
    <h3>About</h3><p class="sub">Wafid Desktop: a browser for wafid.com with the assistant built in.</p>
    <div class="card"><div class="kv">
      <span>Version</span><b>${esc(S.meta.version)}</b>
      <span>Chromium</span><b>${esc(S.meta.chrome)}</b>
      <span>Electron</span><b>${esc(S.meta.electron)}</b>
      <span>Shortcuts</span><b>Ctrl+T new tab · Ctrl+W close · Ctrl+Tab switch · F5 reload · Ctrl+L address · Ctrl +/- zoom · F12 dev tools</b>
    </div></div>`;
  $("page-settings").innerHTML = `<div class="set"><aside><h2>Settings</h2>${secs.map(([k, ic, l]) => `<button data-s="${k}" class="${k === setSec ? "on" : ""}">${icon(ic, 16)}${l}</button>`).join("")}</aside><div class="body">${body}</div></div>`;
  bindSettings();
}

function bindSettings() {
  const P = $("page-settings");
  P.querySelectorAll("aside button").forEach(b => b.onclick = () => { setSec = b.dataset.s; renderSettings(); });
  const v = id => P.querySelector("#" + id);
  if (v("sUaMode")) v("sUaMode").onchange = () => v("uaRow").classList.toggle("hide", v("sUaMode").value !== "custom");
  if (v("sResetPanel")) v("sResetPanel").onclick = async () => { if (confirm("Delete all Auto Fill profiles, monitor settings and change history?")) { await app.resetPanel(); toast("Assistant data reset - reload the page"); } };
  if (v("sOpenData")) v("sOpenData").onclick = () => app.openData();
  if (v("sSave")) v("sSave").onclick = async () => {
    const s = {};
    if (v("sHome")) Object.assign(s, { homeUrl: v("sHome").value.trim() || "https://wafid.com/en/book-appointment/", restoreTabs: v("sRestore").checked,
      notify: v("sNotify").checked, flashTaskbar: v("sFlash").checked, keepAwake: v("sAwake").checked, alwaysOnTop: v("sTop").checked, zoom: Number(v("sZoom").value) });
    if (v("sUaMode")) Object.assign(s, { uaMode: v("sUaMode").value, customUA: v("sUa").value.trim(), acceptLanguage: v("sLang").value.trim() || "en-US,en;q=0.9",
      webrtcProtect: v("sRtc").checked, blockTrackers: v("sTrk").checked });
    const r = await app.saveSettings(s);
    S.settings = r.settings; S.meta.ua = r.ua; renderSettings(); toast("Settings saved");
  };
  const readProfiles = () => [...P.querySelectorAll(".prof")].map(el => ({ id: el.dataset.id, name: el.querySelector(".pn").value.trim() || "Profile",
    color: el.querySelector(".pc").value, proxy: el.querySelector(".pp").value.trim() }));
  if (v("pAdd")) v("pAdd").onclick = () => {
    S.profiles = readProfiles();
    const colors = ["#22c55e", "#f59e0b", "#a855f7", "#ef4444", "#14b8a6", "#ec4899"];
    S.profiles.push({ id: "p" + Date.now().toString(36), name: "Profile " + (S.profiles.length + 1), color: colors[S.profiles.length % colors.length], proxy: "" });
    renderSettings();
  };
  if (v("pSave")) v("pSave").onclick = async () => { S.profiles = await app.saveProfiles(readProfiles()); renderSettings(); toast("Profiles saved"); };
  P.querySelectorAll(".prof").forEach(el => {
    const id = el.dataset.id, msg = P.querySelector(`[data-msg="${id}"]`);
    el.querySelector(".pt").onclick = async () => {
      msg.className = "msg"; msg.textContent = "Testing connection to wafid.com…";
      const r = await app.testProxy(el.querySelector(".pp").value);
      msg.className = "msg " + (r.ok ? "ok" : "bad"); msg.textContent = (r.ok ? "Working: " : "Failed: ") + r.msg;
    };
    el.querySelector(".po").onclick = async () => { S.profiles = await app.saveProfiles(readProfiles()); closePage(); app.newTab({ profileId: id }); };
    el.querySelector(".pclr").onclick = async () => { if (confirm("Clear cookies, login and cache of this profile?")) { await app.clearProfile(id); msg.className = "msg ok"; msg.textContent = "Cleared. Reload the open tabs of this profile."; } };
    const d = el.querySelector(".pd");
    if (d) d.onclick = () => { if (confirm("Delete this profile?")) { S.profiles = readProfiles().filter(p => p.id !== id); renderSettings(); } };
  });
}

/* activity */
function renderActivity() {
  const list = S.activity || [];
  $("page-activity").innerHTML = `<div class="act"><h3>Activity</h3><p class="sub">Monitor events from all tabs: center changes, matches, warnings. Newest first.</p>
    <div class="card" style="max-width:none">${list.length ? list.map(a => `<div class="ev"><time>${tm(a.at)}</time><span class="k ${esc(a.kind)}">${esc(a.kind)}</span><span>${esc(a.text)} <span style="color:var(--dim)">· tab ${a.tab} · ${esc(a.profile)}</span></span></div>`).join("") : `<div class="empty">No activity yet. Start the Live monitor from the assistant panel on the booking page.</div>`}</div></div>`;
}

/* ---------- wiring ---------- */
app.on("tabs", d => { S.tabs = d.tabs; S.activeId = d.activeId; renderTabs(); renderToolbar(); });
app.on("activity", a => { S.activity = a; if (page === "activity") renderActivity(); });
app.on("maximized", m => { document.querySelector('[data-w="max"]').innerHTML = icon(m ? "restore" : "max", 13); });
app.on("focus-address", () => { $("url").focus(); });

app.init().then(d => {
  S.settings = d.settings; S.profiles = d.profiles; S.activity = d.activity || [];
  S.meta = { version: d.version, chrome: d.chrome, electron: d.electron, ua: d.ua, dataPath: d.dataPath };
  $("sbVer").textContent = "v" + d.version;
});
