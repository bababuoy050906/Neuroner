let paintJS = #"""
(function () {
  'use strict';
  const X = window.MMX;
  if (!X) return;
  const view = X.view, host = document.getElementById('canvas'), tbar = document.getElementById('toolbar');
  const NS = 'http://www.w3.org/2000/svg', KEY = 'mm-paint2';
  const PALETTE = ['#1D3557', '#000000', '#E63946', '#F4A261', '#E9C46A', '#2A9D8F', '#70AD47', '#00B4D8', '#457B9D', '#9B5DE5', '#F15BB5', '#FFFFFF'];
  const STY = { pen: { w: 1, o: 1, name: 'Pen' }, marker: { w: 2.4, o: 0.88, name: 'Marker' }, hl: { w: 5, o: 0.32, name: 'Highlighter' } };
    const LASER_COLORS = [
    { n: 'Red', c: '#FF2D2D' }, { n: 'Orange', c: '#FF8A00' }, { n: 'Yellow', c: '#FFD60A' }, { n: 'Green', c: '#2BFF4F' },
    { n: 'Purple', c: '#A64DFF' }, { n: 'Pink', c: '#FF4FD8' }, { n: 'Blue-Green', c: '#00F0C8' }
  ];
  const LASER_MODES = ['dot', 'trail', 'line'], LASER_LABEL = { dot: 'Dot', trail: 'Short trail', line: 'Line' };
  const LZ_TRAIL = 650, LZ_DOT = 260, LZ_IDLE = 2500, LZ_FADE = 600;   // trail life · dot fade-out · line idle time · line fade-out (ms)
  const MARG = 0.18, CHUNK = 900;
           // extra bitmap around the screen · points after which a long stroke is cut into pieces
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const f2 = v => Math.round(v * 100) / 100;
  const r1 = v => Math.round(v * 20) / 20;
  const stat = m => { const s = document.getElementById('status'); if (s) s.textContent = m; };
  function buzz() {
    try { const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic; if (h) { h.postMessage('heavy'); return; } } catch (e) { /* ignore */ }
    try { if (navigator.vibrate) navigator.vibrate(30); } catch (e) { /* ignore */ }
  }
  const svgEl = (t, a) => { const e = document.createElementNS(NS, t); if (a) for (const k in a) e.setAttribute(k, a[k]); return e; };
  const hEl = (t, c, html) => { const e = document.createElement(t); if (c) e.className = c; if (html != null) e.innerHTML = html; return e; };

  /* ---------- settings (saved on this device, written lazily) ---------- */
  const D = {
    style: 'pen', color: '#1D3557', width: 4, smooth: 0.3,
    presets: [{ s: 'pen', c: '#1D3557', w: 3 }, { s: 'pen', c: '#E63946', w: 3 }, { s: 'marker', c: '#2A9D8F', w: 5 }, { s: 'hl', c: '#E9C46A', w: 6 }, { s: 'pen', c: '#000000', w: 2 }],
    recent: ['#1D3557', '#E63946', '#2A9D8F', '#E9C46A'],
    swap: true, protect: true, whole: false, eraseSize: 22,
    snap: true, filt: { ink: true, hl: true, text: false, img: false, boxes: false },
        touch: true, laser: { color: '#FF2D2D', mode: 'dot' }, pos: { x: 8, y: 70, o: 'v', edge: 'l' }

  };
  const P = JSON.parse(JSON.stringify(D));
  try {
    const s = JSON.parse(localStorage.getItem(KEY) || 'null');
        if (s) { Object.assign(P, s); P.filt = Object.assign({}, D.filt, s.filt || {}); P.pos = Object.assign({}, D.pos, s.pos || {}); P.laser = Object.assign({}, D.laser, s.laser || {}); }

  } catch (e) { /* ignore */ }
  if (!Array.isArray(P.presets) || P.presets.length !== 5) P.presets = D.presets.slice();
  if (!Array.isArray(P.recent)) P.recent = D.recent.slice();
    if (!STY[P.style]) P.style = 'pen';
  if (!P.laser || !LASER_COLORS.some(c => c.c === P.laser.color)) P.laser = Object.assign({}, D.laser, P.laser && LASER_MODES.indexOf(P.laser.mode) >= 0 ? { mode: P.laser.mode } : {});
  if (LASER_MODES.indexOf(P.laser.mode) < 0) P.laser.mode = 'dot';

    let saveT = 0;
  function flushSettings() { clearTimeout(saveT); try { localStorage.setItem(KEY, JSON.stringify(P)); } catch (e) { /* ignore */ } }
  // called when the app is about to leave the screen: finishes whatever is still being drawn so it is part of the save
  function flushNow() {
    try {
      [...live.keys()].forEach(id => stopPen(id));
      if (typeof releaseLasers === 'function') releaseLasers();
      if (act) finishAct();
      clearTimeout(recT);
      if (recPending) { addRecent(recPending); recPending = null; }
    } catch (err) { console.error(err); }
    flushSettings();
  }

  const save = () => { clearTimeout(saveT); saveT = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(P)); } catch (e) { /* ignore */ } }, 700); };

  /* ---------- styles ---------- */
  const CSS = `
#inkBase,#inkLive{position:absolute;pointer-events:none;z-index:2;transform-origin:0 0}
#inkBase{will-change:transform}
#inkLive{left:0;top:0}
#inkSvg{position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:2;overflow:hidden}
#inkLaser{position:absolute;left:0;top:0;pointer-events:none;z-index:2}

.paint-on #canvas{cursor:crosshair;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
#paintBtn.on{background:#2A9D8F;border-color:#2A9D8F;color:#fff}
#pnt{position:absolute;z-index:5;display:flex;align-items:center;gap:6px;padding:6px;background:var(--pop);color:var(--fg);border:1px solid var(--fieldb);border-radius:18px;box-shadow:0 6px 22px rgba(0,0,0,.3);touch-action:none}
#pnt.v{flex-direction:column;width:56px}
#pnt.h{flex-direction:row}
#pnt[hidden],#pPop[hidden],#pSel[hidden],#pDlg[hidden]{display:none}
#pnt button,#pSel button{flex:none;width:40px;height:40px;padding:0;border-radius:12px;font-size:20px;display:flex;align-items:center;justify-content:center;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
#pnt button.on,#pSel button.on{background:#2A9D8F;border-color:#2A9D8F;color:#fff}
#pGrip{width:40px;height:20px;line-height:20px;text-align:center;font-size:18px;color:var(--muted);cursor:grab;flex:none;touch-action:none;-webkit-user-select:none;user-select:none}
.pt{display:flex;gap:6px}
#pnt.v .pt{flex-direction:column}
#pCol i{display:block;width:22px;height:22px;border-radius:50%;border:2px solid #fff;box-shadow:0 0 0 1px rgba(0,0,0,.45)}
.pp,.pr{display:flex;flex-wrap:wrap;gap:4px;justify-content:center;align-items:center}
#pnt.v .pp{width:44px}
#pnt.v .pr{width:44px;gap:3px}
#pnt.h .pp,#pnt.h .pr{flex-wrap:nowrap}
#pnt .pre{width:20px;height:20px;border:2px solid var(--fg);border-radius:50%;padding:0;display:block}
#pnt .pre.s-marker{border-radius:6px}
#pnt .pre.s-hl{height:12px;border-radius:6px}
#pnt .pre.on{outline:3px solid #2A9D8F;outline-offset:1px}
#pnt .rc{width:12px;height:12px;border-radius:50%;border:1px solid rgba(0,0,0,.45);padding:0;display:block}
#pPop{position:absolute;z-index:6;width:min(270px,calc(100% - 16px));max-height:calc(100% - 16px);overflow:auto;background:var(--pop);color:var(--fg);border:1px solid var(--fieldb);border-radius:14px;padding:12px;box-shadow:0 8px 26px rgba(0,0,0,.32);display:flex;flex-direction:column;gap:10px;font-size:14px}
#pPop .pph{font-weight:700}
#pPop small{color:var(--muted);font-size:11px;line-height:1.3}
#pPop .chips{display:flex;flex-wrap:wrap;gap:6px}
#pPop .chip{min-width:34px;height:34px;padding:0 10px;border-radius:17px;font-size:13px}
#pPop .chip.on{outline:3px solid #2A9D8F;outline-offset:1px}
#pPop .sw{width:30px;min-width:30px;height:30px;padding:0;border-radius:50%;border:1px solid rgba(0,0,0,.4)}
#pPop .sw.on{outline:3px solid #2A9D8F;outline-offset:1px}
#pPop .sl{display:flex;flex-direction:column;gap:2px;font-size:13px}
#pPop .sl b{float:right}
#pPop input[type=range]{width:100%;accent-color:#2A9D8F;height:34px}
#pPop .tg{display:flex;align-items:flex-start;gap:8px;font-size:13px;line-height:1.3}
#pPop .tg input{width:22px;height:22px;flex:none;accent-color:#2A9D8F;margin:0}
#pPop .tg.off{opacity:.45}
#pPop .row2{display:flex;align-items:center;gap:8px}
#pPop svg{width:100%;height:36px;background:var(--field);border-radius:8px}
#pPop input[type=color]{width:44px;height:34px;padding:0;border:1px solid var(--fieldb);border-radius:8px;background:none}
#pSel{position:absolute;z-index:5;display:flex;gap:6px;padding:5px;background:var(--pop);border:1px solid var(--fieldb);border-radius:18px;box-shadow:0 5px 18px rgba(0,0,0,.3);touch-action:none}
#pDlg{position:fixed;inset:0;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;z-index:70}
#pDlg .card{background:var(--pop);color:var(--fg);padding:14px;border-radius:12px;width:min(92vw,520px);max-height:88vh;display:flex;flex-direction:column;gap:10px;box-shadow:0 10px 30px rgba(0,0,0,.4)}
#pDlg img{max-width:100%;max-height:60vh;object-fit:contain;background:#fff;border-radius:8px;-webkit-touch-callout:default;-webkit-user-select:auto;user-select:auto}
`;
  const stEl = document.createElement('style'); stEl.textContent = CSS; document.head.appendChild(stEl);

  /* ---------- layers: committed ink (bitmap) · the stroke being drawn (bitmap) · handles and cursors (small svg) ---------- */
  const base = hEl('canvas'); base.id = 'inkBase';
  const liveC = hEl('canvas'); liveC.id = 'inkLive';
  const inkSvg = svgEl('svg', { id: 'inkSvg' });
  const gT = svgEl('g'), gC = svgEl('g');
  gT.appendChild(gC); inkSvg.appendChild(gT);
    host.insertBefore(base, tbar); host.insertBefore(liveC, tbar); host.insertBefore(inkSvg, tbar);
  const laserC = hEl('canvas'); laserC.id = 'inkLaser';
  host.insertBefore(laserC, tbar);


  const pnt = hEl('div'); pnt.id = 'pnt'; pnt.hidden = true; pnt.setAttribute('data-pui', '1');
  pnt.innerHTML = '<div id="pGrip" title="Drag to move the tools">⠿</div>' +
    '<div class="pt"><button data-t="hand" title="Move the canvas">🖐</button><button data-t="pen" title="Pen · tap again for options">✒️</button>' +
    '<button data-t="eraser" title="Eraser · tap again for options">🧽</button><button data-t="lasso" title="Lasso · tap again for options">➰</button><button data-t="blasso" title="Boxes-only lasso · a partial loop selects whole boxes">▭</button><button data-t="laser" title="Laser pointer · tap again for options">🔴</button></div>'
 +
    '<button id="pCol" title="Colour"><i></i></button><div class="pp" id="pPre"></div><div class="pr" id="pRec"></div>' +
    '<button id="pFin">☝️</button><button id="pClose" title="Close the painting tools">✕</button>';
  host.appendChild(pnt);
  const pop = hEl('div'); pop.id = 'pPop'; pop.hidden = true; pop.setAttribute('data-pui', '1'); host.appendChild(pop);
  const selBar = hEl('div'); selBar.id = 'pSel'; selBar.hidden = true; selBar.setAttribute('data-pui', '1');
  selBar.innerHTML = '<button data-a="col" title="Recolor the ink">🎨</button><button data-a="cover" title="Cover / uncover the boxes">🩹</button>' +
    '<button data-a="img" title="Copy the area as an image">🖼</button><button data-a="pdf" title="Export the area to PDF">📄</button>' +
    '<button data-a="del" title="Delete the selection">🗑</button><button data-a="x" title="Deselect">✕</button>';
  host.appendChild(selBar);
  const dlg = hEl('div'); dlg.id = 'pDlg'; dlg.hidden = true; dlg.setAttribute('data-pui', '1'); document.body.appendChild(dlg);
  [pnt, pop, selBar].forEach(n => ['pointerdown', 'pointerup', 'pointermove', 'pointercancel', 'wheel'].forEach(t => n.addEventListener(t, e => e.stopPropagation())));
  const pCol = pnt.querySelector('#pCol'), pPre = pnt.querySelector('#pPre'), pRec = pnt.querySelector('#pRec'), pFin = pnt.querySelector('#pFin');
  const paintBtn = hEl('button', '', '🖌'); paintBtn.id = 'paintBtn'; paintBtn.title = 'Painting tools';
  tbar.insertBefore(paintBtn, document.getElementById('menuBtn'));

  /* ---------- state ---------- */
  let open = false, tool = 'hand', lastTool = 'pen', popKind = '';
  let strokes = [], nextSid = 1, sel = null, lift = new Set();
  let act = null;                                         // one lasso / eraser gesture at a time
  const live = new Map();                                 // pen strokes being drawn right now, one per touch
  let quietUntil = 0, chromeK = -1, dimK = null;

  /* ---------- the two bitmaps ---------- */
  let W = 1, H = 1, DPR = 1, mx = 0, my = 0, bctx = null, lctx = null, rv = { x: 0, y: 0, k: 1 }, lastR = 0;
  const sameView = () => rv.x === view.x && rv.y === view.y && rv.k === view.k;
  function size() {
    const r = host.getBoundingClientRect();
    W = Math.max(1, Math.round(r.width)); H = Math.max(1, Math.round(r.height));
    mx = Math.round(W * MARG); my = Math.round(H * MARG);
    let d = Math.min(2, window.devicePixelRatio || 1);
    while (d > 1 && (W + 2 * mx) * (H + 2 * my) * d * d > 9e6) d -= 0.25;
    DPR = d;
    base.width = Math.round((W + 2 * mx) * d); base.height = Math.round((H + 2 * my) * d);
    base.style.width = (W + 2 * mx) + 'px'; base.style.height = (H + 2 * my) + 'px';
    base.style.left = -mx + 'px'; base.style.top = -my + 'px';
    liveC.width = Math.round(W * d); liveC.height = Math.round(H * d);
    liveC.style.width = W + 'px'; liveC.style.height = H + 'px';
        bctx = base.getContext('2d'); lctx = liveC.getContext('2d', { desynchronized: true });
    laserC.width = Math.round(W * d); laserC.height = Math.round(H * d);
    laserC.style.width = W + 'px'; laserC.style.height = H + 'px';
    zctx = laserC.getContext('2d'); lzSoon();

    renderBase(); liveSoon();
  }
  function sty(ctx, s) {
    ctx.globalAlpha = s.o * (dimK ? dimK(s) : 1); ctx.strokeStyle = s.c; ctx.lineWidth = s.w;
    ctx.lineCap = s.k === 'hl' ? 'butt' : 'round'; ctx.lineJoin = 'round';
  }
  function buildPath(p) {
    const path = new Path2D(), n = p.length / 2;
    if (n < 1) return path;
    path.moveTo(p[0], p[1]);
    if (n === 1) { path.lineTo(p[0] + 0.01, p[1]); return path; }
    if (n === 2) { path.lineTo(p[2], p[3]); return path; }
    for (let i = 1; i < n - 1; i++) path.quadraticCurveTo(p[2 * i], p[2 * i + 1], (p[2 * i] + p[2 * i + 2]) / 2, (p[2 * i + 1] + p[2 * i + 3]) / 2);
    path.lineTo(p[2 * n - 2], p[2 * n - 1]);
    return path;
  }
  const pathOf = s => s.path || (s.path = buildPath(s.pts));
  const touchS = s => { s.bb = null; s.ser = null; s.path = null; };
  function bb(s) {
    if (!s.bb) {
      let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9; const p = s.pts;
      for (let i = 0; i < p.length; i += 2) { if (p[i] < x0) x0 = p[i]; if (p[i] > x1) x1 = p[i]; if (p[i + 1] < y0) y0 = p[i + 1]; if (p[i + 1] > y1) y1 = p[i + 1]; }
      s.bb = { x0, y0, x1, y1 };
    }
    return s.bb;
  }
  function renderBase() {
    if (!bctx) return;
    rv = { x: view.x, y: view.y, k: view.k }; lastR = performance.now();
    base.style.transform = 'translate3d(0,0,0)';
    bctx.setTransform(1, 0, 0, 1, 0, 0); bctx.clearRect(0, 0, base.width, base.height);
    if (!strokes.length) return;
    const k = view.k;
    bctx.setTransform(k * DPR, 0, 0, k * DPR, (view.x + mx) * DPR, (view.y + my) * DPR);
    const x0 = (-mx - view.x) / k, x1 = (W + mx - view.x) / k, y0 = (-my - view.y) / k, y1 = (H + my - view.y) / k;
    for (const s of strokes) {
      if (lift.size && lift.has(s.id)) continue;
      const b = bb(s), h = s.w;
      if (b.x1 + h < x0 || b.x0 - h > x1 || b.y1 + h < y0 || b.y0 - h > y1) continue;
      sty(bctx, s); bctx.stroke(pathOf(s));
    }
  }
  // repaints only a small world rectangle of the committed ink (used by the eraser)
  function renderRegion(b) {
    if (!bctx) return;
    if (!sameView()) { renderBase(); return; }
    const k = view.k, pad = 3;
    const x0 = clamp(Math.floor(((b.x0 * k + view.x + mx) - pad) * DPR), 0, base.width), y0 = clamp(Math.floor(((b.y0 * k + view.y + my) - pad) * DPR), 0, base.height);
    const x1 = clamp(Math.ceil(((b.x1 * k + view.x + mx) + pad) * DPR), 0, base.width), y1 = clamp(Math.ceil(((b.y1 * k + view.y + my) + pad) * DPR), 0, base.height);
    if (x1 <= x0 || y1 <= y0) return;
    bctx.save();
    bctx.setTransform(1, 0, 0, 1, 0, 0); bctx.beginPath(); bctx.rect(x0, y0, x1 - x0, y1 - y0); bctx.clip(); bctx.clearRect(x0, y0, x1 - x0, y1 - y0);
    bctx.setTransform(k * DPR, 0, 0, k * DPR, (view.x + mx) * DPR, (view.y + my) * DPR);
    for (const s of strokes) {
      if (lift.size && lift.has(s.id)) continue;
      const q = bb(s), h = s.w;
      if (q.x1 + h < b.x0 || q.x0 - h > b.x1 || q.y1 + h < b.y0 || q.y0 - h > b.y1) continue;
      sty(bctx, s); bctx.stroke(pathOf(s));
    }
    bctx.restore();
  }
  let lraf = 0;
  const liveSoon = () => { if (!lraf) lraf = requestAnimationFrame(drawLive); };
  function drawLive() {
    lraf = 0;
    if (!lctx) return;
    lctx.setTransform(1, 0, 0, 1, 0, 0); lctx.clearRect(0, 0, liveC.width, liveC.height);
    if (!live.size && !lift.size) return;
    lctx.setTransform(view.k * DPR, 0, 0, view.k * DPR, view.x * DPR, view.y * DPR);
    if (lift.size) for (const s of strokes) if (lift.has(s.id)) { sty(lctx, s); lctx.stroke(pathOf(s)); }
    live.forEach(a => {
      const s = a.s, p = s.pts, n = p.length;
      sty(lctx, s);
      if (n < 4) { lctx.beginPath(); lctx.moveTo(p[0], p[1]); lctx.lineTo(p[0] + 0.01, p[1]); lctx.stroke(); return; }
      lctx.stroke(a.pc);
      lctx.beginPath(); lctx.moveTo(a.ex, a.ey); lctx.lineTo(p[n - 2], p[n - 1]); lctx.stroke();
    });
  }
  // the committed bitmap rides on a CSS transform while the view changes, and is repainted when things settle
  let vT = 0;
  function baseXform() {
    const s = view.k / rv.k, tx = view.x - rv.x * s + mx * (1 - s), ty = view.y - rv.y * s + my * (1 - s);
    base.style.transform = 'translate3d(' + tx + 'px,' + ty + 'px,0) scale(' + s + ')';
    const L = -mx + tx, T = -my + ty, R = L + (W + 2 * mx) * s, B = T + (H + 2 * my) * s;
    return L > 0.5 || T > 0.5 || R < W - 0.5 || B < H - 0.5 || s > 1.5 || s < 0.65;
  }
  function syncSvg() { gT.setAttribute('transform', 'translate(' + view.x + ' ' + view.y + ') scale(' + view.k + ')'); }
  function onView() {
    if (!bctx) return;
    syncSvg();
    clearTimeout(vT);
    if (!strokes.length) rv = { x: view.x, y: view.y, k: view.k };
    else {
      const need = baseXform();
      if (need && performance.now() - lastR > 80) renderBase();
      else vT = setTimeout(() => { if (!sameView()) renderBase(); }, need ? 90 : 140);
    }
        if (live.size || lift.size) liveSoon();
    if (lz.size || lzLines.length || lzGhosts.length) lzSoon();

    if (sel) { if (chromeK !== view.k) chrome(); else placeSelBar(); }
  }
  function onRender() { if (sel && sel.b.size) chrome(); }

  /* ---------- strokes and saving ---------- */
  function pathD(p) {
    const n = p.length / 2;
    if (n < 1) return '';
    if (n === 1) return 'M' + p[0] + ' ' + p[1] + 'h0.01';
    let d = 'M' + p[0] + ' ' + p[1];
    if (n === 2) return d + 'L' + p[2] + ' ' + p[3];
    for (let i = 1; i < n - 1; i++) d += 'Q' + p[2 * i] + ' ' + p[2 * i + 1] + ' ' + (p[2 * i] + p[2 * i + 2]) / 2 + ' ' + (p[2 * i + 1] + p[2 * i + 3]) / 2;
    return d + 'L' + p[2 * n - 2] + ' ' + p[2 * n - 1];
  }
  // each stroke is turned into its saved form once and cached
  function serOf(s) { return s.ser || (s.ser = { i: s.id, k: s.k, c: s.c, w: Math.round(s.w * 100) / 100, o: s.o, p: s.pts.map(r1) }); }
  function getInk() { return strokes.length ? { s: strokes.map(serOf) } : undefined; }
  function setInk(st) {
    clearSel();
    const list = [];
    if (st && st.s) st.s.forEach(o => list.push({ id: o.i, k: o.k, c: o.c, w: o.w, o: o.o, pts: o.p.slice(), bb: null, ser: o, path: null }));

    nextSid = Math.max(nextSid, list.reduce((m, s) => Math.max(m, s.id), 0) + 1);
    strokes = list; renderBase();
  }
  function inkBounds() {
    let b = null;
    strokes.forEach(s => {
      const q = bb(s), h = s.w / 2;
      b = b ? { x0: Math.min(b.x0, q.x0 - h), y0: Math.min(b.y0, q.y0 - h), x1: Math.max(b.x1, q.x1 + h), y1: Math.max(b.y1, q.y1 + h) } : { x0: q.x0 - h, y0: q.y0 - h, x1: q.x1 + h, y1: q.y1 + h };
    });
    return b;
  }
  function inkDraw(g) {
    strokes.forEach(s => {
      const el = svgEl('path', { fill: 'none', 'stroke-linejoin': 'round', 'stroke-linecap': s.k === 'hl' ? 'butt' : 'round', d: pathD(s.pts), stroke: s.c, 'stroke-width': s.w });
      if (s.o < 1) el.setAttribute('stroke-opacity', s.o);
      g.appendChild(el);
    });
  }
  window.MMP = {
        get: getInk, set: setInk, bounds: inkBounds, draw: inkDraw, onView, onRender,
    flush: flushNow, hard: () => live.size > 0 || !!act,
    redraw: () => renderBase(), bbox: bb, selIds: () => (sel ? [...sel.b] : []),
    setDim: f => { dimK = f; renderBase(); liveSoon(); },

        busy: () => live.size > 0 || lz.size > 0 || !!act || performance.now() < quietUntil

  };

  /* ---------- recent colours, written lazily so a finished stroke costs nothing ---------- */
  let recT = 0, recPending = null;
  function addRecent(c) {
    if (P.recent[0] === c) return;
    P.recent = [c].concat(P.recent.filter(x => x !== c)).slice(0, 8); save(); renderRecents();
  }
  function noteColor(c) { recPending = c; clearTimeout(recT); recT = setTimeout(() => addRecent(recPending), 1500); }

  /* ---------- pen: one stroke per touch, drawn the moment the stylus lands ---------- */
  function beginStroke(a, x, y, from) {
    const m = STY[P.style];
    a.s = from
      ? { id: nextSid++, k: from.k, c: from.c, w: from.w, o: from.o, pts: [x, y], bb: null, ser: null, path: null }
      : { id: nextSid++, k: P.style, c: P.color, w: P.width * m.w / view.k, o: m.o, pts: [f2(x), f2(y)], bb: null, ser: null, path: null };
    a.ex = a.s.pts[0]; a.ey = a.s.pts[1];
    a.pc = new Path2D(); a.pc.moveTo(a.ex, a.ey);
  }
  // adds one sample and extends the curve by one segment (no rebuilding)
  function addPt(a, wx, wy, min) {
    const p = a.s.pts, n = p.length;
    if (Math.hypot(wx - p[n - 2], wy - p[n - 1]) < min) return false;
    const x = f2(wx), y = f2(wy);
    if (n >= 4) {
      const qx = (p[n - 2] + x) / 2, qy = (p[n - 1] + y) / 2;
      a.pc.quadraticCurveTo(p[n - 2], p[n - 1], qx, qy); a.ex = qx; a.ey = qy;
    }
    p.push(x, y); a.s.bb = null; a.s.ser = null; a.s.path = null;
    return true;
  }
  function commitStroke(s) {
    s.path = null; strokes.push(s);
    if (sameView() && bctx) {
      bctx.setTransform(view.k * DPR, 0, 0, view.k * DPR, (view.x + mx) * DPR, (view.y + my) * DPR);
      sty(bctx, s); bctx.stroke(pathOf(s));
    } else renderBase();
  }
  function rollover(a) {                                  // very long scribbles are cut into pieces so drawing stays cheap
    const p = a.s.pts, n = p.length, lx = p[n - 2], ly = p[n - 1], old = a.s;
    commitStroke(old);
    beginStroke(a, lx, ly, old);
    drawLive();
  }
  function startPen(e, p, w, r) {
    if (!pop.hidden) closePop();
    const a = { id: e.pointerId, ptype: e.pointerType, t0: performance.now(), len: 0, moved: false, sp: { x: p.x, y: p.y }, raw: { x: p.x, y: p.y }, r, pc: null, ex: 0, ey: 0, s: null, g: null };
    beginStroke(a, w.x, w.y, null);
    if (P.swap && e.pointerType === 'touch') {            // two touches landing together = the swap gesture
      for (const o of live.values()) {
        if (o.ptype === 'touch' && !o.moved && a.t0 - o.t0 < 200) { const g = o.g || { ids: [], up: 0, ok: true }; o.g = g; a.g = g; }
      }
    }
    live.set(e.pointerId, a);
    liveSoon();
  }
  function penMove(a, e) {
    const r = a.r, f = 1 - 0.9 * P.smooth, sm = P.smooth > 0.001, min = 0.3 / view.k;
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : null, evs = list && list.length ? list : [e];
    let any = false;
    for (const ev of evs) {
      const px = ev.clientX - r.left, py = ev.clientY - r.top;
      a.len += Math.hypot(px - a.raw.x, py - a.raw.y); a.raw.x = px; a.raw.y = py;
      if (sm) { a.sp.x += (px - a.sp.x) * f; a.sp.y += (py - a.sp.y) * f; }       // stroke stabilization
      else { a.sp.x = px; a.sp.y = py; }                                           // zero = the exact stylus position
      if (addPt(a, (a.sp.x - view.x) / view.k, (a.sp.y - view.y) / view.k, min)) any = true;
    }
    if (a.len > 9) a.moved = true;
    if (any) { if (a.s.pts.length >= CHUNK * 2) rollover(a); liveSoon(); }
  }
  function endPen(a) {
    const min = 0.3 / view.k;
    if (P.smooth > 0.001) {                                // let the smoothed pen catch up with the stylus
      for (let i = 0; i < 14; i++) {
        const dx = a.raw.x - a.sp.x, dy = a.raw.y - a.sp.y;
        if (Math.hypot(dx, dy) < 0.6) break;
        a.sp.x += dx * 0.4; a.sp.y += dy * 0.4;
        addPt(a, (a.sp.x - view.x) / view.k, (a.sp.y - view.y) / view.k, min);
      }
    }
    addPt(a, (a.raw.x - view.x) / view.k, (a.raw.y - view.y) / view.k, 0.05 / view.k);
    const s = a.s;
    commitStroke(s); drawLive();                           // base and live are updated in the same tick: no flash
    quietUntil = performance.now() + 900;
    X.touch(); noteColor(s.c);
    if (a.g) {
      const g = a.g, now = performance.now();
      g.ids.push(s.id); g.up++;
      if (a.moved || now - a.t0 > 420) g.ok = false;
      if (g.up === 2 && g.ok && P.swap) {                  // a quick two-touch tap: discard the two dots and swap tools
        strokes = strokes.filter(q => g.ids.indexOf(q.id) < 0); renderBase();
        buzz(); setTool(tool === 'eraser' ? 'pen' : 'eraser');
        stat(tool === 'eraser' ? 'Switched to the eraser. Tap with two touches again to go back to the pen.' : 'Switched to the pen.');
      }
    }
  }

  /* ---------- eraser ---------- */
  const uni = (a, b, h) => {
    const q = { x0: b.x0 - h, y0: b.y0 - h, x1: b.x1 + h, y1: b.y1 + h };
    return a ? { x0: Math.min(a.x0, q.x0), y0: Math.min(a.y0, q.y0), x1: Math.max(a.x1, q.x1), y1: Math.max(a.y1, q.y1) } : q;
  };
  function startErase(e, p, w, r) {
    const cur = svgEl('circle', { fill: 'rgba(255,255,255,.35)', stroke: '#666', 'stroke-width': 1 / view.k, r: P.eraseSize / 2 / view.k, cx: w.x, cy: w.y });
    gT.appendChild(cur); syncSvg();
    act = { id: e.pointerId, kind: 'erase', r, last: w, hit: new Set(), changed: false, cur, dirty: null };
    eraseAt(w.x, w.y); flushErase();
  }
  function eraseAt(x, y) {
    const r = P.eraseSize / 2 / view.k, out = []; let changed = false;
    for (const s of strokes) {
      if (lift.has(s.id)) { out.push(s); continue; }
      const b = bb(s), m = r + s.w / 2;
      if (x < b.x0 - m || x > b.x1 + m || y < b.y0 - m || y > b.y1 + m) { out.push(s); continue; }
      const pts = s.pts, n = pts.length / 2, flags = new Uint8Array(n); let any = false;
      for (let i = 0; i < n; i++) { const dx = pts[2 * i] - x, dy = pts[2 * i + 1] - y; if (dx * dx + dy * dy <= m * m) { flags[i] = 1; any = true; } }
      if (!any) { out.push(s); continue; }
      changed = true; act.dirty = uni(act.dirty, b, s.w);
      if (P.whole) continue;
      let run = [];
      const flush = () => { if (run.length >= 4) out.push({ id: nextSid++, k: s.k, c: s.c, w: s.w, o: s.o, pts: run, bb: null, ser: null, path: null }); run = []; };
      for (let i = 0; i < n; i++) { if (flags[i]) flush(); else run.push(pts[2 * i], pts[2 * i + 1]); }
      flush();
    }
    if (changed) { strokes = out; act.changed = true; }
    if (!P.protect) {                                      // protection off: typed boxes can be erased too
      X.nodes().forEach(n => {
        if (X.isMain(n)) return;
        if (Math.abs(x - n.x) <= n.w / 2 + r && Math.abs(y - n.y) <= n.h / 2 + r) act.hit.add(n.id);
      });
    }
  }
  function flushErase() { if (act.dirty) { renderRegion(act.dirty); act.dirty = null; } }
  function eraseMove(e) {
    const r = P.eraseSize / 2 / view.k, rc = act.r;
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : null, evs = list && list.length ? list : [e];
    for (const ev of evs) {
      const w = { x: (ev.clientX - rc.left - view.x) / view.k, y: (ev.clientY - rc.top - view.y) / view.k };
      const d = Math.hypot(w.x - act.last.x, w.y - act.last.y), n = Math.max(1, Math.ceil(d / (r * 0.6)));
      for (let i = 1; i <= n; i++) eraseAt(act.last.x + (w.x - act.last.x) * i / n, act.last.y + (w.y - act.last.y) * i / n);
      act.last = w;
      act.cur.setAttribute('cx', w.x); act.cur.setAttribute('cy', w.y);
    }
    flushErase();
  }
  function eraseUp() {
    act.cur.remove();
    if (act.changed) X.touch();
    if (act.hit.size) {
      const c = X.deleteBoxes([...act.hit]);
      stat(c ? 'Erased ' + c + ' box' + (c > 1 ? 'es' : '') + ' (Undo ↶ brings them back).' : 'Nothing to erase.');
    }
  }

  /* ---------- lasso ---------- */
  function pip(x, y, poly) {
    let c = false;
    for (let i = 0, j = poly.length - 2; i < poly.length; j = i, i += 2) {
      const xi = poly[i], yi = poly[i + 1], xj = poly[j], yj = poly[j + 1];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
    }
    return c;
  }
  function segInt(ax, ay, bx, by, cx, cy, dx, dy) {
    const o = (px, py, qx, qy, rx, ry) => (qx - px) * (ry - py) - (qy - py) * (rx - px);
    return o(ax, ay, bx, by, cx, cy) * o(ax, ay, bx, by, dx, dy) < 0 && o(cx, cy, dx, dy, ax, ay) * o(cx, cy, dx, dy, bx, by) < 0;
  }
  function boxCorners(n) { const x0 = n.x - n.w / 2, x1 = n.x + n.w / 2, y0 = n.y - n.h / 2, y1 = n.y + n.h / 2; return [x0, y0, x1, y0, x1, y1, x0, y1]; }
  function boxTouch(n, poly) {                             // a partial loop is enough
    const c = boxCorners(n);
    for (let i = 0; i < 8; i += 2) if (pip(c[i], c[i + 1], poly)) return true;
    for (let i = 0; i < poly.length; i += 2) if (Math.abs(poly[i] - n.x) <= n.w / 2 && Math.abs(poly[i + 1] - n.y) <= n.h / 2) return true;
    for (let i = 0, j = poly.length - 2; i < poly.length; j = i, i += 2) {
      for (let k = 0; k < 8; k += 2) { const k2 = (k + 2) % 8; if (segInt(poly[j], poly[j + 1], poly[i], poly[i + 1], c[k], c[k + 1], c[k2], c[k2 + 1])) return true; }
    }
    return false;
  }
  function lassoSelect(poly) {
    const f = P.filt, S = new Set(), B = new Set();
    let px0 = 1e9, py0 = 1e9, px1 = -1e9, py1 = -1e9;
    for (let i = 0; i < poly.length; i += 2) { px0 = Math.min(px0, poly[i]); px1 = Math.max(px1, poly[i]); py0 = Math.min(py0, poly[i + 1]); py1 = Math.max(py1, poly[i + 1]); }
    if (!f.boxes) {
      strokes.forEach(s => {
        if (s.k === 'hl' ? !f.hl : !f.ink) return;
        const b = bb(s);
        if (b.x1 < px0 || b.x0 > px1 || b.y1 < py0 || b.y0 > py1) return;
        const n = s.pts.length / 2; let inside = 0;
        for (let i = 0; i < n; i++) if (pip(s.pts[2 * i], s.pts[2 * i + 1], poly)) inside++;
        if (n && (P.snap ? inside / n >= 0.2 : inside === n)) S.add(s.id);        // auto-snap: a partial loop selects the whole stroke
      });
    }
    X.nodes().forEach(n => {
      if (f.boxes) { if (boxTouch(n, poly)) B.add(n.id); }
      else if (f.text) { const c = boxCorners(n); if (pip(c[0], c[1], poly) && pip(c[2], c[3], poly) && pip(c[4], c[5], poly) && pip(c[6], c[7], poly)) B.add(n.id); }
    });
    return S.size || B.size ? { s: S, b: B } : null;
  }
  function startLasso(e, p, w, r) {
    const k = view.k;
    if (sel) {
      const sb = sbounds(), hit = (hx, hy) => Math.hypot(hx * k + view.x - p.x, hy * k + view.y - p.y) < 26;
      if (sb) {
        const cx = (sb.x0 + sb.x1) / 2, cy = (sb.y0 + sb.y1) / 2;
        if (hit(cx, sb.y0 - 30 / k)) { act = { id: e.pointerId, kind: 'rot', r, c: { x: cx, y: cy }, a0: Math.atan2(w.y - cy, w.x - cx), orig: snapOrig() }; return; }
        if (hit(sb.x1, sb.y1)) { act = { id: e.pointerId, kind: 'scl', r, c: { x: cx, y: cy }, d0: Math.max(8 / k, Math.hypot(w.x - cx, w.y - cy)), orig: snapOrig() }; return; }
      }
      const u = ubounds(), m = 8 / k;
      if (u && w.x >= u.x0 - m && w.x <= u.x1 + m && w.y >= u.y0 - m && w.y <= u.y1 + m) {
        act = { id: e.pointerId, kind: 'move', r, p0: p, w0: w, orig: snapOrig(), group: false, moved: false, dx: 0, dy: 0, t: 0 };
        act.t = setTimeout(() => {                        // press-and-hold: boxes move together with the ink
          if (act && act.kind === 'move' && !act.moved) { act.group = true; buzz(); stat(sel && sel.b.size ? 'Group move: drag to move all the selected boxes together.' : 'Drag to move the selection.'); }
        }, 450);
        return;
      }
      clearSel();
    }
    syncSvg();
    const el = svgEl('path', { fill: 'rgba(42,157,143,.10)', stroke: '#2A9D8F', 'stroke-width': 2 / k, 'stroke-dasharray': (7 / k) + ' ' + (5 / k), 'stroke-linejoin': 'round' });
    gT.appendChild(el);
    act = { id: e.pointerId, kind: 'loop', r, pts: [w.x, w.y], d: 'M' + w.x + ' ' + w.y, el };
  }
  function loopMove(e) {
    const rc = act.r, list = e.getCoalescedEvents ? e.getCoalescedEvents() : null, evs = list && list.length ? list : [e];
    for (const ev of evs) {
      const x = (ev.clientX - rc.left - view.x) / view.k, y = (ev.clientY - rc.top - view.y) / view.k, n = act.pts.length;
      if (Math.hypot(x - act.pts[n - 2], y - act.pts[n - 1]) > 1.5 / view.k) { act.pts.push(x, y); act.d += 'L' + f2(x) + ' ' + f2(y); }
    }
    act.el.setAttribute('d', act.d + 'Z');
  }
  function loopUp() {
    act.el.remove();
    if (act.pts.length < 8) { clearSel(); return; }
    const s = lassoSelect(act.pts);
    if (!s) { clearSel(); stat('Nothing inside that loop for the current filters (tap the lasso again to change them).'); return; }
    sel = s; setLift(s.s); updateSelBar(); chrome();
    stat('Selected ' + (s.s.size ? s.s.size + ' stroke' + (s.s.size > 1 ? 's' : '') : '') + (s.s.size && s.b.size ? ' and ' : '') + (s.b.size ? s.b.size + ' box' + (s.b.size > 1 ? 'es' : '') : '') +
      '. Round handle = rotate, square = resize. Hold inside to move boxes together.');
  }

  /* ---------- selection ---------- */
  // selected ink is lifted onto the live layer so moving or rotating it never repaints the whole picture
  function setLift(set) { lift = new Set(set); renderBase(); liveSoon(); }
  function clearSel() {
    const had = lift.size;
    sel = null; gC.removeAttribute('transform');
    while (gC.firstChild) gC.removeChild(gC.firstChild);
    selBar.hidden = true;
    if (had) { lift = new Set(); renderBase(); liveSoon(); }
    if (popKind === 'recolor') closePop();
  }
  const snapOrig = () => { const m = new Map(strokes.map(s => [s.id, s])); return sel ? [...sel.s].map(id => m.get(id)).filter(Boolean).map(s => ({ s, pts: s.pts.slice(), w: s.w })) : []; };
  function sbounds() {
    if (!sel || !sel.s.size) return null;
    let b = null;
    strokes.forEach(s => {
      if (!sel.s.has(s.id)) return;
      const q = bb(s), h = s.w / 2;
      b = b ? { x0: Math.min(b.x0, q.x0 - h), y0: Math.min(b.y0, q.y0 - h), x1: Math.max(b.x1, q.x1 + h), y1: Math.max(b.y1, q.y1 + h) } : { x0: q.x0 - h, y0: q.y0 - h, x1: q.x1 + h, y1: q.y1 + h };
    });
    return b;
  }
  function selBoxes() { return sel && sel.b.size ? X.nodes().filter(n => sel.b.has(n.id)) : []; }
  function bbounds() {
    const l = selBoxes(); if (!l.length) return null;
    return l.reduce((b, n) => ({ x0: Math.min(b.x0, n.x - n.w / 2), y0: Math.min(b.y0, n.y - n.h / 2), x1: Math.max(b.x1, n.x + n.w / 2), y1: Math.max(b.y1, n.y + n.h / 2) }), { x0: 1e9, y0: 1e9, x1: -1e9, y1: -1e9 });
  }
  function ubounds() {
    const a = sbounds(), b = bbounds();
    if (!a) return b; if (!b) return a;
    return { x0: Math.min(a.x0, b.x0), y0: Math.min(a.y0, b.y0), x1: Math.max(a.x1, b.x1), y1: Math.max(a.y1, b.y1) };
  }
  function chrome() {
    while (gC.firstChild) gC.removeChild(gC.firstChild);
    chromeK = view.k; syncSvg();
    if (!sel) return;
    const k = view.k, sb = sbounds(), boxes = selBoxes(), u = ubounds();
    if (!u) { clearSel(); return; }
    boxes.forEach(n => gC.appendChild(svgEl('rect', { x: n.x - n.w / 2 - 3, y: n.y - n.h / 2 - 3, width: n.w + 6, height: n.h + 6, rx: 12, fill: 'rgba(42,157,143,.10)', stroke: '#2A9D8F', 'stroke-width': 2.5 / k })));
    gC.appendChild(svgEl('rect', { x: u.x0, y: u.y0, width: u.x1 - u.x0, height: u.y1 - u.y0, fill: 'none', stroke: '#2A9D8F', 'stroke-width': 1.6 / k, 'stroke-dasharray': (6 / k) + ' ' + (4 / k) }));
    if (sb) {
      const cx = (sb.x0 + sb.x1) / 2;
      gC.appendChild(svgEl('line', { x1: cx, y1: sb.y0, x2: cx, y2: sb.y0 - 30 / k, stroke: '#2A9D8F', 'stroke-width': 1.6 / k }));
      gC.appendChild(svgEl('circle', { cx, cy: sb.y0 - 30 / k, r: 11 / k, fill: '#fff', stroke: '#2A9D8F', 'stroke-width': 3 / k }));
      gC.appendChild(svgEl('rect', { x: sb.x1 - 9 / k, y: sb.y1 - 9 / k, width: 18 / k, height: 18 / k, rx: 3 / k, fill: '#fff', stroke: '#2A9D8F', 'stroke-width': 3 / k }));
    }
    placeSelBar();
  }
  function placeSelBar() {
    const u = ubounds(); if (!u) return;
    const handles = !!sbounds(), k = view.k, r = host.getBoundingClientRect();
    selBar.hidden = false;
    const bw = selBar.offsetWidth || 260, bh = selBar.offsetHeight || 50;
    const x0 = u.x0 * k + view.x, x1 = u.x1 * k + view.x, y0 = u.y0 * k + view.y, y1 = u.y1 * k + view.y;
    let top = y0 - bh - (handles ? 46 : 12);
    if (top < 8) top = y1 + 14;
    selBar.style.left = clamp((x0 + x1) / 2 - bw / 2, 8, Math.max(8, r.width - bw - 8)) + 'px';
    selBar.style.top = clamp(top, 8, Math.max(8, r.height - bh - 8)) + 'px';
  }
  function updateSelBar() {
    selBar.querySelector('[data-a="col"]').hidden = !(sel && sel.s.size);
    selBar.querySelector('[data-a="cover"]').hidden = !(sel && sel.b.size);
    if (window.MMM && window.MMM.onSel) window.MMM.onSel(selBar, sel);
  }
  function applyX(orig, fn, sc) {
    orig.forEach(o => {
      const n = o.pts.length, out = new Array(n);
      for (let i = 0; i < n; i += 2) { const q = fn(o.pts[i], o.pts[i + 1]); out[i] = q[0]; out[i + 1] = q[1]; }
      o.s.pts = out; o.s.w = o.w * sc; touchS(o.s);
    });
    liveSoon();
  }
  function wOf(e) { const r = act.r; return { x: (e.clientX - r.left - view.x) / view.k, y: (e.clientY - r.top - view.y) / view.k }; }
  function selMove(e) {
    const w = wOf(e), r = act.r;
    if (!act.moved && Math.hypot(e.clientX - r.left - act.p0.x, e.clientY - r.top - act.p0.y) > 6) act.moved = true;
    if (!act.moved && !act.group) return;
    act.dx = w.x - act.w0.x; act.dy = w.y - act.w0.y;
    if (act.orig.length) {
      act.orig.forEach(o => { o.s.pts = o.pts.map((v, i) => v + (i % 2 ? act.dy : act.dx)); touchS(o.s); });
      liveSoon();
    }
    if (act.group) gC.setAttribute('transform', 'translate(' + act.dx + ' ' + act.dy + ')'); else chrome();
  }
  function selUp() {
    clearTimeout(act.t);
    if (!act.moved && !act.group) { if (!act.orig.length && sel && sel.b.size) stat('Hold the selection for a moment, then drag, to move the boxes.'); return; }
    gC.removeAttribute('transform');
    if (act.group && sel && sel.b.size && (Math.abs(act.dx) > 0.5 || Math.abs(act.dy) > 0.5)) X.moveBoxes([...sel.b], act.dx, act.dy);
    if (act.orig.length) X.touch();
    chrome();
  }
  function xformMove(e) {
    const w = wOf(e), c = act.c;
    if (act.kind === 'scl') {
      const f = clamp(Math.hypot(w.x - c.x, w.y - c.y) / act.d0, 0.1, 10);
      applyX(act.orig, (x, y) => [c.x + (x - c.x) * f, c.y + (y - c.y) * f], f);
    } else {
      const a = Math.atan2(w.y - c.y, w.x - c.x) - act.a0, cs = Math.cos(a), sn = Math.sin(a);
      applyX(act.orig, (x, y) => [c.x + (x - c.x) * cs - (y - c.y) * sn, c.y + (x - c.x) * sn + (y - c.y) * cs], 1);
    }
    chrome();
  }
  function recolorSel(c) {
    if (!sel) return;
    strokes.forEach(s => { if (sel.s.has(s.id)) { s.c = c; s.ser = null; } });
    liveSoon(); noteColor(c); X.touch(); closePop();
  }
  selBar.addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b || !sel) return;
    const a = b.dataset.a;
    if (a === 'x') clearSel();
    else if (a === 'col') { if (popKind === 'recolor') closePop(); else openPop('recolor'); }
    else if (a === 'cover') { const any = X.coverBoxes([...sel.b]); stat(any ? 'Covered the selected boxes.' : 'Uncovered the selected boxes.'); }
    else if (a === 'del') {
      const ids = [...sel.b], gone = new Set(sel.s);
      clearSel();
      if (gone.size) { strokes = strokes.filter(s => !gone.has(s.id)); renderBase(); X.touch(); }
      if (ids.length) { const c = X.deleteBoxes(ids); stat(c ? 'Deleted ' + c + ' box' + (c > 1 ? 'es' : '') + ' (the centre box is never deleted).' : 'The centre box can not be deleted.'); }
    }
    else if (a === 'img') copyImage();
    else if (a === 'pdf') exportPdf();
  });

  /* ---------- copy as image / export the selected area to PDF ---------- */
  function regionSvg(u) {
    const m = 14, x = u.x0 - m, y = u.y0 - m, w = Math.max(20, u.x1 - u.x0 + 2 * m), h = Math.max(20, u.y1 - u.y0 + 2 * m);
    const src = document.getElementById('svg'), wg = src.querySelector(':scope > g'), df = src.querySelector(':scope > defs');
    const out = svgEl('svg', { xmlns: NS, width: w, height: h, viewBox: '0 0 ' + w + ' ' + h });
    out.appendChild(svgEl('rect', { x: 0, y: 0, width: w, height: h, fill: document.body.classList.contains('dark') ? '#12161c' : '#ffffff' }));
    if (df) out.appendChild(df.cloneNode(true));
    const g = svgEl('g', { transform: 'translate(' + (-x) + ' ' + (-y) + ')' });
    if (wg) {
      const c = wg.cloneNode(true); c.removeAttribute('transform');
      c.querySelectorAll('.dim,.semi').forEach(el => el.classList.remove('dim', 'semi'));
      c.querySelectorAll('[style]').forEach(el => { el.style.filter = ''; el.style.cursor = ''; });
      g.appendChild(c);
    }
    const ig = svgEl('g'); inkDraw(ig); g.appendChild(ig);
    out.appendChild(g);
    return { svg: out, w, h };
  }
  function pngOf(r) {
    return new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => {
        const sc = Math.min(3, 4096 / Math.max(r.w, r.h)), c = document.createElement('canvas');
        c.width = Math.round(r.w * sc); c.height = Math.round(r.h * sc);
        const g = c.getContext('2d'); g.scale(sc, sc); g.drawImage(img, 0, 0, r.w, r.h);
        c.toBlob(b => (b ? res(b) : rej(new Error('png'))), 'image/png');
      };
      img.onerror = () => rej(new Error('img'));
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(r.svg));
    });
  }
  async function copyImage() {
    const u = ubounds(); if (!u) return;
    let blob;
    try { blob = await pngOf(regionSvg(u)); } catch (e) { stat('Could not make the picture.'); return; }
    try { await navigator.clipboard.write([new ClipboardItem({ 'image/png': blob })]); stat('Copied the selected area as an image.'); return; } catch (e) { /* try the next way */ }
    try {
      const f = new File([blob], 'mindmap-selection.png', { type: 'image/png' });
      if (navigator.canShare && navigator.canShare({ files: [f] })) { await navigator.share({ files: [f] }); stat('Shared the image.'); return; }
    } catch (e) { if (e && e.name === 'AbortError') return; }
    dlg.innerHTML = '<div class="card"><b>Selected area</b><img alt="selection" src="' + URL.createObjectURL(blob) + '"><small>Hold the picture, then tap Copy or Save to Photos.</small><div class="row"><button id="pDlgX" class="primary">Close</button></div></div>';
    dlg.hidden = false;
    dlg.querySelector('#pDlgX').onclick = () => { dlg.hidden = true; dlg.innerHTML = ''; };
  }
  async function exportPdf() {
    const u = ubounds(); if (!u) return;
    stat('Making the PDF…');
    try {
      const r = regionSvg(u), { jsPDF } = window.jspdf, W2 = Math.ceil(r.w), H2 = Math.ceil(r.h), s = Math.min(1, 19000 / Math.max(W2, H2));
      const holder = document.createElement('div');
      holder.style.cssText = 'position:fixed;left:-99999px;top:0;opacity:0;pointer-events:none';
      document.body.appendChild(holder); holder.appendChild(r.svg);
      const pdf = new jsPDF({ orientation: W2 >= H2 ? 'l' : 'p', unit: 'px', format: [W2 * s, H2 * s], hotfixes: ['px_scaling'] });
      const o = { x: 0, y: 0, width: W2 * s, height: H2 * s };
      if (typeof pdf.svg === 'function') await pdf.svg(r.svg, o); else await (window.svg2pdf.svg2pdf || window.svg2pdf)(r.svg, pdf, o);
      holder.remove();
      if (X.deliver) await X.deliver(pdf, 'mindmap_selection.pdf'); else pdf.save('mindmap_selection.pdf');
    } catch (err) { console.error(err); stat('PDF error: ' + err.message); }
  }

    /* ---------- laser pointer: a glowing dot, a short trail, or a line that fades when you stop ---------- */
  // Never saved, never an undo step, never in the PDF. Points are kept in map coordinates, so the laser stays on the same spot if the view moves.
  let zctx = null, zraf = 0, zT = 0, lzAct = 0, lzLines = [], lzGhosts = [];
  const lz = new Map();                                   // pointers driving a laser right now: id → state
  const lzRgb = {};
  const lzSoon = () => { if (!zraf) zraf = requestAnimationFrame(drawLaser); };
  function lzCol(c, a) {
    let q = lzRgb[c];
    if (!q) q = lzRgb[c] = [parseInt(c.substr(1, 2), 16), parseInt(c.substr(3, 2), 16), parseInt(c.substr(5, 2), 16)];
    return 'rgba(' + q[0] + ',' + q[1] + ',' + q[2] + ',' + a + ')';
  }
  // the pointer tip: a coloured glow around a white glowing core
  function lzDot(x, y, c, al) {
    const u = 1 / view.k;
    zctx.globalAlpha = 1;
    let g = zctx.createRadialGradient(x, y, 0, x, y, 26 * u);
    g.addColorStop(0, lzCol(c, 0.75 * al)); g.addColorStop(0.4, lzCol(c, 0.35 * al)); g.addColorStop(1, lzCol(c, 0));
    zctx.fillStyle = g; zctx.beginPath(); zctx.arc(x, y, 26 * u, 0, 6.2832); zctx.fill();
    zctx.fillStyle = lzCol(c, 0.95 * al); zctx.beginPath(); zctx.arc(x, y, 9 * u, 0, 6.2832); zctx.fill();
    g = zctx.createRadialGradient(x, y, 0, x, y, 8 * u);
    g.addColorStop(0, 'rgba(255,255,255,' + al + ')'); g.addColorStop(0.55, 'rgba(255,255,255,' + 0.9 * al + ')'); g.addColorStop(1, 'rgba(255,255,255,0)');
    zctx.fillStyle = g; zctx.beginPath(); zctx.arc(x, y, 8 * u, 0, 6.2832); zctx.fill();
  }
  // a fading tail: points older than LZ_TRAIL are dropped, newer ones are stronger and thicker. Returns true while something is left.
  function lzTrail(tr, c, now) {
    let i = 0;
    while (i < tr.length && now - tr[i + 2] > LZ_TRAIL) i += 3;
    if (i) tr.splice(0, i);
    const n = tr.length / 3;
    if (n < 1) return false;
    if (n >= 2) {
      const u = 1 / view.k, m = n - 1, G = Math.min(10, m);
      for (let pass = 0; pass < 3; pass++) {
        zctx.strokeStyle = pass === 2 ? '#ffffff' : c;
        for (let g = 0; g < G; g++) {
          const s0 = Math.floor(g * m / G), s1 = Math.floor((g + 1) * m / G);
          if (s1 <= s0) continue;
          const mid = tr[3 * ((s0 + s1 + 1) >> 1) + 2], al = 1 - (now - mid) / LZ_TRAIL;
          if (al <= 0) continue;
          zctx.globalAlpha = (pass === 0 ? 0.22 : pass === 1 ? 0.9 : 1) * al;
          zctx.lineWidth = (pass === 0 ? 22 : pass === 1 ? 9 : 3.4) * (0.3 + 0.7 * al) * u;
          zctx.beginPath(); zctx.moveTo(tr[3 * s0], tr[3 * s0 + 1]);
          for (let j = s0 + 1; j <= s1; j++) zctx.lineTo(tr[3 * j], tr[3 * j + 1]);
          zctx.stroke();
        }
      }
    }
    return true;
  }
  // a freehand laser line: glow, colour, white core
  function lzLine(L, fa) {
    const p = L.pts, n = p.length, u = 1 / view.k;
    let path = null;
    if (n >= 4) { path = new Path2D(L.pc); path.lineTo(p[n - 2], p[n - 1]); }
    const run = (w, col, al) => {
      zctx.strokeStyle = col; zctx.lineWidth = w * u; zctx.globalAlpha = al * fa;
      if (path) zctx.stroke(path);
      else { zctx.beginPath(); zctx.moveTo(p[0], p[1]); zctx.lineTo(p[0] + 0.01, p[1]); zctx.stroke(); }
    };
    run(22, L.c, 0.22); run(9, L.c, 0.9); run(3.4, '#ffffff', 1);
  }
  function lzAddPt(L, x, y) {
    const p = L.pts, n = p.length;
    if (Math.hypot(x - p[n - 2], y - p[n - 1]) < 0.8 / view.k) return;
    const fx = f2(x), fy = f2(y);
    if (n >= 4) { const qx = (p[n - 2] + fx) / 2, qy = (p[n - 1] + fy) / 2; L.pc.quadraticCurveTo(p[n - 2], p[n - 1], qx, qy); L.ex = qx; L.ey = qy; }
    p.push(fx, fy);
  }
  function drawLaser() {
    zraf = 0; clearTimeout(zT);
    if (!zctx) return;
    const now = performance.now(), k = view.k;
    zctx.setTransform(1, 0, 0, 1, 0, 0); zctx.clearRect(0, 0, laserC.width, laserC.height);
    if (!lz.size && !lzGhosts.length && !lzLines.length) return;
    zctx.setTransform(k * DPR, 0, 0, k * DPR, view.x * DPR, view.y * DPR);
    zctx.lineCap = 'round'; zctx.lineJoin = 'round';
    let again = false, drawing = false;
    lz.forEach(a => { if (a.ln) drawing = true; });
    if (drawing) lzAct = now;                              // a line is being drawn: not idle
    if (lzLines.length) {
      const idle = now - lzAct, fa = idle > LZ_IDLE ? 1 - (idle - LZ_IDLE) / LZ_FADE : 1;
      if (fa <= 0) lzLines = [];
      else {
        for (const L of lzLines) lzLine(L, fa);
        if (drawing || idle > LZ_IDLE) again = true;      // drawing, or fading out
        else zT = setTimeout(lzSoon, Math.max(30, LZ_IDLE - idle + 5));   // wait quietly until the 2.5 s are over
      }
    }
    if (lzGhosts.length) {
      lzGhosts = lzGhosts.filter(g => {
        if (g.mode === 'dot') {
          const al = 1 - (now - g.t0) / LZ_DOT;
          if (al <= 0) return false;
          lzDot(g.x, g.y, g.c, al); return true;
        }
        return lzTrail(g.tr, g.c, now);
      });
      if (lzGhosts.length) again = true;
    }
    lz.forEach(a => {
      if (a.mode === 'trail' && lzTrail(a.tr, a.c, now)) again = true;
      lzDot(a.x, a.y, a.c, 1);
    });
    if (again) lzSoon();
  }
  function startLaser(e, p, w, r) {
    if (!pop.hidden) closePop();
    const now = performance.now(), L = P.laser;
    const a = { id: e.pointerId, ptype: e.pointerType, mode: L.mode, c: L.color, hov: false, r, x: w.x, y: w.y, tr: [], ln: null };
    if (a.mode === 'trail') a.tr.push(w.x, w.y, now);
    else if (a.mode === 'line') {
      if (lzLines.length && now - lzAct > LZ_IDLE) lzLines = [];     // the old lines were already fading out
      a.ln = { c: a.c, pts: [f2(w.x), f2(w.y)], pc: new Path2D(), ex: w.x, ey: w.y };
      a.ln.pc.moveTo(w.x, w.y);
      lzLines.push(a.ln); lzAct = now;
    }
    lz.set(e.pointerId, a);
    lzSoon();
  }
  function laserMove(a, e) {
    if (a.hov && e.target.closest && e.target.closest(IGN)) { stopLaser(a.id); return; }
    const r = a.hov ? host.getBoundingClientRect() : a.r, now = performance.now();
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : null, evs = list && list.length ? list : [e];
    for (const ev of evs) {
      const x = (ev.clientX - r.left - view.x) / view.k, y = (ev.clientY - r.top - view.y) / view.k;
      a.x = x; a.y = y;
      if (a.mode === 'trail') a.tr.push(x, y, ev.timeStamp > 0 && ev.timeStamp <= now + 4 ? ev.timeStamp : now);
      else if (a.ln) lzAddPt(a.ln, x, y);
    }
    if (a.tr.length > 1500) a.tr.splice(0, a.tr.length - 1500);
    if (!a.hov) lzAct = now;
    lzSoon();
  }
  // a mouse or a hovering Apple Pencil shows the laser before it touches the screen
  function laserHover(e) {
    if (e.target.closest && e.target.closest(IGN)) { const h = lz.get(e.pointerId); if (h && h.hov) stopLaser(e.pointerId); return; }
    const r = host.getBoundingClientRect(), x = (e.clientX - r.left - view.x) / view.k, y = (e.clientY - r.top - view.y) / view.k;
    const a = { id: e.pointerId, ptype: e.pointerType, mode: P.laser.mode, c: P.laser.color, hov: true, r, x, y, tr: [], ln: null };
    if (a.mode === 'trail') a.tr.push(x, y, performance.now());
    lz.set(e.pointerId, a);
    lzSoon();
  }
  function stopLaser(id) {
    const a = lz.get(id); if (!a) return;
    lz.delete(id);
    if (!a.hov && a.ptype === 'pen') penLive = Math.max(0, penLive - 1);
    const now = performance.now();
    if (!a.hov) {
      if (a.mode === 'dot') lzGhosts.push({ mode: 'dot', c: a.c, x: a.x, y: a.y, t0: now });
      else if (a.mode === 'trail') lzGhosts.push({ mode: 'trail', c: a.c, tr: a.tr });
      else lzAct = now;                                    // a line stays until 2.5 s without input
    }
    lzSoon();
  }
  function releaseLasers() { [...lz.keys()].forEach(id => stopLaser(id)); }
  host.addEventListener('pointerleave', e => { const h = lz.get(e.pointerId); if (h && h.hov) stopLaser(e.pointerId); });
  function popLaser() {
    const L = P.laser;
    pop.innerHTML = '<div class="pph">🔴 Laser pointer</div><div class="chips" id="plMode"></div><div class="chips" id="plCol"></div>' +
      '<small>Dot: a glowing point that follows the pointer. Short trail: a fading tail. Line: freehand, it fades away 2.5 seconds after you stop. Nothing is saved.</small>';
    const md = pop.querySelector('#plMode');
    LASER_MODES.forEach(k => {
      const b = hEl('button', 'chip' + (L.mode === k ? ' on' : ''), LASER_LABEL[k]);
      b.addEventListener('click', () => { L.mode = k; save(); popLaser(); });
      md.appendChild(b);
    });
    const cl = pop.querySelector('#plCol');
    LASER_COLORS.forEach(o => {
      const b = hEl('button', 'sw' + (L.color === o.c ? ' on' : '')); b.style.background = o.c; b.title = o.n;
      b.addEventListener('click', () => { L.color = o.c; save(); refresh(); });
      cl.appendChild(b);
    });
  }

  /* ---------- pointer routing (runs before the canvas' own handlers while a drawing tool is on) ---------- */

  const IGN = '#toolbar,#editor,#nodebar,#unhide,#nodeEdit,#masterTape,#rpanel,.rot,[data-pui],.tphd';
  let penLive = 0, penQuiet = 0;                         // stylus strokes being drawn · until when a touch next to the stylus counts as a resting palm
  const swallowed = new Set();                           // touches ignored on purpose (a palm): their move / up never reach the canvas either

  // finishes and saves one pen stroke; used on release, when the next stroke reuses the same id, and when the app is hidden
  function stopPen(id) {
    const a = live.get(id); if (!a) return false;
    live.delete(id);
    if (a.ptype === 'pen') penLive = Math.max(0, penLive - 1);
    endPen(a);
    return true;
  }
  function finishAct() {
    if (!act) return;
    const k = act.kind;
    try {
      if (k === 'erase') eraseUp(); else if (k === 'loop') loopUp();
      else if (k === 'move') selUp(); else { X.touch(); chrome(); }
    } catch (err) { console.error(err); }
    act = null; quietUntil = performance.now() + 600;
  }
  function down(e) {
    if (!open || tool === 'hand') return;
    if (e.target.closest && e.target.closest(IGN)) return;
    const now = performance.now(), isPen = e.pointerType === 'pen';
    if (isPen) penQuiet = now + 1000;
    // a stylus often reuses the same pointer id for every stroke: if the last one was not reported finished yet, finish it first
        if (live.has(e.pointerId)) stopPen(e.pointerId);
    if (lz.has(e.pointerId)) stopLaser(e.pointerId);

    if (act && act.id === e.pointerId) finishAct();
    if (e.pointerType === 'touch') {
      if (penLive > 0 || now < penQuiet) {                 // a resting palm next to the stylus: ignore it completely
        swallowed.add(e.pointerId); e.stopImmediatePropagation(); e.preventDefault(); return;
      }
      if (!P.touch) return;                                // touch draws only when ☝️ is on; otherwise it moves the canvas
    }
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    e.stopImmediatePropagation(); e.preventDefault();
    try { host.setPointerCapture(e.pointerId); } catch (err) { /* ignore */ }
    const r = host.getBoundingClientRect(), p = { x: e.clientX - r.left, y: e.clientY - r.top }, w = { x: (p.x - view.x) / view.k, y: (p.y - view.y) / view.k };
    const tmp = (e.buttons & 32) > 0;                      // the eraser end of a stylus
    if (tool === 'pen' && !(tmp && P.swap)) {
      startPen(e, p, w, r);
      if (isPen && live.has(e.pointerId)) penLive++;
      return;
    }
        if (tool === 'laser') {
      startLaser(e, p, w, r);
      if (isPen && lz.has(e.pointerId)) penLive++;
      return;
    }
    if (act) return;
                                       // one eraser / lasso gesture at a time
    if (!pop.hidden) closePop();
    if (tool === 'eraser' || (tmp && P.swap)) startErase(e, p, w, r); else startLasso(e, p, w, r);
  }
  function move(e) {
        if (swallowed.has(e.pointerId)) { e.stopImmediatePropagation(); return; }
    const zl = lz.size ? lz.get(e.pointerId) : null;
    if (zl) { e.stopImmediatePropagation(); e.preventDefault(); laserMove(zl, e); return; }
    if (!live.size && !act) { if (open && tool === 'laser' && e.pointerType !== 'touch') laserHover(e); return; }
    const a = live.get(e.pointerId);

    if (a) { e.stopImmediatePropagation(); e.preventDefault(); penMove(a, e); return; }
    if (act && act.id === e.pointerId) {
      e.stopImmediatePropagation(); e.preventDefault();
      const k = act.kind;
      if (k === 'erase') eraseMove(e); else if (k === 'loop') loopMove(e); else if (k === 'move') selMove(e); else xformMove(e);
      return;
    }
    if (e.pointerType === 'touch' && penLive > 0) e.stopImmediatePropagation();   // palm drift while the stylus writes must not pan or zoom
  }
  function up(e) {
        if (swallowed.has(e.pointerId)) { swallowed.delete(e.pointerId); e.stopImmediatePropagation(); return; }
    if (lz.size && lz.has(e.pointerId)) {
      const zl = lz.get(e.pointerId);
      if (!zl.hov) { e.stopImmediatePropagation(); e.preventDefault(); }
      stopLaser(e.pointerId);
      if (e.pointerType === 'pen') penQuiet = performance.now() + 1000;
      return;
    }
    if (!live.size && !act) return;

    if (live.has(e.pointerId)) {
      e.stopImmediatePropagation(); e.preventDefault();
      stopPen(e.pointerId);
      if (e.pointerType === 'pen') penQuiet = performance.now() + 1000;
      return;
    }
    if (act && act.id === e.pointerId) { e.stopImmediatePropagation(); e.preventDefault(); finishAct(); }
  }
  host.addEventListener('pointerdown', down, true);
  window.addEventListener('pointermove', move, true);
  window.addEventListener('pointerup', up, true);
  window.addEventListener('pointercancel', up, true);
  // iOS must never wait for a double-tap or open a magnifier / callout while a drawing tool is on, whichever device touches
  host.addEventListener('touchstart', e => {
    if (open && tool !== 'hand' && !(e.target.closest && e.target.closest(IGN))) e.preventDefault();
  }, { passive: false });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) [...live.keys()].forEach(id => stopPen(id));
  });


  /* ---------- colours, presets, recent colours ---------- */
  function pickColor(c) { P.color = c; addRecent(c); save(); refresh(); }
  function renderRecents() {
    pRec.innerHTML = '';
    P.recent.forEach(c => { const b = hEl('button', 'rc'); b.style.background = c; b.title = c; b.addEventListener('click', () => { P.color = c; save(); refresh(); }); pRec.appendChild(b); });
  }
  function renderPresets() {
    pPre.innerHTML = '';
    P.presets.forEach((q, i) => {
      const b = hEl('button', 'pre s-' + q.s); b.style.background = q.c;
      b.title = STY[q.s].name + ' · ' + q.w + ' · tap to use, hold to save the current pen here';
      if (q.s === P.style && q.c === P.color && q.w === P.width) b.classList.add('on');
      let t = 0, fired = false;
      b.addEventListener('pointerdown', () => {
        fired = false; clearTimeout(t);
        t = setTimeout(() => { fired = true; P.presets[i] = { s: P.style, c: P.color, w: P.width }; save(); buzz(); stat('Saved the current pen into preset ' + (i + 1) + '.'); renderPresets(); }, 550);
      });
      ['pointerup', 'pointerleave', 'pointercancel'].forEach(ev => b.addEventListener(ev, () => clearTimeout(t)));
      b.addEventListener('click', () => {
        if (fired) { fired = false; return; }
        P.style = q.s; P.color = q.c; P.width = q.w; addRecent(q.c); save();
        if (tool !== 'pen') setTool('pen'); else refresh();
      });
      pPre.appendChild(b);
    });
  }

  /* ---------- tool options (tap the active tool again) ---------- */
  function chipRow(box, list, cur, pick) {
    box.innerHTML = '';
    list.forEach(c => { const b = hEl('button', 'sw' + (c === cur ? ' on' : '')); b.style.background = c; b.title = c; b.addEventListener('click', () => pick(c)); box.appendChild(b); });
  }
  function tog(label, get, set, off) {
    const l = hEl('label', 'tg' + (off ? ' off' : '')), c = hEl('input'); c.type = 'checkbox'; c.checked = !!get(); c.disabled = !!off;
    c.addEventListener('change', () => { set(c.checked); save(); if (popKind === 'lasso') popLasso(); });
    l.appendChild(c); l.appendChild(hEl('span', '', label));
    return l;
  }
  function popPen() {
    pop.innerHTML = '<div class="pph">✒️ Pen</div><div class="chips" id="ppSty"></div>' +
      '<label class="sl">Thickness <b id="ppWv"></b><input type="range" id="ppW" min="1" max="24" step="1"></label>' +
      '<label class="sl">Stabilizer <b id="ppSv"></b><input type="range" id="ppS" min="0" max="100" step="1"></label>' +
      '<svg id="ppPrev" viewBox="0 0 220 36"><path d="M10 26C55 2 100 44 140 18S190 8 210 14" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>' +
      '<div class="chips" id="ppCol"></div><div class="chips" id="ppRec"></div>' +
      '<small>Stabilizer smooths shaky handwriting (0 = the exact stylus position). Tap a swatch in the panel to swap presets, hold one to save this pen into it.</small>';
    const sty2 = pop.querySelector('#ppSty');
    Object.keys(STY).forEach(k => { const b = hEl('button', 'chip' + (P.style === k ? ' on' : ''), STY[k].name); b.addEventListener('click', () => { P.style = k; save(); refresh(); }); sty2.appendChild(b); });
    const w = pop.querySelector('#ppW'), s = pop.querySelector('#ppS');
    w.value = P.width; s.value = Math.round(P.smooth * 100);
    const upd = () => {
      pop.querySelector('#ppWv').textContent = P.width; pop.querySelector('#ppSv').textContent = Math.round(P.smooth * 100) + '%';
      const pv = pop.querySelector('#ppPrev path'), m = STY[P.style];
      pv.setAttribute('stroke', P.color); pv.setAttribute('stroke-width', Math.min(30, P.width * m.w)); pv.setAttribute('stroke-opacity', m.o);
    };
    w.addEventListener('input', () => { P.width = +w.value; save(); upd(); renderPresets(); });
    s.addEventListener('input', () => { P.smooth = +s.value / 100; save(); upd(); });
    upd();
    chipRow(pop.querySelector('#ppCol'), PALETTE, P.color, pickColor);
    chipRow(pop.querySelector('#ppRec'), P.recent, P.color, pickColor);
  }
  function popEraser() {
    pop.innerHTML = '<div class="pph">🧽 Eraser</div>';
    pop.appendChild(tog('Auto-switch: a quick two-touch tap swaps pen ⇄ eraser; the stylus eraser end or side button erases while pressed', () => P.swap, v => { P.swap = v; }));
    pop.appendChild(tog('Protect typed text and boxes (only ink is erased)', () => P.protect, v => { P.protect = v; }));
    pop.appendChild(tog('Erase whole strokes instead of parts', () => P.whole, v => { P.whole = v; }));
    const l = hEl('label', 'sl', 'Eraser size <b id="peV"></b><input type="range" id="peS" min="6" max="60" step="1">');
    pop.appendChild(l);
    const s = l.querySelector('#peS'), v = l.querySelector('#peV'); s.value = P.eraseSize; v.textContent = P.eraseSize;
    s.addEventListener('input', () => { P.eraseSize = +s.value; v.textContent = s.value; save(); });
    pop.appendChild(hEl('small', '', 'With protection off, the eraser also deletes the boxes it passes over (Undo ↶ brings them back). This map has no image or PDF layers to protect.'));
  }
  function popLasso() {
    const f = P.filt, bx = f.boxes;
    pop.innerHTML = '<div class="pph">➰ Lasso · what to select</div>';
    pop.appendChild(tog('Ink strokes', () => f.ink, v => { f.ink = v; }, bx));
    pop.appendChild(tog('Highlights', () => f.hl, v => { f.hl = v; }, bx));
    pop.appendChild(tog('Text (boxes fully inside the loop)', () => f.text, v => { f.text = v; }, bx));
    pop.appendChild(tog('Images (none in this map)', () => false, () => {}, true));
    pop.appendChild(tog('Boxes only: a partial loop selects whole boxes', () => f.boxes, v => { f.boxes = v; }));
    pop.appendChild(tog('Stroke auto-snap: a partial loop selects the whole stroke', () => P.snap, v => { P.snap = v; }, bx));
    pop.appendChild(hEl('small', '', 'After selecting: round handle rotates, square handle resizes the ink. Press and hold inside the selection, then drag, to move the selected boxes together.'));
  }
  function popColor(recolor) {
    pop.innerHTML = '<div class="pph">🎨 ' + (recolor ? 'Recolor the selected ink' : 'Colour') + '</div><div class="chips" id="pcP"></div>' +
      '<div class="row2"><input type="color" id="pcc"><small>Custom colour</small></div><div class="chips" id="pcR"></div>';
    const pick = recolor ? recolorSel : pickColor, cur = recolor ? null : P.color;
    chipRow(pop.querySelector('#pcP'), PALETTE, cur, pick);
    chipRow(pop.querySelector('#pcR'), P.recent, cur, pick);
    const cc = pop.querySelector('#pcc'); cc.value = /^#[0-9a-f]{6}$/i.test(P.color) ? P.color : '#1d3557';
    cc.addEventListener('change', () => pick(cc.value));
  }
  function openPop(kind) {
    popKind = kind;
        if (kind === 'pen') popPen(); else if (kind === 'eraser') popEraser(); else if (kind === 'lasso') popLasso(); else if (kind === 'laser') popLaser(); else popColor(kind === 'recolor');

    placePop();
  }
  function closePop() { pop.hidden = true; popKind = ''; }
  function placePop() {
    const r = host.getBoundingClientRect(), pr = pnt.getBoundingClientRect();
    pop.hidden = false;
    const pw = pop.offsetWidth, ph = pop.offsetHeight, px = pr.left - r.left, py = pr.top - r.top;
    let x, y;
    if (popKind === 'recolor') { const sr = selBar.getBoundingClientRect(); x = sr.left - r.left; y = sr.top - r.top + sr.height + 8; if (y + ph > r.height - 8) y = sr.top - r.top - ph - 8; }
    else if (P.pos.o === 'v') { x = (px + pnt.offsetWidth / 2 < r.width / 2) ? px + pnt.offsetWidth + 8 : px - pw - 8; y = py; }
    else { x = px; y = (py + pnt.offsetHeight / 2 < r.height / 2) ? py + pnt.offsetHeight + 8 : py - ph - 8; }
    pop.style.left = clamp(x, 8, Math.max(8, r.width - pw - 8)) + 'px'; pop.style.top = clamp(y, 8, Math.max(8, r.height - ph - 8)) + 'px';
  }

  /* ---------- the movable tool panel ---------- */
  function refresh() {
    pnt.querySelectorAll('[data-t]').forEach(b => b.classList.toggle('on', b.dataset.t === 'blasso' ? (tool === 'lasso' && !!P.filt.boxes) : b.dataset.t === tool));
        pCol.querySelector('i').style.background = tool === 'laser' ? P.laser.color : P.color;

    pFin.classList.toggle('on', P.touch);
    pFin.title = P.touch ? 'Touch draws (tap to let only Apple Pencil or mouse draw, fingers then move the canvas)' : 'Only Apple Pencil or mouse draws; touch moves the canvas (tap to let touch draw)';
    renderPresets(); renderRecents();
    document.body.classList.toggle('paint-on', open && tool !== 'hand');
        if (popKind === 'pen') popPen(); else if (popKind === 'color') popColor(false); else if (popKind === 'laser') popLaser();

  }
  function setTool(t) {
    if (tool !== t) clearSel();
        tool = t; if (t !== 'hand') lastTool = t;
    if (t !== 'laser') releaseLasers();

    closePop(); refresh();
  }
  function placePanel() {
    pnt.classList.toggle('v', P.pos.o === 'v'); pnt.classList.toggle('h', P.pos.o === 'h');
    const r = host.getBoundingClientRect(), pw = pnt.offsetWidth, ph = pnt.offsetHeight;
    pnt.style.left = clamp(P.pos.x, 8, Math.max(8, r.width - pw - 8)) + 'px';
    pnt.style.top = clamp(P.pos.y, 8, Math.max(8, r.height - ph - 8)) + 'px';
  }
  // on release the panel docks to the nearest edge and turns vertical (left/right edge) or horizontal (top/bottom edge)
  function snapPanel() {
    const r = host.getBoundingClientRect();
    const x = parseFloat(pnt.style.left) || 0, y = parseFloat(pnt.style.top) || 0;
    let pw = pnt.offsetWidth, ph = pnt.offsetHeight;
    const d = { l: x, r: r.width - (x + pw), t: y, b: r.height - (y + ph) };
    const e = Object.keys(d).sort((a, b) => d[a] - d[b])[0];
    P.pos.o = (e === 'l' || e === 'r') ? 'v' : 'h'; P.pos.edge = e;
    pnt.classList.toggle('v', P.pos.o === 'v'); pnt.classList.toggle('h', P.pos.o === 'h');
    pw = pnt.offsetWidth; ph = pnt.offsetHeight;
    let nx = x, ny = y;
    if (e === 'l') nx = 8; else if (e === 'r') nx = r.width - pw - 8; else if (e === 't') ny = 64; else ny = r.height - ph - 8;   // top edge leaves the toolbar free
    if (e === 'l' || e === 'r') ny = clamp(ny, 8, Math.max(8, r.height - ph - (e === 'l' ? 170 : 8)));                                 // left edge leaves the tape buttons free
    else nx = clamp(nx, e === 'b' ? 170 : 8, Math.max(8, r.width - pw - 8));
    P.pos.x = nx; P.pos.y = ny; placePanel(); save();
  }
  const grip = pnt.querySelector('#pGrip'); let pd = null;
  grip.addEventListener('pointerdown', e => {
    e.preventDefault(); grip.setPointerCapture(e.pointerId);
    const r = pnt.getBoundingClientRect(); pd = { id: e.pointerId, dx: e.clientX - r.left, dy: e.clientY - r.top };
    closePop();
  });
  grip.addEventListener('pointermove', e => {
    if (!pd || e.pointerId !== pd.id) return;
    const c = host.getBoundingClientRect();
    pnt.style.left = (e.clientX - c.left - pd.dx) + 'px'; pnt.style.top = (e.clientY - c.top - pd.dy) + 'px';
  });
  const gripEnd = e => { if (!pd || e.pointerId !== pd.id) return; pd = null; snapPanel(); };
  grip.addEventListener('pointerup', gripEnd); grip.addEventListener('pointercancel', gripEnd);

  pnt.querySelectorAll('[data-t]').forEach(b => b.addEventListener('click', () => {
    const t = b.dataset.t;
    if (t === 'blasso') { if (tool === 'lasso' && P.filt.boxes) P.filt.boxes = false; else { P.filt.boxes = true; if (tool !== 'lasso') setTool('lasso'); } save(); closePop(); refresh(); return; }
    if (t === 'hand') { setTool('hand'); return; }
    if (tool === t) { if (popKind === t) closePop(); else openPop(t); }          // tap the active tool again: its options
    else setTool(t);
  }));
    pCol.addEventListener('click', () => {
    const k = tool === 'laser' ? 'laser' : 'color';
    if (popKind === k) closePop(); else openPop(k);
  });

  pFin.addEventListener('click', () => { P.touch = !P.touch; save(); refresh(); stat(P.touch ? 'Touch draws now (stylus or finger). Use the 🖐 tool to move the canvas.' : 'Only Apple Pencil or mouse draws. Touch pans and pinches the canvas.'); });
  pnt.querySelector('#pClose').addEventListener('click', () => setOpen(false));
  function setOpen(v) {
    open = v; pnt.hidden = !v; paintBtn.classList.toggle('on', v);
    if (v) { if (tool === 'hand') tool = lastTool; placePanel(); }
        else { tool = 'hand'; clearSel(); closePop(); releaseLasers(); }

    refresh();
  }
  paintBtn.addEventListener('click', () => setOpen(!open));
  window.addEventListener('resize', () => { if (open) { placePanel(); closePop(); } });
  if (window.ResizeObserver) new ResizeObserver(() => size()).observe(host);

  size(); syncSvg();
  if (window.__inkPending) setInk(window.__inkPending);
  refresh();
})();
(function () {
  'use strict';
  const X = window.MMX, P0 = window.MMP;
  if (!X || !P0) return;
  const view = X.view, host = document.getElementById('canvas'), tbar = document.getElementById('toolbar'), menuBtn = document.getElementById('menuBtn');
  const NS = 'http://www.w3.org/2000/svg', MINT = 0.06;
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const el = (t, c, h) => { const e = document.createElement(t); if (c) e.className = c; if (h != null) e.innerHTML = h; return e; };
  const sv = (t, a) => { const e = document.createElementNS(NS, t); for (const k in a) e.setAttribute(k, a[k]); return e; };
  const stat = m => { const s = document.getElementById('status'); if (s) s.textContent = m; };
  const short = (t, n) => { n = n || 28; return t.length > n ? t.slice(0, n - 1) + '…' : t; };
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const TL = { def: 'Define', idn: 'Identify', enum: 'Enumerate' }, TC = { def: '#457B9D', idn: '#E63946', enum: '#7B2CBF' };
  const noProp = n => ['pointerdown', 'pointerup', 'pointermove', 'pointercancel', 'wheel'].forEach(t => n.addEventListener(t, e => e.stopPropagation()));

  /* ---------- styles ---------- */
  const st = document.createElement('style');
  st.textContent = `
body.mode-b #panel,body.mode-c #panel{display:none}
.mpanel{width:340px;max-width:100%;background:var(--panel);border-right:1px solid var(--line);padding:14px;display:none;flex-direction:column;gap:10px;z-index:5;overflow:auto;overscroll-behavior:contain}
.mpanel h1{font-size:18px;margin:0}
.mpanel input[type=search],.mpanel select{width:100%;padding:8px;font-size:14px;border:1px solid var(--fieldb);border-radius:8px;background:var(--field);color:var(--fg)}
.mpanel .tg{display:flex;align-items:flex-start;gap:8px;font-size:13px;line-height:1.3;margin-top:8px}
.mpanel .tg input{width:22px;height:22px;flex:none;accent-color:#2A9D8F;margin:0}
.mpanel .note{color:var(--muted);font-size:12px;line-height:1.35}
@media (max-width:760px){.mpanel{position:absolute;inset:0 auto 0 0;width:88%;transform:translateX(-100%);transition:transform .2s}.mpanel.open{transform:none}}
body.mode-b #panelB,body.mode-c #panelC{display:flex}
body.collapsed .mpanel{display:none!important}
body.mode-b #nodebar,body.mode-c #nodebar,body.mode-b #rpanel,body.mode-c #rpanel,body.mode-b #unhide,body.mode-c #unhide,body.mode-b #editor,body.mode-c #editor,body.mode-b #masterTape,body.mode-c #masterTape,body.mode-b .rot,body.mode-c .rot{display:none!important}
#toolbar{flex-wrap:wrap;justify-content:flex-end;max-width:calc(100% - 24px)}
#tapeBtn.on{background:#2A9D8F;border-color:#2A9D8F;color:#fff}
#pSel button[hidden]{display:none}
#pSel button[data-m]{width:auto;padding:0 10px;font-size:13px}
#mmMenu{position:absolute;right:12px;top:calc(60px + env(safe-area-inset-top));z-index:7;background:var(--pop);color:var(--fg);border:1px solid var(--fieldb);border-radius:12px;padding:6px;box-shadow:0 6px 22px rgba(0,0,0,.3);display:flex;flex-direction:column;gap:4px;min-width:190px}
#mmMenu[hidden]{display:none}
#mmMenu button{text-align:left;min-height:42px}
#mmMenu button.on{background:#2A9D8F;border-color:#2A9D8F;color:#fff}
#mmMenu hr{width:100%;border:0;border-top:1px solid var(--line);margin:2px 0}
#cardBar{position:absolute;left:50%;bottom:calc(14px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:5;max-width:calc(100% - 16px);background:var(--pop);color:var(--fg);border:1px solid var(--fieldb);border-radius:16px;padding:8px 10px;box-shadow:0 6px 22px rgba(0,0,0,.3);display:flex;flex-direction:column;gap:6px;align-items:center}
#cardBar[hidden]{display:none}
#cardBar .cbt{font-size:13px;text-align:center;max-width:520px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
#cardBar .cbr{display:flex;gap:6px;flex-wrap:wrap;justify-content:center;align-items:center}
#cardBar button,#cardBar select{min-height:40px;font-size:14px}
#cardBar select{border:1px solid var(--fieldb);background:var(--field);color:var(--fg);border-radius:8px;padding:4px}
body.cardview .node.dim,body.cardview .node.semi,body.cardview .edge.dim,body.cardview .edge.semi{opacity:1}
body.cardview .cdim{opacity:.12!important}
.cblur{filter:blur(3px)}
.crow{display:flex;gap:6px;align-items:center;padding:6px 4px;border-bottom:1px solid var(--line);cursor:pointer}
.crow.cur{background:rgba(42,157,143,.15)}
.crow .cm{flex:1;min-width:0;font-size:13px}
.crow .cm small{display:block;color:var(--muted);font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.crow .cty{display:inline-block;color:#fff;border-radius:6px;padding:0 6px;font-size:11px;margin-right:4px}
.crow button{padding:4px 8px;font-size:14px}
#mmDlg{position:fixed;inset:0;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;z-index:80}
#mmDlg .card{background:var(--pop);color:var(--fg);padding:16px;border-radius:12px;width:min(92vw,360px);display:flex;flex-direction:column;gap:12px;box-shadow:0 10px 30px rgba(0,0,0,.4)}
`;
  document.head.appendChild(st);

  /* ---------- card data (saved with the map) ---------- */
  const D = { tape: {}, dir: {}, cdir: {}, ext: {}, exc: {}, del: {}, sched: {}, cfg: { pairs: false, blur: false } };
  const cp = o => JSON.parse(JSON.stringify(o));
  function reset() { D.tape = {}; D.dir = {}; D.cdir = {}; D.ext = {}; D.exc = {}; D.del = {}; D.sched = {}; D.cfg = { pairs: false, blur: false }; }
  const roots = () => X.roots();
  function amap() { const m = new Map(); roots().forEach(r => (function w(n) { m.set(n.id, n); n.children.forEach(w); })(r)); return m; }
  const vmap = () => new Map(X.nodes().map(n => [n.id, n]));
  function getData(h) {
    if (!h && X.main()) {                               // forget tapes / schedules of deleted boxes
      const am = amap();
      Object.keys(D.tape).forEach(k => { if (!am.has(+k)) delete D.tape[k]; });
      Object.keys(D.sched).forEach(k => { if (!am.has(+k.split(':')[1])) delete D.sched[k]; });
    }
    const o = { tape: D.tape, dir: D.dir, cdir: D.cdir, ext: D.ext, exc: D.exc, del: D.del, cfg: D.cfg };
    if (h) o.h = 1; else o.sched = D.sched;
    return o;
  }
  function setData(o) {
    if (!o) reset();
    else {
      ['tape', 'dir', 'cdir', 'ext', 'exc', 'del'].forEach(f => { D[f] = o[f] && typeof o[f] === 'object' ? cp(o[f]) : {}; });
      D.cfg = Object.assign({ pairs: false, blur: false }, o.cfg || {});
      if (!o.h) D.sched = o.sched && typeof o.sched === 'object' ? cp(o.sched) : {};   // undo never touches schedules
    }
    cardsCache = null;
    if (!ready) return;
    if (!o) { if (sess) endSession(true); } else reconcile();
    refreshPanel(); refreshOverlay(); syncBar();
  }

  /* ---------- cards ---------- */
  let cardsCache = null;
  const cards = () => cardsCache || (cardsCache = genCards());
  function cardsOf(p) {
    const res = [], kids = p.children;
    if (!kids.length) return res;
    const dir = D.dir[p.id] || 'both';
    const mk = (type, ks, ex, key) => { if (!D.del[key]) res.push({ key, type, p: p.id, kids: ks.map(k => k.id), ext: ex.map(g => g.id) }); };
    const extOf = ks => { const s = new Set(D.ext[p.id] || []), r = []; ks.forEach(k => k.children.forEach(g => { if (s.has(g.id)) r.push(g); })); return r; };
    if (D.cfg.pairs) {                                   // one card per parent-child pair
      kids.forEach(c => { const ex = extOf([c]); if (dir !== 'idn') mk('def', [c], ex, 'def:' + p.id + ':' + c.id); if (dir !== 'def') mk('idn', [c], ex, 'idn:' + p.id + ':' + c.id); });
      return res;
    }
    const exc = new Set(D.exc[p.id] || []), inc = kids.filter(k => !exc.has(k.id)), out = kids.filter(k => exc.has(k.id));
    if (inc.length) {
      const ex = extOf(inc), dt = inc.length > 1 ? 'enum' : 'def';
      if (dir !== 'idn') mk(dt, inc, ex, dt + ':' + p.id);
      if (dir !== 'def') mk('idn', inc, ex, 'idn:' + p.id);
    }
    out.forEach(c => { const cd = D.cdir[c.id] || 'both', ex = extOf([c]); if (cd !== 'idn') mk('def', [c], ex, 'def:' + p.id + ':' + c.id); if (cd !== 'def') mk('idn', [c], ex, 'idn:' + p.id + ':' + c.id); });
    return res;
  }
  // order: branch by branch (first child of the centre first), Enumerate cards first inside a branch, the centre's own cards last
  function genCards() {
    const main = X.main(), out = [];
    if (!main) return out;
    const branch = b => {
      const en = [], rest = [];
      (function w(n) { if (n.children.length) cardsOf(n).forEach(c => (c.type === 'enum' ? en : rest).push(c)); n.children.forEach(w); })(b);
      return en.concat(rest);
    };
    main.children.forEach(b => branch(b).forEach(c => out.push(c)));
    roots().slice(1).forEach(r => branch(r).forEach(c => out.push(c)));
    const mc = cardsOf(main);
    mc.filter(c => c.type === 'enum').concat(mc.filter(c => c.type !== 'enum')).forEach(c => out.push(c));
    return out;
  }
  const cardBoxes = c => [c.p].concat(c.kids, c.ext);
  const dirGet = c => (c.key.split(':').length === 3 && !D.cfg.pairs ? (D.cdir[c.kids[0]] || 'both') : (D.dir[c.p] || 'both'));
  function dirSet(c, v) { if (c.key.split(':').length === 3 && !D.cfg.pairs) D.cdir[c.kids[0]] = v; else D.dir[c.p] = v; }
  const isDue = c => { const s = D.sched[c.key]; return !s || s.due <= Date.now(); };
  const cardVisible = c => { const vm = vmap(); return cardBoxes(c).every(id => vm.has(id)); };

  /* ---------- modes ---------- */
  let mode = 'A', prevMode = 'A', tapeOn = false, tapeSel = null, sess = null, saved = null, ready = false;
  const panelB = el('aside', 'mpanel'), panelC = el('aside', 'mpanel');
  panelB.id = 'panelB'; panelC.id = 'panelC';
  panelB.innerHTML = '<div class="head"><h1>Tape edit</h1><button class="pHide" title="Hide panel">‹</button></div><div class="note">Nothing here yet. Tap a box to select its tape, then drag its four sides.</div>';
  panelC.innerHTML = '<div class="head"><h1>Flashcards</h1><button class="pHide" title="Hide panel">‹</button></div>' +
    '<div class="row"><button id="pcStart" class="primary">Start cards</button><button id="pcRestore">Restore deleted</button></div>' +
    '<details class="sec"><summary>Card settings</summary>' +
    '<label class="tg"><input type="checkbox" id="pcPairs"><span>One card per parent–child pair (off: one card per box with children)</span></label>' +
    '<label class="tg"><input type="checkbox" id="pcBlur"><span>Real blur outside the card (off: heavy dim, which is smoother)</span></label></details>' +
    '<input type="search" id="pcSearch" placeholder="Search cards…">' +
    '<select id="pcFilter"><option value="all">All cards</option><option value="due">Due</option><option value="new">New</option><option value="def">Define</option><option value="idn">Identify</option><option value="enum">Enumerate</option></select>' +
    '<div id="pcCount" class="note"></div><div id="pcList"></div>';
  document.body.insertBefore(panelB, host); document.body.insertBefore(panelC, host);
  const $c = id => panelC.querySelector('#' + id);
  const tapeBtn = el('button', '', '🩹'); tapeBtn.id = 'tapeBtn'; tapeBtn.title = 'Tape edit';
  tbar.insertBefore(tapeBtn, menuBtn);
  const bar = el('div'); bar.id = 'cardBar'; bar.hidden = true; bar.setAttribute('data-pui', '1'); host.appendChild(bar); noProp(bar);
  const menu = el('div'); menu.id = 'mmMenu'; menu.hidden = true; menu.setAttribute('data-pui', '1');
  menu.innerHTML = '<button data-md="A">A · Original</button><button data-md="B">B · Tape edit</button><button data-md="C">C · Flashcards</button><hr><button data-md="panel">Show / hide panel</button>';
  host.appendChild(menu); noProp(menu);

  function ask(msg, labels) {
    return new Promise(res => {
      const d = el('div'); d.id = 'mmDlg'; d.setAttribute('data-pui', '1');
      d.innerHTML = '<div class="card"><div class="mmq"></div><div class="row"></div></div>';
      d.querySelector('.mmq').textContent = msg;
      const row = d.querySelector('.row');
      labels.forEach((t, i) => { const b = el('button', i === 0 ? 'primary' : ''); b.textContent = t; b.onclick = () => { d.remove(); res(i); }; row.appendChild(b); });
      d.addEventListener('pointerdown', e => { if (e.target === d) { d.remove(); res(-1); } });
      document.body.appendChild(d);
    });
  }
  const isMobile = () => window.matchMedia('(max-width:760px)').matches;
  function setMode(m, fromMenu) {
    if (m === 'B' && mode !== 'B') prevMode = mode;
    if (mode === 'C' && m !== 'C') endSession();
    const was = mode;
    mode = m; tapeOn = m === 'B' || (m === 'C' && was === 'C' && tapeOn); tapeSel = null;
    [document.getElementById('panel'), panelB, panelC].forEach(p => p.classList.remove('open'));
    if (fromMenu && isMobile() && m !== 'A') (m === 'B' ? panelB : panelC).classList.add('open');
    syncUI();
  }
  function toggleTape() {
    if (!tapeOn) { if (mode === 'C') { tapeOn = true; tapeSel = null; syncUI(); } else setMode('B'); }
    else if (mode === 'B') setMode(prevMode === 'B' ? 'A' : prevMode);
    else { tapeOn = false; tapeSel = null; syncUI(); }
  }
  function syncUI() {
    const b = document.body;
    ['a', 'b', 'c'].forEach(k => b.classList.toggle('mode-' + k, mode === k.toUpperCase()));
    tapeBtn.classList.toggle('on', tapeOn);
    menu.querySelectorAll('[data-md]').forEach(x => x.classList.toggle('on', x.dataset.md === mode));
    refreshOverlay(); syncBar(); refreshSelBtns(); if (mode === 'C') renderList();
  }
  tapeBtn.onclick = toggleTape;
  menuBtn.onclick = () => { menu.hidden = !menu.hidden; };
  menu.addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return;
    menu.hidden = true;
    const m = b.dataset.md;
    if (m === 'panel') togglePanel(); else setMode(m, true);
  });
  document.addEventListener('pointerdown', e => { if (!menu.hidden && !e.target.closest('#mmMenu') && e.target !== menuBtn) menu.hidden = true; }, true);
  function togglePanel() {
    const p = mode === 'A' ? document.getElementById('panel') : (mode === 'B' ? panelB : panelC);
    if (isMobile()) p.classList.toggle('open'); else document.body.classList.toggle('collapsed');
  }
  [panelB, panelC].forEach(p => p.querySelector('.pHide').onclick = togglePanel);

  /* ---------- tape ---------- */
  let gT = null, gP = null, gH = null, tapeEls = new Map(), hEls = [], hNode = null, hd = null, lastDim = null;
  const tp = id => D.tape[id] || [0, 0, 1, 1];
  const tapedIds = c => (dispType(c) === 'idn' ? [c.p] : c.kids.concat(c.ext));
  function dispType(c) {
    const pd = sess && sess.pdir;
    if (pd === 'idn') return 'idn';
    if (pd === 'def') return c.type === 'idn' ? (c.kids.length > 1 ? 'enum' : 'def') : c.type;
    return c.type;
  }
  function setRect(e, n) {
    const t = tp(n.id);
    e.setAttribute('x', n.x - n.w / 2 + t[0] * n.w); e.setAttribute('y', n.y - n.h / 2 + t[1] * n.h);
    e.setAttribute('width', (t[2] - t[0]) * n.w); e.setAttribute('height', (t[3] - t[1]) * n.h);
  }
  function drawTape() {
    tapeEls = new Map();
    const show = [], vm = vmap();
    if (mode === 'B') X.nodes().forEach(n => show.push([n, 0.7]));
    else if (mode === 'C' && sess) {
      const ts = new Set(sess.revealed ? [] : tapedIds(sess.cur));
      cardBoxes(sess.cur).forEach(id => { const n = vm.get(id); if (!n) return; if (tapeOn) show.push([n, 0.7]); else if (ts.has(id)) show.push([n, 1]); });
    }
    show.forEach(([n, o]) => {
      const s = n.id === tapeSel && (mode === 'B' || tapeOn);
      const e = sv('rect', { rx: 4, fill: '#F4E7B0', stroke: s ? '#2A9D8F' : '#C9B26B', 'stroke-width': s ? 3 : 1.5, 'stroke-dasharray': s ? '6 4' : '0', opacity: o, 'data-id': n.id });
      setRect(e, n); gT.appendChild(e); tapeEls.set(n.id, e);
    });
  }
  function drawHandles() {
    hEls.forEach(h => h.e.remove()); hEls = []; hNode = null;
    if (!gH || tapeSel == null || !(mode === 'B' || tapeOn)) return;
    const n = vmap().get(tapeSel);
    if (!n || !tapeEls.has(n.id)) return;
    hNode = n;
    ['l', 'r', 't', 'b'].forEach(side => {
      const e = sv('rect', { fill: '#2A9D8F', stroke: '#fff', 'class': 'tphd', style: 'cursor:' + (side === 'l' || side === 'r' ? 'ew-resize' : 'ns-resize') });
      e.addEventListener('pointerdown', ev => {
        ev.stopPropagation(); ev.preventDefault();
        try { e.setPointerCapture(ev.pointerId); } catch (_) { /* ignore */ }
        hd = { side, n, s: tp(n.id).slice(), x: ev.clientX, y: ev.clientY, id: ev.pointerId };
      });
      e.addEventListener('pointermove', ev => {
        if (!hd || ev.pointerId !== hd.id) return;
        ev.stopPropagation();
        const dx = (ev.clientX - hd.x) / view.k / hd.n.w, dy = (ev.clientY - hd.y) / view.k / hd.n.h, t = hd.s.slice();
        if (hd.side === 'l') t[0] = clamp(hd.s[0] + dx, 0, t[2] - MINT);
        else if (hd.side === 'r') t[2] = clamp(hd.s[2] + dx, t[0] + MINT, 1);
        else if (hd.side === 't') t[1] = clamp(hd.s[1] + dy, 0, t[3] - MINT);
        else t[3] = clamp(hd.s[3] + dy, t[1] + MINT, 1);
        const r = t.map(v => Math.round(v * 1000) / 1000);
        if (r[0] === 0 && r[1] === 0 && r[2] === 1 && r[3] === 1) delete D.tape[hd.n.id]; else D.tape[hd.n.id] = r;
        const te = tapeEls.get(hd.n.id); if (te) setRect(te, hd.n);
        posHandles();
      });
      const end = ev => { if (!hd || ev.pointerId !== hd.id) return; hd = null; X.touch(); };
      e.addEventListener('pointerup', end); e.addEventListener('pointercancel', end);
      gH.appendChild(e); hEls.push({ e, side });
    });
    posHandles();
  }
  function posHandles() {
    if (!hNode) return;
    const n = hNode, t = tp(n.id), k = view.k;
    const x0 = n.x - n.w / 2 + t[0] * n.w, x1 = n.x - n.w / 2 + t[2] * n.w, y0 = n.y - n.h / 2 + t[1] * n.h, y1 = n.y - n.h / 2 + t[3] * n.h, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    const L = 34 / k, T = 12 / k;
    hEls.forEach(({ e, side }) => {
      const hz = side === 'l' || side === 'r', w = hz ? T : L, h = hz ? L : T;
      const x = side === 'l' ? x0 : side === 'r' ? x1 : cx, y = side === 't' ? y0 : side === 'b' ? y1 : cy;
      e.setAttribute('x', x - w / 2); e.setAttribute('y', y - h / 2); e.setAttribute('width', w); e.setAttribute('height', h);
      e.setAttribute('rx', 4 / k); e.setAttribute('stroke-width', 2 / k);
    });
  }

  /* ---------- plus / minus icons that extend the taped range ---------- */
  function drawPlus() {
    if (!gP) return;
    while (gP.firstChild) gP.removeChild(gP.firstChild);
    if (!sess) return;
    const c = sess.cur, k = view.k, vm = vmap(), ext = new Set(c.ext);
    c.kids.forEach(kid => {
      const kn = vm.get(kid); if (!kn) return;
      kn.children.forEach(g => {
        const gn = vm.get(g.id); if (!gn) return;
        const on = ext.has(g.id), cx = gn.x + gn.w / 2, cy = gn.y - gn.h / 2;
        const grp = sv('g', { 'class': 'tphd', style: 'cursor:pointer' });
        grp.appendChild(sv('circle', { cx, cy, r: 13 / k, fill: on ? '#E63946' : '#2A9D8F', stroke: '#fff', 'stroke-width': 2 / k }));
        const t = sv('text', { x: cx, y: cy + 6 / k, 'text-anchor': 'middle', 'font-size': 18 / k, fill: '#fff', 'font-family': 'Helvetica,Arial,sans-serif', 'font-weight': 'bold' });
        t.textContent = on ? '−' : '+'; t.style.pointerEvents = 'none'; grp.appendChild(t);
        grp.addEventListener('pointerdown', e => e.stopPropagation());
        grp.addEventListener('click', e => { e.stopPropagation(); toggleExt(c, gn); });
        gP.appendChild(grp);
      });
    });
  }
  async function toggleExt(c, g) {
    const arr = D.ext[c.p] || (D.ext[c.p] = []), i = arr.indexOf(g.id);
    if (i >= 0) { arr.splice(i, 1); if (!arr.length) delete D.ext[c.p]; changed(); return; }
    await addExt(c, [g]);
  }
  async function addExt(c, gs) {
    const dc = [];
    gs.forEach(g => cards().forEach(x => { if (g.parent && x.p === g.parent.id && x.kids.indexOf(g.id) >= 0 && dc.indexOf(x) < 0) dc.push(x); }));
    if (dc.length) {
      const r = await ask('Extend the range to ' + gs.length + ' box(es)? They already have ' + dc.length + ' default card(s). Delete them?', ['Delete them', 'Keep them', 'Cancel']);
      if (r < 0 || r === 2) return;
      if (r === 0) dc.forEach(x => { D.del[x.key] = 1; });
    }
    const arr = D.ext[c.p] || (D.ext[c.p] = []);
    gs.forEach(g => { if (arr.indexOf(g.id) < 0) arr.push(g.id); });
    changed();
  }

  /* ---------- overlay: dim outside the card, tape, handles ---------- */
  function cardRect(c) {
    const vm = vmap(); let r = null;
    cardBoxes(c).forEach(id => { const n = vm.get(id); if (!n) return; const q = { x0: n.x - n.w / 2 - 40, y0: n.y - n.h / 2 - 40, x1: n.x + n.w / 2 + 40, y1: n.y + n.h / 2 + 40 }; r = r ? { x0: Math.min(r.x0, q.x0), y0: Math.min(r.y0, q.y0), x1: Math.max(r.x1, q.x1), y1: Math.max(r.y1, q.y1) } : q; });
    return r;
  }
  function applyDim() {
    const ne = X.nodeEls(), ee = X.edgeEls(), set = sess ? new Set(cardBoxes(sess.cur)) : null, vm = vmap(), bl = D.cfg.blur && ne.size <= 140;
    ne.forEach((e, id) => { const d = !!set && !set.has(id); e.classList.toggle('cdim', d); e.classList.toggle('cblur', d && bl); });
    ee.forEach((e, id) => { const n = vm.get(id), d = !!set && !(n && n.parent && set.has(id) && set.has(n.parent.id)); e.classList.toggle('cdim', d); e.classList.toggle('cblur', d && bl); });
    document.body.classList.toggle('cardview', !!sess);
    const r = sess ? cardRect(sess.cur) : null, key = r ? JSON.stringify(r) : '';
    if (key !== lastDim) {                               // ink outside the card is dimmed too
      lastDim = key;
      P0.setDim(r ? (s => { const b = P0.bbox(s); return (b.x1 < r.x0 || b.x0 > r.x1 || b.y1 < r.y0 || b.y0 > r.y1) ? 0.18 : 1; }) : null);
    }
  }
  function build() {
    const w = X.world(); if (!w) return;
    gT = sv('g'); gP = sv('g'); gH = sv('g');
    w.appendChild(gT); w.appendChild(gP); w.appendChild(gH);
    drawTape(); drawPlus(); drawHandles(); applyDim();
  }
  function refreshOverlay() { [gT, gP, gH].forEach(g => { if (g && g.parentNode) g.parentNode.removeChild(g); }); build(); }
  let lt = 0;
  function onRender() { cardsCache = null; build(); clearTimeout(lt); lt = setTimeout(() => { if (mode === 'C') renderList(); }, 300); }
  function onView() { posHandles(); if (sess) drawPlus(); }

  /* ---------- tap routing ---------- */
  function lockTap(n) {
    if (mode === 'A') return false;
    if (mode === 'B' || tapeOn) {
      const ok = n && (mode === 'B' || (sess && cardBoxes(sess.cur).indexOf(n.id) >= 0));
      tapeSel = ok ? n.id : null; refreshOverlay(); return true;
    }
    if (sess && !sess.revealed && n && tapedIds(sess.cur).indexOf(n.id) >= 0) { sess.revealed = true; refreshOverlay(); syncBar(); }
    return true;
  }

  /* ---------- camera ---------- */
  let raf = 0;
  function animTo(t, ms) {
    cancelAnimationFrame(raf);
    const a = { x: view.x, y: view.y, k: view.k }, t0 = performance.now();
    const step = now => {
      let p = Math.min(1, (now - t0) / ms); p = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      view.k = a.k * Math.pow(t.k / a.k, p); view.x = a.x + (t.x - a.x) * p; view.y = a.y + (t.y - a.y) * p;
      X.applyView();
      if (p < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
  }
  function zoomCard(c) {
    const r = cardRect(c); if (!r) return;
    const b = host.getBoundingClientRect(), W = r.x1 - r.x0, H = r.y1 - r.y0, availH = Math.max(120, b.height - 100);
    const k = clamp(Math.min(b.width / W, availH / H), 0.01, 1.6);
    animTo({ k, x: b.width / 2 - (r.x0 + W / 2) * k, y: availH / 2 - (r.y0 + H / 2) * k + 10 }, 260);
  }

  /* ---------- study / review sessions ---------- */
  function startSession(kind, list, i0) {
    const key = list[i0] && list[i0].key, ok = list.filter(cardVisible);
    if (!ok.length) { stat('Those cards are in hidden branches. Show the branch first.'); return; }
    if (mode !== 'C') setMode('C');
    if (!saved) saved = { x: view.x, y: view.y, k: view.k };
    let i = ok.findIndex(c => c.key === key); if (i < 0) i = 0;
    sess = { kind, list: ok, i, cur: ok[i], revealed: false, pdir: 'both' };
    showCard();
  }
  function showCard(noZoom) {
    const c = sess.list[sess.i]; sess.cur = c; sess.pdir = dirGet(c);
    if (!noZoom) { sess.revealed = false; zoomCard(c); }
    refreshOverlay(); syncBar(); refreshSelBtns(); renderList();
  }
  function endSession(skip) {
    if (!sess) return;
    sess = null; const s = saved; saved = null;
    if (!skip && s) animTo(s, 260);                      // back to exactly where it was
    bar.hidden = true; refreshOverlay(); refreshSelBtns(); renderList();
  }
  function reconcile() {
    if (!sess) return;
    const all = new Map(cards().map(c => [c.key, c])), ck = sess.cur && sess.cur.key;
    sess.list = sess.list.map(c => all.get(c.key)).filter(Boolean);
    if (!sess.list.length) { endSession(); return; }
    const i = sess.list.findIndex(c => c.key === ck);
    if (i < 0) { sess.i = Math.min(sess.i, sess.list.length - 1); showCard(); return; }
    sess.i = i; sess.cur = sess.list[i];
  }
  function rate(good) {
    const c = sess.cur, now = Date.now(), s = D.sched[c.key] || { ivl: 0, reps: 0, lapses: 0 };
    sess.list.splice(sess.i, 1);
    if (good) { s.ivl = s.reps ? Math.max(1, Math.round(s.ivl * 2.5)) : 1; s.reps++; s.due = now + s.ivl * 864e5; }   // Got it: a longer gap every time
    else { s.lapses = (s.lapses || 0) + 1; s.reps = 0; s.ivl = 0; s.due = now + 6e4; sess.list.splice(Math.min(sess.list.length, sess.i + (c.type === 'enum' ? 1 : 3)), 0, c); }   // Understood: back soon
    D.sched[c.key] = s; X.persist();
    if (!sess.list.length) { stat('Review finished.'); endSession(); return; }
    if (sess.i >= sess.list.length) sess.i = 0;
    showCard();
  }
  function syncBar() {
    if (!sess) { bar.hidden = true; return; }
    bar.hidden = false;
    const c = sess.cur, t = dispType(c), pn = amap().get(c.p), n = sess.list.length, rv = sess.kind === 'review', rev = sess.revealed;
    let h = '<div class="cbt"><b style="color:' + TC[t] + '">' + TL[t] + '</b> · ' + esc(short(pn ? pn.text : '', 40)) + ' · ' + (rv ? n + ' left' : (sess.i + 1) + '/' + n) + '</div><div class="cbr">';
    if (!rv) h += '<button data-a="prev">‹ Prev</button><button data-a="rev">' + (rev ? 'Hide' : 'Show') + '</button><button data-a="next">Skip ›</button>';
    else if (!rev) h += '<button class="primary" data-a="rev">Show answer</button>';
    else h += '<button data-a="again">Understood</button><button class="primary" data-a="good">Got it</button>';
    h += '</div><div class="cbr"><select id="cbDir">' + [['both', 'Both ways'], ['def', 'Define only'], ['idn', 'Identify only']].map(o => '<option value="' + o[0] + '"' + (o[0] === sess.pdir ? ' selected' : '') + '>' + o[1] + '</option>').join('') + '</select><button data-a="save">Save</button><button data-a="close">✕</button></div>';
    bar.innerHTML = h;
  }
  bar.addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b || !sess) return;
    const a = b.dataset.a;
    if (a === 'rev') { sess.revealed = sess.kind === 'review' ? true : !sess.revealed; refreshOverlay(); syncBar(); }
    else if (a === 'prev') { if (sess.i > 0) { sess.i--; showCard(); } }
    else if (a === 'next') { if (sess.i < sess.list.length - 1) { sess.i++; showCard(); } else { stat('That was the last card.'); endSession(); } }
    else if (a === 'again') rate(false);
    else if (a === 'good') rate(true);
    else if (a === 'save') { dirSet(sess.cur, sess.pdir); changed(); stat('Saved this direction for all future reviews of the card.'); }
    else if (a === 'close') endSession();
  });
  bar.addEventListener('change', e => { if (e.target.id === 'cbDir' && sess) { sess.pdir = e.target.value; refreshOverlay(); syncBar(); } });

  function changed() { cardsCache = null; X.touch(); reconcile(); refreshPanel(); refreshOverlay(); syncBar(); refreshSelBtns(); renderList(); }

  /* ---------- card browser (side panel of mode C) ---------- */
  function dueText(c) { const s = D.sched[c.key]; if (!s) return 'New'; if (s.due <= Date.now()) return 'Due now'; return 'Due ' + new Date(s.due).toLocaleDateString(); }
  function filtered() {
    const q = $c('pcSearch').value.trim().toLowerCase(), f = $c('pcFilter').value, am = amap(), nm = id => (am.get(id) ? am.get(id).text : '');
    return cards().filter(c => {
      if (f === 'due' && !isDue(c)) return false;
      if (f === 'new' && D.sched[c.key]) return false;
      if ((f === 'def' || f === 'idn' || f === 'enum') && c.type !== f) return false;
      if (!q) return true;
      return (TL[c.type] + ' ' + nm(c.p) + ' ' + c.kids.map(nm).join(' ')).toLowerCase().indexOf(q) >= 0;
    });
  }
  function renderList() {
    if (mode !== 'C') return;
    const box = $c('pcList'), list = filtered(), am = amap(), nm = id => (am.get(id) ? am.get(id).text : '?');
    const all = cards(), due = all.filter(isDue).length;
    $c('pcCount').textContent = all.length + ' cards · ' + due + ' due/new' + (list.length !== all.length ? ' · ' + list.length + ' shown' : '') + (list.length > 300 ? ' (first 300)' : '');
    box.innerHTML = '';
    list.slice(0, 300).forEach(c => {
      const r = el('div', 'crow' + (sess && sess.cur && sess.cur.key === c.key ? ' cur' : ''));
      const kids = c.kids.map(nm).map(t => short(t, 18)).join(', ');
      r.innerHTML = '<div class="cm"><span class="cty" style="background:' + TC[c.type] + '">' + TL[c.type] + '</span><b>' + esc(short(nm(c.p), 26)) + '</b><small>' + (c.type === 'idn' ? esc(kids) + ' → ' + esc(short(nm(c.p), 18)) : '→ ' + esc(kids)) + ' · ' + dueText(c) + '</small></div><button data-r title="Reset schedule">↺</button><button data-d title="Delete card">🗑</button>';
      r.onclick = e => {
        if (e.target.closest('[data-r]')) { delete D.sched[c.key]; X.persist(); renderList(); return; }
        if (e.target.closest('[data-d]')) { D.del[c.key] = 1; changed(); return; }
        startSession('study', list, list.indexOf(c));    // tap a card: its boxes open on the canvas
      };
      box.appendChild(r);
    });
  }
  function refreshPanel() { $c('pcPairs').checked = !!D.cfg.pairs; $c('pcBlur').checked = !!D.cfg.blur; }
  $c('pcSearch').addEventListener('input', renderList);
  $c('pcFilter').addEventListener('change', renderList);
  $c('pcPairs').addEventListener('change', e => { D.cfg.pairs = e.target.checked; changed(); });
  $c('pcBlur').addEventListener('change', e => { D.cfg.blur = e.target.checked; X.touch(); refreshOverlay(); });
  $c('pcRestore').onclick = () => { D.del = {}; changed(); stat('Deleted cards are back.'); };
  async function begin(list) {
    const k = await ask('Start cards (' + list.length + ')', ['Study', 'Review', 'Cancel']);
    if (k < 0 || k === 2) return;
    const l = k === 1 ? list.filter(isDue) : list;
    if (!l.length) { stat('Nothing is due.'); return; }
    startSession(k === 0 ? 'study' : 'review', l, 0);
  }
  $c('pcStart').onclick = () => begin(cards());

  /* ---------- lasso: selection bar extras ---------- */
  let sb = null;
  function ensureSelBtns(bar2) {
    if (sb) return; sb = {};
    [['study', 'Study selection', 'Study'], ['del', 'Delete the card made of exactly these boxes', 'Delete card'], ['inc', 'Include in the enumeration', 'Include'], ['exc', 'Exclude from the enumeration', 'Exclude'], ['ext', 'Extend the taped range to these boxes', 'Extend']].forEach(([k, t, l]) => {
      const b = el('button', '', l); b.dataset.m = k; b.title = t; b.hidden = true; bar2.insertBefore(b, bar2.firstChild); sb[k] = b;
    });
    bar2.addEventListener('click', selClick);
  }
  function matchCards(ids) {
    const S = new Set(ids); if (!S.size) return [];
    return cards().filter(c => { const b = cardBoxes(c); return b.length === S.size && b.every(id => S.has(id)); });
  }
  function refreshSelBtns() {
    if (!sb) return;
    const ids = P0.selIds(), has = ids.length > 0; let inc = false, ext = false;
    if (has && sess) {
      const am = amap(), pn = am.get(sess.cur.p), ks = new Set(pn ? pn.children.map(k => k.id) : []);
      inc = ids.some(id => ks.has(id));
      ext = ids.some(id => { const g = am.get(id); return g && g.parent && sess.cur.kids.indexOf(g.parent.id) >= 0; });
    }
    sb.study.hidden = !has; sb.del.hidden = !(has && mode === 'A' && matchCards(ids).length > 0);
    sb.inc.hidden = !inc; sb.exc.hidden = !inc; sb.ext.hidden = !ext;
  }
  function onSel(bar2) { ensureSelBtns(bar2); refreshSelBtns(); }
  async function selClick(e) {
    const b = e.target.closest('button[data-m]'); if (!b) return;
    const k = b.dataset.m, ids = P0.selIds();
    if (k === 'study') {
      const S = new Set(ids), list = cards().filter(c => cardBoxes(c).every(id => S.has(id)));
      if (!list.length) { stat('No complete card inside the selection.'); return; }
      if (mode !== 'C') setMode('C');
      begin(list);
    } else if (k === 'del') {
      const m = matchCards(ids);
      const r = await ask('Delete ' + m.length + ' card(s) (' + m.map(c => TL[c.type]).join(', ') + ') made of exactly these boxes?', ['Delete', 'Cancel']);
      if (r === 0) { m.forEach(c => { D.del[c.key] = 1; }); changed(); }
    } else if (k === 'ext' && sess) {
      const am = amap(), gs = ids.map(id => am.get(id)).filter(g => g && g.parent && sess.cur.kids.indexOf(g.parent.id) >= 0 && sess.cur.ext.indexOf(g.id) < 0);
      if (gs.length) await addExt(sess.cur, gs);
    } else if ((k === 'inc' || k === 'exc') && sess) {
      const p = sess.cur.p, pn = amap().get(p), ks = new Set(pn.children.map(c => c.id)), ch = ids.filter(id => ks.has(id));
      if (!ch.length) return;
      let a = (D.exc[p] || []).filter(id => ch.indexOf(id) < 0);
      if (k === 'exc') {
        a = a.concat(ch);
        const r = await ask('How should the excluded box(es) be studied?', ['Both ways', 'Define only', 'Identify only']);
        if (r < 0) return;
        ch.forEach(id => { D.cdir[id] = ['both', 'def', 'idn'][r]; });
      }
      if (a.length) D.exc[p] = a; else delete D.exc[p];
      changed();
    }
  }

  /* ---------- public hooks ---------- */
  window.MMM = { get: getData, set: setData, lock: () => mode !== 'A', lockTap, onRender, onView, onSel, mode: () => mode };
  ready = true;
  if (window.__cdPending !== undefined) { setData(window.__cdPending); window.__cdPending = undefined; }
  refreshPanel(); syncUI();
})();
"""#





