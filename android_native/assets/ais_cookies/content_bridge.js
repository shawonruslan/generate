// Appended after the shared overlay (lib/browser/overlay_script.dart) by
// patch_android.py: connects the overlay to the app through background.js.
(() => {
  if (window.top !== window.self || typeof window.__aisTake !== "function") return;
  let port = null;
  function connect() {
    port = browser.runtime.connect({ name: "ais-tab" });
    port.onMessage.addListener((m) => {
      try {
        if (m.type === "basket") window.__aisBasket(m.srcs, m.v, m.pages);
        else if (m.type === "status") window.__aisStatus(m);
        else if (m.type === "toast") window.__aisToast(m.msg);
      } catch (e) {}
    });
    port.onDisconnect.addListener(() => { port = null; setTimeout(connect, 1000); });
  }
  connect();
  setInterval(() => {
    try {
      const t = JSON.parse(window.__aisTake());
      if (t.q.length && port) port.postMessage({ type: "q", q: t.q, page: location.href, title: document.title });
    } catch (e) {}
  }, 400);
})();
