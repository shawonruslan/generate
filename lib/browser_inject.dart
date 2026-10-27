/// JavaScript injected into every page of the in-app Web browser.
///
/// It draws a small overlay on top of every visible image (it never
/// touches the page's own DOM layout): a sparkle button that asks the app
/// for an image -> prompt, and a tick box to queue several images. A
/// floating bar at the bottom generates every ticked image one by one.
///
/// Page -> app:  flutter_inappwebview.callHandler('aisPrompt', [items])
///               flutter_inappwebview.callHandler('aisGrab', reqId, dataUrl)
/// App  -> page: __aisSetState(id, 'queued'|'running'|'done'|'error')
///               __aisGrab(reqId, src)   (in-page fetch + canvas fallback)
///               __aisSetVisible(bool)
///               __aisSetDeep(bool)      (background / canvas / lazy images)
///               __aisMode('' | 'target' | 'region')
///               __aisHideUi(bool)       (hide overlay for a clean screenshot)
/// Page -> app:  callHandler('aisTarget', {sources, rect, vw, vh, page, region})
///               callHandler('aisMode', '')   (Esc pressed)
///
/// Target mode: tap anywhere; every layer under the finger is inspected
/// (elementsFromPoint, so transparent "protection" overlays, blur/locked
/// previews, CSS backgrounds, ::before/::after, lazy data-src, <canvas>,
/// SVG <image>, open shadow roots and <a href="big.jpg"> are all seen).
/// Region mode: drag a box; the app screenshots exactly that area.
const String browserInjectJs = r'''
(function () {
  if (window.__aisInit) { try { window.__aisRefresh(); } catch (e) {} return; }
  window.__aisInit = true;

  var MIN = 100;
  var nextId = 1;
  var visible = true;
  var selected = {};      // id -> true
  var states = {};        // id -> state
  var imgs = {};          // id -> element
  var btns = {};          // id -> overlay node
  var notes = {};         // id -> tooltip (error reason)
  var deep = false;       // deep scan: CSS backgrounds, canvas, lazy images
  var deepEls = [];
  var mode = '';          // '' | 'target' | 'region'
  var URL_RE = /url\(\s*(['"]?)(.*?)\1\s*\)/i;
  var ATTRS = ['data-src', 'data-original', 'data-lazy-src', 'data-lazy', 'data-bg',
    'data-background', 'data-background-image', 'data-full', 'data-full-src',
    'data-zoom-image', 'data-large', 'data-large-file', 'data-hi-res', 'data-srcset',
    'data-image', 'data-img', 'data-orig-file'];

  var css = '' +
    '#__ais_layer{position:fixed;left:0;top:0;width:0;height:0;z-index:2147483646;pointer-events:none}' +
    '.__ais_b{position:fixed;display:flex;gap:6px;pointer-events:auto;font:600 12px/1 system-ui,Segoe UI,Roboto,sans-serif}' +
    '.__ais_btn{width:30px;height:30px;border-radius:50%;border:0;cursor:pointer;display:flex;align-items:center;justify-content:center;background:rgba(17,17,24,.78);color:#fff;box-shadow:0 2px 8px rgba(0,0,0,.35);padding:0;transition:transform .12s}' +
    '.__ais_btn:hover{transform:scale(1.1);background:#4F46E5}' +
    '.__ais_btn svg{width:17px;height:17px;fill:currentColor}' +
    '.__ais_chk.on{background:#16a34a}' +
    '.__ais_go.queued{background:#a16207}.__ais_go.running{background:#4F46E5;animation:__aisp 1s infinite}' +
    '.__ais_go.done{background:#16a34a}.__ais_go.error{background:#dc2626}' +
    '@keyframes __aisp{0%,100%{opacity:1}50%{opacity:.45}}' +
    '#__ais_bar{position:fixed;left:50%;bottom:16px;transform:translateX(-50%);display:none;gap:8px;align-items:center;z-index:2147483647;' +
      'background:rgba(17,17,24,.92);color:#fff;padding:8px 10px;border-radius:14px;box-shadow:0 6px 24px rgba(0,0,0,.4);font:600 13px system-ui,Segoe UI,Roboto,sans-serif}' +
    '#__ais_bar button{border:0;border-radius:9px;padding:8px 12px;cursor:pointer;font:600 13px system-ui,Segoe UI,Roboto,sans-serif;background:#2a2a35;color:#fff}' +
    '#__ais_bar button.__ais_main{background:#4F46E5}' +
    '#__ais_tgt{position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483645;cursor:crosshair;background:rgba(79,70,229,.05);touch-action:none;display:none}' +
    '#__ais_hl{position:fixed;z-index:2147483646;pointer-events:none;border:2px solid #4F46E5;background:rgba(79,70,229,.14);border-radius:6px;display:none;transition:all .06s}' +
    '#__ais_hl.region{border-style:dashed}#__ais_hl.ok{border-color:#16a34a;background:rgba(22,163,74,.22)}' +
    '#__ais_hint{position:fixed;left:50%;top:10px;transform:translateX(-50%);z-index:2147483647;pointer-events:none;display:none;' +
      'background:rgba(17,17,24,.9);color:#fff;padding:7px 12px;border-radius:999px;font:600 12px system-ui,Segoe UI,Roboto,sans-serif}';

  var SPARK = '<svg viewBox="0 0 24 24"><path d="M12 2l1.9 5.6L19.5 9.5l-5.6 1.9L12 17l-1.9-5.6L4.5 9.5l5.6-1.9zM19 14l.9 2.6 2.6.9-2.6.9L19 21l-.9-2.6-2.6-.9 2.6-.9zM5 15l.7 1.8 1.8.7-1.8.7L5 20l-.7-1.8L2.5 17.5l1.8-.7z"/></svg>';
  var TICK = '<svg viewBox="0 0 24 24"><path d="M9 16.2l-3.5-3.5L4 14.2l5 5 11-11-1.5-1.5z"/></svg>';
  var BOX = '<svg viewBox="0 0 24 24"><path d="M19 5v14H5V5h14m0-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2z"/></svg>';

  function ensureDom() {
    if (!document.body) return false;
    if (!document.getElementById('__ais_style')) {
      var st = document.createElement('style');
      st.id = '__ais_style'; st.textContent = css;
      (document.head || document.documentElement).appendChild(st);
    }
    if (!document.getElementById('__ais_layer')) {
      var l = document.createElement('div'); l.id = '__ais_layer';
      document.documentElement.appendChild(l);
    }
    if (!document.getElementById('__ais_tgt')) {
      var tg = document.createElement('div'); tg.id = '__ais_tgt';
      var hl = document.createElement('div'); hl.id = '__ais_hl';
      var hint = document.createElement('div'); hint.id = '__ais_hint';
      document.documentElement.appendChild(tg);
      document.documentElement.appendChild(hl);
      document.documentElement.appendChild(hint);
      wireTarget(tg, hl);
    }
    if (!document.getElementById('__ais_bar')) {
      var bar = document.createElement('div'); bar.id = '__ais_bar';
      bar.innerHTML = '<span id="__ais_cnt"></span>' +
        '<button class="__ais_main" id="__ais_gen">Generate prompts</button>' +
        '<button id="__ais_all">Select all</button>' +
        '<button id="__ais_clr">Clear</button>';
      document.documentElement.appendChild(bar);
      bar.querySelector('#__ais_gen').onclick = function (e) { e.preventDefault(); e.stopPropagation(); sendSelected(); };
      bar.querySelector('#__ais_all').onclick = function (e) { e.preventDefault(); e.stopPropagation(); selectAll(); };
      bar.querySelector('#__ais_clr').onclick = function (e) { e.preventDefault(); e.stopPropagation(); selected = {}; render(); };
    }
    return true;
  }

  // Pinterest (i.pinimg.com/236x/..) -> the 736x rendition: sharper input,
  // and it exists for every pin (originals/ sometimes 403s or is a GIF).
  function upgrade(u) {
    try {
      if (/(^|\.)pinimg\.com$/.test(new URL(u).hostname)) {
        return u.replace(/\/(\d+x\d*|\d+x\d+_RS|originals)\//, '/736x/');
      }
    } catch (e) {}
    return u;
  }

  function bestSrcset(el) {
    if (!el.srcset) return '';
    var best = '', bestW = -1;
    el.srcset.split(',').forEach(function (p) {
      var bits = p.trim().split(/\s+/); if (!bits[0]) return;
      var d = bits[1] || '1x'; var n = parseFloat(d) || 1;
      if (/w$/.test(d)) n = n / 1000;
      if (bits[0].indexOf('/originals/') >= 0) n = n - 0.5; // prefer 736x over originals
      if (n > bestW) { bestW = n; best = bits[0]; }
    });
    return best;
  }

  function abs(u) {
    if (!u) return '';
    try { return upgrade(new URL(u, location.href).href); } catch (e) { return u; }
  }

  function bgOf(el, pseudo) {
    try {
      var b = window.getComputedStyle(el, pseudo || null).backgroundImage;
      if (!b || b === 'none') return '';
      var m = URL_RE.exec(b);
      if (!m || !m[2] || m[2].indexOf('data:image/svg') === 0) return '';
      return abs(m[2]);
    } catch (e) { return ''; }
  }

  // Lazy-load / zoom attributes that hold the real (often larger) file.
  function attrSrc(el) {
    if (!el.getAttribute) return '';
    for (var i = 0; i < ATTRS.length; i++) {
      var v = el.getAttribute(ATTRS[i]);
      if (!v || /^\s*$/.test(v)) continue;
      v = v.split(',').pop().trim().split(/\s+/)[0];
      if (v && v.indexOf('data:image/gif') !== 0 && v.indexOf('{') < 0) return abs(v);
    }
    return '';
  }

  function placeholder(s) {
    return !s || s.indexOf('data:image/gif') === 0 || s.indexOf('data:image/svg') === 0 ||
      /(blank|spacer|pixel|placeholder|transparent)\.(gif|png)/i.test(s);
  }

  function srcOf(el) {
    var tag = el.tagName;
    if (tag === 'VIDEO') return abs(el.poster || '');
    if (tag === 'CANVAS') return 'canvas:';
    if (tag === 'image' || tag === 'IMAGE') {
      var h = el.href && el.href.baseVal ? el.href.baseVal : (el.getAttribute('href') || el.getAttribute('xlink:href') || '');
      return abs(h);
    }
    if (tag !== 'IMG') return attrSrc(el) || bgOf(el) || bgOf(el, '::before') || bgOf(el, '::after');
    var s = bestSrcset(el) || el.currentSrc || el.src || '';
    if (placeholder(s)) s = attrSrc(el) || s;
    if (placeholder(s) && el.srcset) {
      var parts = el.srcset.split(',').map(function (p) { return p.trim().split(/\s+/)[0]; });
      if (parts.length) s = parts[parts.length - 1];
    }
    return abs(s);
  }

  // <canvas> -> JPEG data URL (null when the canvas is cross-origin tainted;
  // the app then screenshots its area instead).
  function canvasData(el) {
    try {
      var w = el.width, h = el.height;
      if (!w || !h) return '';
      var scale = Math.min(1, 2048 / Math.max(w, h));
      var c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(w * scale)); c.height = Math.max(1, Math.round(h * scale));
      var g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height);
      g.drawImage(el, 0, 0, c.width, c.height);
      return c.toDataURL('image/jpeg', 0.92);
    } catch (e) { return ''; }
  }

  function refreshDeep() {
    deepEls = [];
    if (!deep || !document.body) return;
    var all = document.body.getElementsByTagName('*');
    var n = Math.min(all.length, 6000);
    for (var i = 0; i < n; i++) {
      var el = all[i], t = el.tagName;
      if (t === 'IMG' || t === 'VIDEO' || t === 'SCRIPT' || t === 'STYLE' || ours(el)) continue;
      var r = el.getBoundingClientRect();
      if (r.width < MIN || r.height < MIN) continue;
      if (t === 'CANVAS' || t === 'image' || t === 'IMAGE') { deepEls.push(el); continue; }
      if (attrSrc(el) || bgOf(el) || bgOf(el, '::before') || bgOf(el, '::after')) deepEls.push(el);
    }
  }

  function idOf(el) {
    var s = srcOf(el);
    if (!el.__aisId || el.__aisSrc !== s) {
      if (el.__aisId && imgs[el.__aisId] === el) delete imgs[el.__aisId];
      el.__aisId = String(nextId++); el.__aisSrc = s; imgs[el.__aisId] = el;
    }
    return el.__aisId;
  }

  function mediaList() {
    var a = Array.prototype.slice.call(document.images);
    var v = document.querySelectorAll('video[poster]');
    for (var i = 0; i < v.length; i++) a.push(v[i]);
    if (deep) for (var j = 0; j < deepEls.length; j++) if (deepEls[j].isConnected) a.push(deepEls[j]);
    return a;
  }

  function candidates() {
    var out = [];
    var list = mediaList();
    var vw = window.innerWidth, vh = window.innerHeight;
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      var r = el.getBoundingClientRect();
      if (r.width < MIN || r.height < MIN) continue;
      if (r.bottom < 0 || r.top > vh || r.right < 0 || r.left > vw) continue;
      var s = srcOf(el);
      if (!s || s.indexOf('data:image/svg') === 0) continue;
      var cs = window.getComputedStyle(el);
      if (cs.visibility === 'hidden' || cs.display === 'none' || parseFloat(cs.opacity) === 0) continue;
      out.push({ el: el, r: r, src: s });
    }
    return out;
  }

  function allCandidates() {
    var out = [];
    var list = mediaList();
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      var w = el.naturalWidth || el.width || 0, h = el.naturalHeight || el.height || 0;
      var r = el.getBoundingClientRect();
      if (Math.max(r.width, w) < MIN || Math.max(r.height, h) < MIN) continue;
      var s = srcOf(el);
      if (!s || s.indexOf('data:image/svg') === 0) continue;
      out.push({ el: el, src: s });
    }
    return out;
  }

  function makeBtn(id) {
    var wrap = document.createElement('div'); wrap.className = '__ais_b';
    var go = document.createElement('button'); go.className = '__ais_btn __ais_go';
    go.title = 'Generate prompt from this image'; go.innerHTML = SPARK;
    var chk = document.createElement('button'); chk.className = '__ais_btn __ais_chk';
    chk.title = 'Tick to queue this image'; chk.innerHTML = BOX;
    go.addEventListener('click', function (e) {
      e.preventDefault(); e.stopPropagation();
      var el = imgs[id]; if (!el) return;
      send([item(id, el)]);
    }, true);
    chk.addEventListener('click', function (e) {
      e.preventDefault(); e.stopPropagation();
      if (selected[id]) delete selected[id]; else selected[id] = true;
      render();
    }, true);
    ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'touchend'].forEach(function (t) {
      wrap.addEventListener(t, function (e) { e.stopPropagation(); }, true);
    });
    wrap.appendChild(go); wrap.appendChild(chk);
    return wrap;
  }

  function item(id, el) {
    var r = el.getBoundingClientRect();
    var s = srcOf(el);
    if (s === 'canvas:') s = canvasData(el);
    // rect lets the app keep a screenshot of the image as a fallback.
    return { id: id, src: s, alt: (el.alt || (el.getAttribute && el.getAttribute('aria-label')) || '').slice(0, 200),
      w: el.naturalWidth || Math.round(r.width), h: el.naturalHeight || Math.round(r.height),
      page: location.href, rect: [r.left, r.top, r.width, r.height],
      vw: window.innerWidth, vh: window.innerHeight };
  }

  function send(items) {
    items.forEach(function (it) { states[it.id] = 'queued'; });
    render();
    try { window.flutter_inappwebview.callHandler('aisPrompt', items); } catch (e) {}
  }

  function sendSelected() {
    var items = [];
    Object.keys(selected).forEach(function (id) { var el = imgs[id]; if (el) items.push(item(id, el)); });
    selected = {};
    if (items.length) send(items);
  }

  function selectAll() {
    allCandidates().forEach(function (c) { selected[idOf(c.el)] = true; });
    render();
  }

  function render() {
    if (!ensureDom()) return;
    var layer = document.getElementById('__ais_layer');
    var seen = {};
    if (visible) {
      candidates().forEach(function (c) {
        var id = idOf(c.el); seen[id] = true;
        var b = btns[id];
        if (!b) { b = makeBtn(id); btns[id] = b; layer.appendChild(b); }
        b.style.top = Math.max(4, c.r.top + 8) + 'px';
        b.style.left = (c.r.right - 74) + 'px';
        var go = b.firstChild, chk = b.lastChild;
        go.className = '__ais_btn __ais_go' + (states[id] ? ' ' + states[id] : '');
        go.title = notes[id] || 'Generate prompt from this image';
        var on = !!selected[id];
        chk.className = '__ais_btn __ais_chk' + (on ? ' on' : '');
        chk.innerHTML = on ? TICK : BOX;
      });
    }
    Object.keys(btns).forEach(function (id) {
      if (!seen[id]) { btns[id].remove(); delete btns[id]; }
    });
    var n = Object.keys(selected).length;
    var bar = document.getElementById('__ais_bar');
    bar.style.display = (visible && n > 0) ? 'flex' : 'none';
    document.getElementById('__ais_cnt').textContent = n + ' selected';
    document.getElementById('__ais_gen').textContent = 'Generate ' + n + ' prompt' + (n === 1 ? '' : 's');
  }

  var pending = false;
  function schedule() {
    if (pending) return; pending = true;
    requestAnimationFrame(function () { pending = false; try { render(); } catch (e) {} });
  }

  window.addEventListener('scroll', schedule, true);
  window.addEventListener('resize', schedule);
  document.addEventListener('load', schedule, true);
  function ours(n) {
    while (n) { if (typeof n.id === 'string' && n.id.indexOf('__ais_') === 0) return true; n = n.parentNode; }
    return false;
  }

  // ---------------------------------------------------------------- target
  function stackAt(x, y) {
    var out = [];
    var els = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
    for (var i = 0; i < els.length; i++) {
      var e = els[i];
      if (ours(e) || out.indexOf(e) >= 0) continue;
      out.push(e);
      if (e.shadowRoot && e.shadowRoot.elementsFromPoint) {
        var sh = e.shadowRoot.elementsFromPoint(x, y);
        for (var j = 0; j < sh.length; j++) if (out.indexOf(sh[j]) < 0) out.push(sh[j]);
      }
    }
    return out;
  }

  function isMedia(t) { return t === 'IMG' || t === 'VIDEO' || t === 'CANVAS' || t === 'image' || t === 'IMAGE'; }

  // Every image source under (x, y), top layer to bottom, best first.
  function pickAt(x, y, light) {
    var stack = stackAt(x, y), found = [], seen = {}, box = null;
    var full = window.innerWidth * window.innerHeight;
    for (var i = 0; i < stack.length && i < 40; i++) {
      var e = stack[i];
      if (e === document.documentElement || e === document.body) continue;
      var r = e.getBoundingClientRect();
      if (r.width < 40 || r.height < 40) continue;
      var srcs = [];
      var s = srcOf(e);
      if (s === 'canvas:') s = light ? 'canvas:' : canvasData(e);
      if (s) srcs.push(s);
      if (e.tagName !== 'IMG') {
        var b1 = bgOf(e, '::before'), b2 = bgOf(e, '::after');
        if (b1) srcs.push(b1); if (b2) srcs.push(b2);
      }
      if (e.tagName === 'IMG') { var a2 = attrSrc(e); if (a2) srcs.push(a2); }
      var a = e.closest ? e.closest('a[href]') : null;
      var href = a ? (a.getAttribute('href') || '') : '';
      if (/\.(jpe?g|png|webp|gif|avif|bmp)(\?|#|$)/i.test(href)) srcs.push(abs(href));
      var area = r.width * r.height;
      srcs.forEach(function (u) {
        if (!u || seen[u] || u.indexOf('data:image/svg') === 0) return; seen[u] = 1;
        found.push({ src: u, kind: e.tagName.toLowerCase(),
          w: e.naturalWidth || Math.round(r.width), h: e.naturalHeight || Math.round(r.height),
          score: area * (isMedia(e.tagName) ? 1.3 : 1) * (area > full * 0.95 ? 0.3 : 1),
          rect: [r.left, r.top, r.width, r.height] });
      });
      if (!box && srcs.length) box = r;
      if (!box && light === 'box' && area < full * 0.85) box = r;
    }
    found.sort(function (p, q) { return q.score - p.score; });
    if (found.length) { var fr = found[0].rect; box = { left: fr[0], top: fr[1], width: fr[2], height: fr[3] }; }
    if (!box) {
      // Nothing readable (cross-origin iframe, closed shadow DOM, CSS art):
      // fall back to the smallest sizeable layer, else a box around the tap.
      for (var k = 0; k < stack.length; k++) {
        var rr = stack[k].getBoundingClientRect();
        if (rr.width >= 60 && rr.height >= 60 && rr.width * rr.height < full * 0.85) { box = rr; break; }
      }
    }
    if (!box) box = { left: x - 160, top: y - 160, width: 320, height: 320 };
    return { found: found.slice(0, 8), box: box };
  }

  function showBox(hl, b, cls) {
    hl.className = cls || '';
    hl.style.display = 'block';
    hl.style.left = b.left + 'px'; hl.style.top = b.top + 'px';
    hl.style.width = b.width + 'px'; hl.style.height = b.height + 'px';
  }

  function post(payload) {
    try { window.flutter_inappwebview.callHandler('aisTarget', payload); } catch (e) {}
  }

  function wireTarget(tg, hl) {
    var start = null, hoverPending = false, lastXY = null;
    function stop(e) { e.preventDefault(); e.stopPropagation(); }
    tg.addEventListener('pointermove', function (e) {
      stop(e);
      if (mode === 'region') {
        if (!start) return;
        var x0 = Math.min(start[0], e.clientX), y0 = Math.min(start[1], e.clientY);
        showBox(hl, { left: x0, top: y0, width: Math.abs(e.clientX - start[0]), height: Math.abs(e.clientY - start[1]) }, 'region');
        return;
      }
      lastXY = [e.clientX, e.clientY];
      if (hoverPending) return; hoverPending = true;
      requestAnimationFrame(function () {
        hoverPending = false;
        if (mode !== 'target' || !lastXY) return;
        showBox(hl, pickAt(lastXY[0], lastXY[1], 'box').box, '');
      });
    }, true);
    tg.addEventListener('pointerdown', function (e) {
      stop(e);
      if (mode === 'region') { start = [e.clientX, e.clientY]; try { tg.setPointerCapture(e.pointerId); } catch (x) {} }
    }, true);
    tg.addEventListener('pointerup', function (e) {
      stop(e);
      var vw = window.innerWidth, vh = window.innerHeight;
      if (mode === 'region') {
        if (!start) return;
        var x0 = Math.min(start[0], e.clientX), y0 = Math.min(start[1], e.clientY);
        var w = Math.abs(e.clientX - start[0]), h = Math.abs(e.clientY - start[1]);
        start = null;
        if (w < 24 || h < 24) { hl.style.display = 'none'; return; }
        showBox(hl, { left: x0, top: y0, width: w, height: h }, 'region ok');
        post({ sources: [], rect: [x0, y0, w, h], vw: vw, vh: vh, page: location.href, region: true });
        setTimeout(function () { hl.style.display = 'none'; }, 700);
        return;
      }
      if (mode !== 'target') return;
      var p = pickAt(e.clientX, e.clientY, false);
      showBox(hl, p.box, 'ok');
      post({ sources: p.found.map(function (f) { return { src: f.src, kind: f.kind, w: f.w, h: f.h }; }),
        rect: [p.box.left, p.box.top, p.box.width, p.box.height], vw: vw, vh: vh, page: location.href, region: false });
    }, true);
    ['click', 'mousedown', 'mouseup', 'touchstart', 'touchmove', 'touchend', 'contextmenu'].forEach(function (t) {
      tg.addEventListener(t, function (e) {
        // Target mode keeps finger scrolling; region mode owns the gesture.
        if ((t === 'touchstart' || t === 'touchmove') && mode !== 'region') { e.stopPropagation(); return; }
        stop(e);
      }, { capture: true, passive: false });
    });
    tg.addEventListener('pointercancel', function () { start = null; hl.style.display = 'none'; }, true);
  }

  function applyMode() {
    if (!ensureDom()) return;
    var tg = document.getElementById('__ais_tgt'), hl = document.getElementById('__ais_hl'), hint = document.getElementById('__ais_hint');
    tg.style.display = mode ? 'block' : 'none';
    tg.style.touchAction = mode === 'region' ? 'none' : 'pan-x pan-y pinch-zoom';
    hl.style.display = 'none';
    hint.style.display = mode ? 'block' : 'none';
    hint.textContent = mode === 'region'
      ? 'Drag a box around any area to turn it into a prompt  (Esc to exit)'
      : 'Target mode: tap any image, even locked or hidden ones  (Esc to exit)';
  }

  document.addEventListener('keydown', function (e) {
    if (mode && e.key === 'Escape') {
      mode = ''; applyMode();
      try { window.flutter_inappwebview.callHandler('aisMode', ''); } catch (x) {}
    }
  }, true);
  try { new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) { if (!ours(muts[i].target)) { schedule(); return; } }
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'srcset', 'style', 'class'] }); } catch (e) {}
  setInterval(function () { if (deep) refreshDeep(); schedule(); }, 1500);

  window.__aisRefresh = schedule;
  window.__aisSetDeep = function (v) { deep = !!v; refreshDeep(); schedule(); };
  window.__aisMode = function (m) { mode = m || ''; applyMode(); };
  window.__aisHideUi = function (h) {
    ['__ais_layer', '__ais_bar', '__ais_tgt', '__ais_hl', '__ais_hint'].forEach(function (id) {
      var n = document.getElementById(id); if (n) n.style.visibility = h ? 'hidden' : '';
    });
  };
  window.__aisSetVisible = function (v) { visible = !!v; schedule(); };
  window.__aisSetState = function (id, s, note) {
    states[id] = s; notes[id] = note || ''; schedule();
  };

  // In-page grab: fetch with the page's own cookies, re-encode to JPEG via
  // canvas (handles AVIF/SVG/blob: that the app cannot decode itself).
  window.__aisGrab = function (reqId, src) {
    function reply(v) { try { window.flutter_inappwebview.callHandler('aisGrab', reqId, v || ''); } catch (e) {} }
    function viaCanvas(source) {
      try {
        var w = source.naturalWidth || source.width, h = source.naturalHeight || source.height;
        var scale = Math.min(1, 2048 / Math.max(w, h));
        var c = document.createElement('canvas');
        c.width = Math.max(1, Math.round(w * scale)); c.height = Math.max(1, Math.round(h * scale));
        c.getContext('2d').drawImage(source, 0, 0, c.width, c.height);
        return c.toDataURL('image/jpeg', 0.92);
      } catch (e) { return ''; }
    }
    function get(mode) {
      return fetch(src, { credentials: mode, mode: 'cors' }).then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob();
      });
    }
    get('omit').catch(function () { return get('include'); }).then(function (blob) {
      if (window.createImageBitmap) {
        return createImageBitmap(blob).then(function (bmp) { reply(viaCanvas(bmp)); });
      }
      var fr = new FileReader(); fr.onload = function () { reply(fr.result); }; fr.readAsDataURL(blob);
    }).catch(function () {
      // Last resort: the already-loaded element itself (works when the
      // image is same-origin or CORS-enabled).
      var el = null;
      Object.keys(imgs).some(function (id) { if (srcOf(imgs[id]) === src) { el = imgs[id]; return true; } return false; });
      reply(el ? viaCanvas(el) : '');
    });
  };

  schedule();
})();
''';
