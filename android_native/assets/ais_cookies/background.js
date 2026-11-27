// Built-in extension of the Android built-in browser (GeckoView).
//  * Gemini session: answers "get" with ONLY the Google session cookies
//    gemini.google.com uses. They go straight to the app on this device.
//  * Image to Prompt: relays the picture overlay (content.js) <-> app.
const NAMES = new Set([
  "SID", "HSID", "SSID", "APISID", "SAPISID", "SIDCC", "NID", "AEC",
  "__Secure-1PSID", "__Secure-3PSID",
  "__Secure-1PSIDTS", "__Secure-3PSIDTS",
  "__Secure-1PSIDRTS", "__Secure-3PSIDRTS",
  "__Secure-1PSIDCC", "__Secure-3PSIDCC",
  "__Secure-1PAPISID", "__Secure-3PAPISID",
]);
const DOMAINS = new Set([".google.com", "google.com", "gemini.google.com", ".gemini.google.com"]);
let port = null;
const tabs = new Set();
const geminiTabs = new Set();
const saTabs = new Set();
let basket = { srcs: [], v: 0, pages: 0 };
let saAuto = null; // { email, password }
let saTokenSent = false;
let saClientId = "";

function emitSaToken(accessToken, refreshToken, clientId) {
  if ((!accessToken && !refreshToken) || saTokenSent) return;
  saTokenSent = true;
  if (port) {
    port.postMessage({
      type: "sa_token",
      accessToken: accessToken ? String(accessToken) : "",
      refreshToken: refreshToken ? String(refreshToken) : "",
      clientId: clientId ? String(clientId) : saClientId,
    });
  }
}

try {
  browser.webRequest.onBeforeSendHeaders.addListener(
    (details) => {
      if (saTokenSent) return;
      for (const h of details.requestHeaders || []) {
        if ((h.name || "").toLowerCase() === "authorization" && h.value && h.value.startsWith("Bearer ")) {
          const tok = h.value.slice(7).trim();
          if (tok.length > 40) {
            emitSaToken(tok, "", saClientId);
            break;
          }
        }
      }
    },
    { urls: ["https://*.stableaudio.com/*", "https://api.stableaudio.com/*", "https://sessions-api.stableaudio.com/*"] },
    ["requestHeaders"]
  );

  browser.webRequest.onBeforeRequest.addListener(
    (details) => {
      try {
        if (details.requestBody && details.requestBody.raw && details.requestBody.raw[0]) {
          const txt = new TextDecoder("utf-8").decode(details.requestBody.raw[0].bytes);
          const body = JSON.parse(txt);
          if (body && body.client_id) saClientId = String(body.client_id);
        }
      } catch (e) {}
      if (typeof browser.webRequest.filterResponseData !== "function") return;
      const filter = browser.webRequest.filterResponseData(details.requestId);
      const chunks = [];
      filter.ondata = (ev) => {
        chunks.push(ev.data);
        filter.write(ev.data);
      };
      filter.onstop = () => {
        try {
          const total = chunks.reduce((n, c) => n + c.byteLength, 0);
          const merged = new Uint8Array(total);
          let off = 0;
          for (const c of chunks) {
            merged.set(new Uint8Array(c), off);
            off += c.byteLength;
          }
          const json = JSON.parse(new TextDecoder("utf-8").decode(merged));
          const tok = json && (json.access_token || json.accessToken || json.token || json.id_token || (json.data && json.data.access_token));
          if (tok && typeof tok === "string" && tok.length > 40) {
            emitSaToken(tok, json.refresh_token || "", saClientId);
          }
        } catch (e) {}
        filter.close();
      };
    },
    { urls: ["https://api.workos.com/user_management/authenticate*"] },
    ["blocking", "requestBody"]
  );
} catch (e) {}

function toTabs(m) {
  for (const t of tabs) {
    try { t.postMessage(m); } catch (e) {}
  }
}

function toSaTabs(m) {
  for (const t of saTabs) {
    try { t.postMessage(m); } catch (e) {}
  }
}

async function cookies(msg) {
  try {
    const all = await browser.cookies.getAll({ url: "https://gemini.google.com/app" });
    const c = all.filter((x) => NAMES.has(x.name) && DOMAINS.has(x.domain));
    port && port.postMessage({ id: msg.id, cookies: c });
  } catch (e) {
    port && port.postMessage({ id: msg.id, error: String(e) });
  }
}

