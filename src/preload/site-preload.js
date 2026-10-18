// Runs inside every web tab (sandboxed). Injects the Wafid assistant on booking/payment pages:
//  - core.js  -> page (main) world, exactly like the extension's "MAIN" content script
//  - panel.js -> isolated world 1001, with a chrome.storage shim backed by the app store
const { ipcRenderer, contextBridge, webFrame } = require("electron");

const WORLD = 1001;
const MATCH = /^https:\/\/wafid\.com\/[a-z]{2}\/(book-appointment\/|appointment\/[^/]+\/pay\/)/i;

// Keep navigator.userAgentData consistent with a regular Chrome build (no "Electron" brand).
try {
  webFrame.executeJavaScript(`(() => {
    try {
      const uad = navigator.userAgentData; if (!uad) return;
      const major = (navigator.userAgent.match(/Chrome\\/(\\d+)/) || [])[1] || "130";
      const brands = [{ brand: "Chromium", version: major }, { brand: "Google Chrome", version: major }, { brand: "Not?A_Brand", version: "99" }];
      const proto = Object.getPrototypeOf(uad);
      const orig = proto.getHighEntropyValues;
      Object.defineProperty(proto, "brands", { get: () => brands.map(b => Object.assign({}, b)), configurable: true });
      Object.defineProperty(proto, "platform", { get: () => "Windows", configurable: true });
      proto.getHighEntropyValues = function (h) {
        return orig.call(this, h).then(v => Object.assign(v, { brands: brands.map(b => Object.assign({}, b)), platform: "Windows",
          fullVersionList: brands.map(b => ({ brand: b.brand, version: b.version + ".0.0.0" })) }));
      };
    } catch (e) {}
  })();`);
} catch (e) {}

if (MATCH.test(location.href)) {
  contextBridge.exposeInIsolatedWorld(WORLD, "__bdHost", {
    get: keys => ipcRenderer.invoke("site:store-get", keys),
    set: obj => ipcRenderer.invoke("site:store-set", obj),
    mon: info => { try { ipcRenderer.send("site:mon", JSON.parse(JSON.stringify(info))); } catch (e) {} }
  });

  const SHIM = `
    (function () {
      const wrap = (p, cb) => { p.then(v => { try { cb && cb(v); } catch (e) { console.error(e); } }); return p; };
      window.chrome = window.chrome || {};
      window.chrome.storage = { local: {
        get: (keys, cb) => { if (typeof keys === "function") { cb = keys; keys = null; } return wrap(__bdHost.get(keys), cb); },
        set: (obj, cb) => wrap(__bdHost.set(obj), cb)
      } };
      window.addEventListener("message", e => {
        if (e.source === window && e.data && e.data.__bd && e.data.type === "mon") __bdHost.mon(e.data.info);
      });
    })();`;

  let done = false;
  const inject = () => {
    if (done) return; done = true;
    const src = ipcRenderer.sendSync("site:inject-src");
    if (!src) return;
    webFrame.executeJavaScript(src.core).catch(e => console.error("[wafid-desktop] core", e));
    webFrame.executeJavaScriptInIsolatedWorld(WORLD, [{ code: SHIM }, { code: src.panel },
      { code: '(function t(){ typeof window.__bdInitPanel==="function" ? window.__bdInitPanel() : setTimeout(t,100); })();' }])
      .catch(e => console.error("[wafid-desktop] panel", e));
  };
  if (document.readyState === "loading") window.addEventListener("DOMContentLoaded", inject, { once: true });
  else inject();
}
