// Gemini page bridge of the Android built-in browser (GeckoView).
// Runs as a content script on gemini.google.com pages only.
//
// Why this exists: on Android the app used to copy the Google cookies
// out of the built-in browser and replay them with plain HTTP requests.
// Google increasingly refuses copied cookies outside the browser that
// signed in (the /app page then comes back without the SNlM0e auth
// token), so every Gemini feature failed with "not signed in" even
// though the profile WAS signed in. Windows never hit this because it
// can fall back to running the request inside real Chrome, and the
// Gemini HD Studio extension never hits it because it fetches from
// inside Chrome itself (credentials: "include").
//
// This script is the Android twin of that: the app asks (through
// background.js) and the fetch runs HERE, inside the signed-in Gemini
// tab, with the browser's own cookies, origin and TLS - nothing is
// copied out.
(() => {
  if (window.top !== window.self) return;
  let port = null;

  function b64(bytes) {
    let bin = "";
    for (let i = 0; i < bytes.length; i += 32768) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
    }
    return btoa(bin);
  }

  async function gfetch(m) {
    const init = { method: m.m || "GET", headers: m.h || {}, credentials: "include" };
    if (m.f) {
      const bin = atob(m.f);
      const u8 = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      const fd = new FormData();
      fd.append("file", new Blob([u8], { type: m.ft || "image/jpeg" }), m.fn || "image.jpg");
      init.body = fd;
    } else if (m.b !== null && m.b !== undefined) {
      init.body = m.b;
    }
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), m.t || 120000);
    init.signal = ctl.signal;
    try {
      const r = await fetch(m.u, init);
      const ct = r.headers.get("content-type") || "";
      if (ct.startsWith("image/")) {
        const buf = new Uint8Array(await r.arrayBuffer());
        return { s: r.status, u: r.url, b: "", ct: ct, x: b64(buf) };
      }
      return { s: r.status, u: r.url, b: await r.text(), ct: ct };
    } catch (e) {
      return { s: 0, u: m.u, b: "", e: String(e) };
    } finally {
      clearTimeout(timer);
    }
  }

  function connect() {
    try {
      port = browser.runtime.connect({ name: "ais-gemini" });
    } catch (e) {
      port = null;
      setTimeout(connect, 1000);
      return;
    }
    port.onMessage.addListener(async (m) => {
      if (!m || m.type !== "gfetch") return;
      const r = await gfetch(m);
      r.type = "gfetch_result";
      r.id = m.id;
      try { port.postMessage(r); } catch (e) {}
    });
    port.onDisconnect.addListener(() => { port = null; setTimeout(connect, 1000); });
  }
  connect();
})();