// Picture download for the app (fallback when the app's own download
// fails because of CORS / hot-link rules). No cookies are sent.
async function fetchPic(msg) {
  try {
    const r = await fetch(msg.src, { credentials: "omit" });
    if (!r.ok) throw new Error("HTTP " + r.status);
    const blob = await r.blob();
    if (blob.size > 25 * 1024 * 1024) throw new Error("picture too large");
    const data = await new Promise((ok, bad) => {
      const fr = new FileReader();
      fr.onload = () => ok(fr.result);
      fr.onerror = () => bad(fr.error);
      fr.readAsDataURL(blob);
    });
    port && port.postMessage({ id: msg.id, data: data });
  } catch (e) {
    port && port.postMessage({ id: msg.id, error: String(e) });
  }
}

// Gemini request relay: the app asks for a fetch, a signed-in
// gemini.google.com tab (gemini_bridge.js) runs it with the browser's
// own cookies/origin, and the answer goes back to the app under the
// same id. No tab open yet -> the app opens one and retries.
function gfetch(msg) {
  const tab = geminiTabs.values().next().value;
  if (!tab) {
    port && port.postMessage({ id: msg.id, error: "no_gemini_tab" });
    return;
  }
  try {
    tab.postMessage({
      type: "gfetch", id: msg.id,
      m: msg.m, u: msg.u, h: msg.h || {}, b: msg.b ?? null,
      f: msg.f || null, fn: msg.fn, ft: msg.ft, t: msg.t,
    });
  } catch (e) {
    port && port.postMessage({ id: msg.id, error: String(e) });
  }
}

function fromApp(msg) {
  if (!msg) return;
  switch (msg.cmd) {
    case "get": cookies(msg); break;
    case "fetch": fetchPic(msg); break;
    case "gfetch": gfetch(msg); break;
    case "basket":
      basket = { srcs: msg.srcs || [], v: msg.v || 0, pages: msg.pages || 0 };
      toTabs({ type: "basket", srcs: basket.srcs, v: basket.v, pages: basket.pages });
      break;
    case "status": toTabs({ type: "status", src: msg.src, state: msg.state, message: msg.message || "" }); break;
    case "toast": toTabs({ type: "toast", msg: msg.msg || "" }); break;
    case "sa_auto":
      saTokenSent = false;
      saAuto = msg.email ? { email: msg.email, password: msg.password || "" } : null;
      if (saAuto) toSaTabs({ type: "sa_auto", email: saAuto.email, password: saAuto.password });
      break;
    case "sa_otp":
      toSaTabs({ type: "sa_otp", otp: msg.otp || "" });
      break;
  }
}

browser.runtime.onConnect.addListener((p) => {
  if (p.name === "ais-gemini") {
    geminiTabs.add(p);
    p.onMessage.addListener((m) => {
      if (!m || m.type !== "gfetch_result" || !port) return;
      port.postMessage({
        id: m.id, s: m.s, u: m.u, b: m.b, ct: m.ct, x: m.x, e: m.e,
        error: m.e || undefined,
      });
    });
    p.onDisconnect.addListener(() => geminiTabs.delete(p));
    return;
  }
  if (p.name === "ais-sa") {
    saTabs.add(p);
    if (saAuto) p.postMessage({ type: "sa_auto", email: saAuto.email, password: saAuto.password });
    p.onMessage.addListener((m) => {
      if (!m) return;
      if (m.type === "sa_token") {
        emitSaToken(m.accessToken, m.refreshToken, m.clientId);
      } else if (m.type === "sa_need_otp" && port) {
        port.postMessage(m);
      }
    });
    p.onDisconnect.addListener(() => saTabs.delete(p));
    return;
  }
  if (p.name !== "ais-tab") return;
  tabs.add(p);
  p.postMessage({ type: "basket", srcs: basket.srcs, v: basket.v, pages: basket.pages });
  p.onMessage.addListener((m) => {
    if (m && m.type === "q" && port) port.postMessage(m);
  });
  p.onDisconnect.addListener(() => tabs.delete(p));
});

function connect() {
  try {
    port = browser.runtime.connectNative("ais");
  } catch (e) {
    port = null;
    setTimeout(connect, 1000);
    return;
  }
  port.onMessage.addListener(fromApp);
  port.onDisconnect.addListener(() => {
    port = null;
    setTimeout(connect, 1000);
  });
}

connect();
