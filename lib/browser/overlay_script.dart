/// JavaScript injected into every tab of the controlled Chromium window
/// through the Chrome DevTools Protocol (`Page.addScriptToEvaluateOnNewDocument`).
///
/// It draws, inside a closed shadow root (so no site CSS leaks in or out):
///  * a floating toolbar on the hovered image: "Prompt" (generate now) and
///    a tick box (mark for batch);
///  * a coloured frame + status tag on every ticked / queued / running /
///    finished image;
///  * a dock at the bottom ("N selected · Generate prompts · Select all ·
///    Clear") while at least one image is ticked.
///
/// Requests go to the app through the CDP binding `__aisBridge`
/// (`Runtime.addBinding`); the app pushes status back by calling
/// `window.__aisStatus({src, state, message})`.
const String overlayBindingName = '__aisBridge';

const String overlayScript = r'''
(() => {
  try {
    if (window.top !== window.self) return;
    if (window.__aisInstalled) return;
    window.__aisInstalled = true;
  } catch (e) { return; }

  const BIND = '__aisBridge';
  const MIN = 72;
  const sel = new Map();   // src -> img element (ticked, not yet sent)
  const stat = new Map();  // src -> {el, state, message}
  let hoverImg = null, host = null, root = null, bar = null, btnGen = null,
      btnSel = null, layer = null, dock = null, dockCount = null, toastEl = null;
  let lastX = -1, lastY = -1, moveRaf = 0, layoutRaf = 0, toastTimer = 0, ticker = 0;
  const frames = new Map(); // src -> frame element

  const svg = (d) => '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true">' + d + '</svg>';
  const I_SPARK = svg('<path fill="currentColor" d="M11 2.5l1.8 5.2 5.2 1.8-5.2 1.8L11 16.5l-1.8-5.2L4 9.5l5.2-1.8zM18.5 14l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9z"/>');
  const I_BOX = svg('<rect x="4" y="4" width="16" height="16" rx="3" fill="none" stroke="currentColor" stroke-width="2"/>');
  const I_TICK = svg('<path fill="currentColor" d="M9.2 16.6 4.9 12.3l-1.4 1.4 5.7 5.7L20.6 8l-1.4-1.4z"/>');
  const I_ERR = svg('<path fill="currentColor" d="M11 6h2v8h-2zm0 10h2v2h-2z"/>');
  const I_WAIT = svg('<path fill="currentColor" d="M12 4a8 8 0 1 0 0 16 8 8 0 0 0 0-16zm1 8.4 3 1.8-.8 1.3L11 13V7h2z"/>');

  const CSS = `
    *{box-sizing:border-box;font-family:"Segoe UI",system-ui,-apple-system,sans-serif;}
    .bar{position:fixed;display:none;gap:6px;z-index:3;}
    .b{display:inline-flex;align-items:center;justify-content:center;gap:6px;height:32px;padding:0 12px 0 10px;border:0;border-radius:16px;
       background:rgba(17,17,27,.84);color:#fff;font-size:12px;font-weight:600;cursor:pointer;box-shadow:0 2px 10px rgba(0,0,0,.35);
       backdrop-filter:blur(6px);transition:background .12s,transform .12s;}
    .b:hover{background:#4F46E5;transform:translateY(-1px);}
    .b.sel{width:32px;padding:0;}
    .b.sel.on{background:#4F46E5;}
    .layer{position:fixed;left:0;top:0;width:0;height:0;z-index:1;}
    .frame{position:fixed;border:3px solid #4F46E5;border-radius:10px;pointer-events:none;box-shadow:0 0 0 1px rgba(255,255,255,.6) inset;}
    .frame.queued{border-color:#64748b;} .frame.running{border-color:#f59e0b;}
    .frame.done{border-color:#10b981;} .frame.error{border-color:#ef4444;}
    .tag{position:absolute;left:6px;top:6px;display:inline-flex;align-items:center;gap:5px;max-width:calc(100% - 12px);padding:3px 9px 3px 5px;
       border-radius:12px;background:#4F46E5;color:#fff;font-size:11px;font-weight:600;pointer-events:auto;cursor:pointer;white-space:nowrap;overflow:hidden;
       box-shadow:0 2px 8px rgba(0,0,0,.3);}
    .queued .tag{background:#64748b;} .running .tag{background:#f59e0b;} .done .tag{background:#10b981;} .error .tag{background:#ef4444;}
    .tag svg{flex:none;width:14px;height:14px;}
    .spin{flex:none;width:12px;height:12px;margin:1px;border:2px solid rgba(255,255,255,.45);border-top-color:#fff;border-radius:50%;animation:s .8s linear infinite;}
    @keyframes s{to{transform:rotate(360deg);}}
    .dock{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);display:none;align-items:center;gap:8px;padding:8px 8px 8px 16px;
       border-radius:26px;background:rgba(17,17,27,.94);color:#fff;font-size:13px;font-weight:600;box-shadow:0 10px 30px rgba(0,0,0,.45);z-index:4;}
    .d{height:34px;padding:0 14px;border:0;border-radius:17px;background:rgba(255,255,255,.13);color:#fff;font-size:12px;font-weight:600;cursor:pointer;}
    .d:hover{background:rgba(255,255,255,.22);} .d.go{background:#4F46E5;} .d.go:hover{background:#6366f1;}
    .toast{position:fixed;right:24px;bottom:90px;display:none;max-width:360px;padding:10px 14px;border-radius:12px;background:rgba(17,17,27,.94);
       color:#fff;font-size:12.5px;box-shadow:0 8px 24px rgba(0,0,0,.4);z-index:5;}
  `;

  const srcOf = (img) => (img && (img.currentSrc || img.src)) || '';
  function usable(img) {
    if (!img || img.tagName !== 'IMG') return false;
    const s = srcOf(img);
    if (!s || s.startsWith('data:image/svg') || s.startsWith('data:image/gif;base64,R0lGOD')) return false;
    const r = img.getBoundingClientRect();
    return r.width >= MIN && r.height >= MIN;
  }
  const info = (img) => ({ src: srcOf(img), alt: (img.alt || img.title || '').slice(0, 300),
                           w: img.naturalWidth || 0, h: img.naturalHeight || 0 });
  const stop = (e) => { e.stopPropagation(); };

  function ensure() {
    if (host && host.isConnected) return true;
    const parent = document.documentElement;
    if (!parent) return false;
    if (!host) {
      host = document.createElement('ais-image-prompt');
      host.style.cssText = 'all:initial;position:fixed;left:0;top:0;width:0;height:0;z-index:2147483647;pointer-events:none;';
      root = host.attachShadow({ mode: 'closed' });
      root.innerHTML = '<style>' + CSS + '</style>' +
        '<div class="layer"></div>' +
        '<div class="bar" style="pointer-events:auto">' +
          '<button class="b gen" title="Generate an image prompt from this picture">' + I_SPARK + '<span>Prompt</span></button>' +
          '<button class="b sel" title="Tick to add this picture to the batch">' + I_BOX + '</button>' +
        '</div>' +
        '<div class="dock" style="pointer-events:auto"><span class="cnt"></span>' +
          '<button class="d go" title="Generate prompts for all ticked pictures, one by one">Generate prompts</button>' +
          '<button class="d all" title="Tick every picture on this page">Select all</button>' +
          '<button class="d clr">Clear</button></div>' +
        '<div class="toast"></div>';
      layer = root.querySelector('.layer');
      bar = root.querySelector('.bar');
      btnGen = root.querySelector('.gen');
      btnSel = root.querySelector('.sel');
      dock = root.querySelector('.dock');
      dockCount = root.querySelector('.cnt');
      toastEl = root.querySelector('.toast');
      for (const ev of ['pointerdown', 'mousedown', 'mouseup', 'click', 'dblclick', 'contextmenu']) {
        root.addEventListener(ev, stop);
      }
      btnGen.addEventListener('click', (e) => { e.preventDefault(); if (hoverImg) send('single', [hoverImg]); });
      btnSel.addEventListener('click', (e) => { e.preventDefault(); if (hoverImg) toggle(hoverImg); });
      root.querySelector('.go').addEventListener('click', (e) => { e.preventDefault(); sendSelected(); });
      root.querySelector('.all').addEventListener('click', (e) => { e.preventDefault(); selectAll(); });
      root.querySelector('.clr').addEventListener('click', (e) => { e.preventDefault(); sel.clear(); schedule(); });
    }
    parent.appendChild(host);
    return true;
  }

  function toast(msg) {
    if (!ensure()) return;
    toastEl.textContent = msg;
    toastEl.style.display = 'block';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toastEl.style.display = 'none'; }, 2600);
  }

  function toggle(img) {
    const s = srcOf(img);
    if (!s) return;
    if (sel.has(s)) sel.delete(s); else { sel.set(s, img); stat.delete(s); }
    schedule();
  }

  function selectAll() {
    let n = 0;
    for (const img of document.images) {
      if (n >= 300) break;
      if (!usable(img)) continue;
      const s = srcOf(img);
      if (sel.has(s)) continue;
      const st = stat.get(s);
      if (st && st.state !== 'error') continue; // already queued / done
      sel.set(s, img); n++;
    }
    toast(n ? n + ' pictures ticked' : 'No new pictures found on this page');
    schedule();
  }

  function send(action, imgs) {
    const fn = window[BIND];
    if (typeof fn !== 'function') {
      toast('AI Image Studio is not connected to this tab. Reopen the browser from the app.');
      return false;
    }
    const items = [], seen = new Set();
    for (const img of imgs) {
      const i = info(img);
      if (!i.src || seen.has(i.src)) continue;
      seen.add(i.src);
      items.push(i);
      stat.set(i.src, { el: img, state: 'queued', message: '' });
      sel.delete(i.src);
    }
    if (!items.length) return false;
    try {
      fn(JSON.stringify({ action, images: items, page: location.href, title: document.title }));
    } catch (e) { toast('Could not reach AI Image Studio: ' + e); return false; }
    toast(items.length === 1 ? 'Sent to AI Image Studio' : items.length + ' pictures queued in AI Image Studio (one by one)');
    schedule();
    return true;
  }

  function sendSelected() {
    const imgs = [...sel.values()];
    if (!imgs.length) return;
    send('batch', imgs);
  }

  function findImg(src) {
    for (const img of document.images) if (srcOf(img) === src) return img;
    return null;
  }

  window.__aisStatus = (o) => {
    try {
      if (!o || !o.src) return;
      const cur = stat.get(o.src) || { el: findImg(o.src) };
      cur.state = o.state || 'queued';
      cur.message = o.message || '';
      if (!cur.el || !cur.el.isConnected) cur.el = findImg(o.src);
      stat.set(o.src, cur);
      schedule();
    } catch (e) {}
  };
  window.__aisToast = (m) => { try { toast(String(m)); } catch (e) {} };

  // ---------------------------------------------------------------- hover
  function pickHover() {
    moveRaf = 0;
    if (lastX < 0) return;
    let found = null;
    let els = [];
    try { els = document.elementsFromPoint(lastX, lastY); } catch (e) {}
    for (const el of els) {
      if (el === host) continue;
      if (el.tagName === 'IMG' && usable(el)) { found = el; break; }
    }
    if (!found) {
      // Pictures covered by an overlay link / div (Pinterest, galleries):
      // look a little inside the top-most elements under the pointer.
      let checked = 0;
      for (const el of els) {
        if (el === host || el === document.body || el === document.documentElement) continue;
        if (++checked > 6) break;
        const imgs = el.getElementsByTagName('img');
        if (!imgs.length || imgs.length > 6) continue;
        for (const img of imgs) {
          const r = img.getBoundingClientRect();
          if (lastX >= r.left && lastX <= r.right && lastY >= r.top && lastY <= r.bottom && usable(img)) { found = img; break; }
        }
        if (found) break;
      }
    }
    if (found !== hoverImg) { hoverImg = found; schedule(); }
  }

  function onMove(e) {
    lastX = e.clientX; lastY = e.clientY;
    if (!moveRaf) moveRaf = requestAnimationFrame(pickHover);
  }

  // --------------------------------------------------------------- layout
  function schedule() {
    if (!layoutRaf) layoutRaf = requestAnimationFrame(layout);
  }

  function frameFor(src) {
    let f = frames.get(src);
    if (!f) {
      f = document.createElement('div');
      f.className = 'frame';
      f.innerHTML = '<div class="tag"></div>';
      f.firstChild.addEventListener('click', (e) => {
        e.preventDefault();
        if (sel.has(src)) sel.delete(src); else stat.delete(src);
        schedule();
      });
      layer.appendChild(f);
      frames.set(src, f);
    }
    return f;
  }

  function layout() {
    layoutRaf = 0;
    if (!ensure()) return;
    const vw = innerWidth, vh = innerHeight;

    // hover toolbar
    if (hoverImg && hoverImg.isConnected) {
      const r = hoverImg.getBoundingClientRect();
      if (r.bottom > 0 && r.top < vh && r.width >= MIN) {
        const ticked = sel.has(srcOf(hoverImg));
        btnSel.classList.toggle('on', ticked);
        btnSel.innerHTML = ticked ? I_TICK : I_BOX;
        btnSel.title = ticked ? 'Untick' : 'Tick to add this picture to the batch';
        bar.style.display = 'flex';
        const bw = bar.offsetWidth || 120;
        const top = Math.max(r.top, 0) + 8;
        const left = Math.min(Math.max(r.right - bw - 8, r.left + 8), vw - bw - 8);
        bar.style.top = top + 'px';
        bar.style.left = Math.max(left, 4) + 'px';
      } else bar.style.display = 'none';
    } else bar.style.display = 'none';

    // frames for ticked + tracked pictures
    const live = new Set();
    const draw = (src, el, state, message) => {
      if (!el || !el.isConnected) return;
      const r = el.getBoundingClientRect();
      if (r.width < 8 || r.bottom < 0 || r.top > vh || r.right < 0 || r.left > vw) return;
      live.add(src);
      const f = frameFor(src);
      f.className = 'frame ' + state;
      f.style.left = r.left + 'px'; f.style.top = r.top + 'px';
      f.style.width = r.width + 'px'; f.style.height = r.height + 'px';
      const tag = f.firstChild;
      const label = {
        selected: I_TICK + 'Selected',
        queued: I_WAIT + 'Queued',
        running: '<span class="spin"></span>Analyzing...',
        done: I_TICK + 'Prompt ready',
        error: I_ERR + 'Failed',
      }[state] || state;
      if (tag.__l !== label) { tag.innerHTML = label; tag.__l = label; }
      tag.title = message || (state === 'selected' ? 'Click to untick' : 'Click to hide');
    };
    for (const [src, el] of sel) draw(src, el, 'selected', '');
    for (const [src, st] of stat) if (!sel.has(src)) draw(src, st.el, st.state, st.message);
    for (const [src, f] of frames) if (!live.has(src)) { f.remove(); frames.delete(src); }

    // dock
    if (sel.size) {
      dockCount.textContent = sel.size + (sel.size === 1 ? ' picture selected' : ' pictures selected');
      dock.style.display = 'flex';
    } else dock.style.display = 'none';

    const busy = sel.size || stat.size;
    if (busy && !ticker) ticker = setInterval(schedule, 400);
    if (!busy && ticker) { clearInterval(ticker); ticker = 0; }
  }

  addEventListener('pointermove', onMove, { capture: true, passive: true });
  addEventListener('scroll', schedule, { capture: true, passive: true });
  addEventListener('resize', schedule, { passive: true });
  document.addEventListener('pointerleave', () => { lastX = -1; hoverImg = null; schedule(); });
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => ensure());
  else ensure();
})();
''';
