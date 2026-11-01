
let appJS = #"""
(function () {
  'use strict';
  const { TYPES, TEAL, parse } = window.NLP;
  const { layout, bounds, borderPoint, FONT } = window.MM;
  const NS = 'http://www.w3.org/2000/svg';
  const $ = id => document.getElementById(id);
  const svg = $('svg'), canvas = $('canvas'), input = $('input'), statusEl = $('status');
  const editor = $('editor'), typeSel = $('typeSel'), panel = $('panel');
  const lenEl = $('len'), lenVal = $('lenVal'), themeBtn = $('theme');
  const lenMinus = $('lenMinus'), lenPlus = $('lenPlus');
  const levelsBody = $('levelsBody');
  const lineRow = $('lineRow'), lineLen = $('lineLen'), lineVal = $('lineVal'), lineReset = $('lineReset');
  const rpanel = $('rpanel'), rname = $('rname'), lineMinus = $('lineMinus'), linePlus = $('linePlus');
  const nodebar = $('nodebar'), nbDot = $('nbDot'), nbType = $('nbType'), nbAdd = $('nbAdd'), nbTape = $('nbTape'), nbDup = $('nbDup');
    const nbFixO = $('nbFixO'), nbFixL = $('nbFixL'), nbFixD = $('nbFixD'), nbDel = $('nbDel'), nbRev = $('nbRev');

  const unhide = $('unhide'), nodeEdit = $('nodeEdit'), masterTape = $('masterTape');
  const ccwBtn = $('ccwBtn'), cwBtn = $('cwBtn');
  const dlg = $('dlg'), libName = $('libName'), libList = $('libList');
  const expDlg = $('expDlg'), expText = $('expText');
  const undoBtn = $('undoBtn'), redoBtn = $('redoBtn');

  const GRID = 28, MINGAP = GRID * 0.25, SNAP = GRID * 0.5;   // canvas grid unit = 28
  const BULGE = 1.22;                                          // size of the tap "bulge" (matches the ripple animation)
  const EDGE_GAP = 62, TIDY_GAP = 14;                          // used when pulling over-long lines back in
  const DATA_V = 3;                                            // saved-data version (older saves hold stale auto-spacing)
  // radial-bloom solver settings
  const BLOOM = { PUSH: 0.9, DAMP: 0.82, ITER: 220, PASSES: 3, DT: 1, CIRC: 0.6, MOVE_MIN: 0.5 };
  // invisible circular barrier around the branch while it blooms (text-length capacity + 15% buffer)
  const BAR = { BUF: 1.15, SPREAD: 9, GROW: 3, STEP: 1.12 };
  // shake-to-detach: REV direction reversals of at least TH pixels within MS milliseconds
  const SHAKE = { TH: 14, REV: 4, MS: 900 };
  // camera follows a moved box: within M pixels of the canvas border the view scrolls at up to V pixels per frame
  const PAN = { M: 80, V: 16 };
  const HELP = 'drag to pan · pinch to zoom · tap a box for tools · double-tap to edit · hold a box to move it, shake it to snap it out';
  const LIB_KEY = 'mm-lib', DRAFT_KEY = 'mm-draft';

  let main = null, floats = [], nodes = [], lists = [];
  let nodeSet = new Set();                              // same boxes as `nodes`, for instant lookups
  let editing = null, selected = null, nodeEls = new Map(), edgeEls = new Map(), world = null;
  let lenK = (+lenEl.value || 120) / 100;
  let levels = {};
  let dark = false;
  let nextId = 1, mapName = '', dirty = false, needPrompt = false, draftT = 0;
  let editNode = null, dnode = null, grab = { x: 0, y: 0 }, target = null;
  let mover = null, lastPtr = null, panRaf = 0;         // mover = a box held and moved while still connected
  let lastTap = { id: 0, t: 0 }, holdT = 0, dlgAfter = null;
  let hist = [], hi = -1;                               // undo / redo history
  let camLock = null;                                   // camera locked on a freshly merged / connected box
  let delT = 0, delArm = null;                          // delete button: armed (waiting for a second tap) on this box
  let indEls = [];                                      // the drop-target highlight drawn while a box is dragged
  const view = { x: 0, y: 0, k: 1 };

  const SAMPLE = `Photosynthesis

Photosynthesis is the process by which green plants convert light energy into chemical energy. It takes place in the chloroplasts of leaf cells, usually at around 25 °C.

Inputs and Outputs
- Inputs: carbon dioxide, water, and sunlight
- Outputs: glucose and oxygen
- Chlorophyll: the green pigment that absorbs light

History
Jan Ingenhousz discovered in 1779 that light is essential for plants. Dr. Melvin Calvin later mapped the cycle and won the Nobel Prize in 1961. As he explained, "the path of carbon in photosynthesis was traced with radioactive tracers."`;

  function setNodes(arr) { nodes = arr; nodeSet = new Set(arr); }

  /* ---------- storage helpers ---------- */
  const lsGet = k => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); return true; } catch (e) { return false; } };
  const lsDel = k => { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } };

  function haptic() {
    try {
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.haptic;
      if (h) { h.postMessage('heavy'); return; }
    } catch (e) { /* ignore */ }
    try { if (navigator.vibrate) navigator.vibrate(30); } catch (e) { /* ignore */ }
  }

  /* ---------- svg helper ---------- */
  function S(tag, attrs, parent) {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(e);
    return e;
  }

  /* ---------- colour helpers ---------- */
  function lum(hex) {
    const c = [1, 3, 5].map(i => parseInt(hex.substr(i, 2), 16) / 255)
      .map(v => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)));
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  function textColor(colors) {
    const w = Math.min(...colors.map(c => contrast('#ffffff', c)));
    const d = Math.min(...colors.map(c => contrast('#111111', c)));
    return w >= d ? '#ffffff' : '#111111';
  }
  function mix(h1, h2, t) {
    const a = [1, 3, 5].map(i => parseInt(h1.substr(i, 2), 16));
    const b = [1, 3, 5].map(i => parseInt(h2.substr(i, 2), 16));
    return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, '0')).join('');
  }
  const isGrad = n => n.isMember && n.type !== 'member';
  const PAGE_BG = () => (dark ? '#12161c' : '#ffffff');

  /* ---------- tree helpers ---------- */
  function walkAll(fn) { [main].concat(floats).forEach(r => { if (r) (function w(n) { fn(n); n.children.forEach(w); })(r); }); }
  function fixIds() { let m = 0; walkAll(n => { if (n.id > m) m = n.id; }); nextId = m + 1; }
  function setDepth(n, d) { n.depth = d; n.children.forEach(c => setDepth(c, d + 1)); }
  function countKids(n) { let c = 0; (function w(m) { m.children.forEach(k => { c++; w(k); }); })(n); return c; }
  const byId = id => nodes.find(n => n.id === id);
  const short = t => (t.length > 34 ? t.slice(0, 33) + '…' : t);
  function inTree(root, x) { let f = false; (function w(m) { if (m === x) f = true; else m.children.forEach(w); })(root); return f; }
  const isAnc = (a, b) => { for (let q = b.parent; q; q = q.parent) if (q === a) return true; return false; };
  const rootOfNode = x => { while (x.parent) x = x.parent; return x; };
  const normA = a => Math.atan2(Math.sin(a), Math.cos(a));
  const subtreeSet = n => { const s = new Set(); (function w(m) { s.add(m); m.children.forEach(w); })(n); return s; };

  /* ---------- level multipliers: whole-map levels, or re-based on a box through its own .lv ---------- */
  // nearest ancestor that has its own level setting for this relative depth wins, then the whole-map level
  function lvMul(n) {
    for (let a = n.parent; a; a = a.parent) {
      if (a.lv) { const v = a.lv[n.depth - a.depth]; if (v != null) return v; }
    }
    return levels[n.depth];
  }
  // multiplier on the default layout distance (1 = 100% = the default initial layout):
  // your own settings win (single line, then level), then automatic tidy-ups, then the default
  function effMul(n) {
    if (n.ov != null) return n.ov;
    const m = lvMul(n);
    if (m != null) return m;
    return n.au != null ? n.au : 1;
  }
  // the real length of a box's line as a multiple of its default length (includes any push the guardrail or a fix added)
  function trueMul(n) {
    const p = n.parent; if (!p) return 1;
    const L = Math.max(1, lenK), base = Math.hypot(n.dx, n.dy);
    if (!(base > 1e-6) || !Number.isFinite(n.x) || !Number.isFinite(p.x)) return effMul(n);
    return Math.hypot(n.x - p.x, n.y - p.y) / L / base;
  }
  // angle of a box's default line direction, as the layout currently sees it
  function baseAngle(n) {
    const lm = lvMul(n), user = n.ov != null ? n.ov : lm, m = user != null ? user : (n.au != null ? n.au : 1);
    const bx = n.dx * m, by = n.dy * m;
    return Math.hypot(bx, by) > 1e-6 ? Math.atan2(by, bx) : (n.ang || 0);
  }

  /* ---------- geometry helpers ---------- */
  // smallest centre distance along direction (ux,uy) at which two boxes are fully apart (plus gap g)
  function sepAlong(a, b, ux, uy, g) {
    const sx = (a.w + b.w) / 2 + g, sy = (a.h + b.h) / 2 + g;
    return Math.min(Math.abs(ux) > 1e-9 ? sx / Math.abs(ux) : Infinity, Math.abs(uy) > 1e-9 ? sy / Math.abs(uy) : Infinity);
  }
  const hitR = (a, b, g) => Math.abs(a.x - b.x) < (a.w + b.w) / 2 + g && Math.abs(a.y - b.y) < (a.h + b.h) / 2 + g;
  // does the connector p→c (centre to centre) pass through box m (grown by g)?
  function segHitsBox(p, c, m, g) {
    const o = [p.x, p.y], d = [c.x - p.x, c.y - p.y];
    const lo = [m.x - m.w / 2 - g, m.y - m.h / 2 - g], hi2 = [m.x + m.w / 2 + g, m.y + m.h / 2 + g];
    let t0 = 0, t1 = 1;
    for (let i = 0; i < 2; i++) {
      if (Math.abs(d[i]) < 1e-9) { if (o[i] < lo[i] || o[i] > hi2[i]) return false; }
      else {
        let a = (lo[i] - o[i]) / d[i], b = (hi2[i] - o[i]) / d[i];
        if (a > b) { const t = a; a = b; b = t; }
        t0 = Math.max(t0, a); t1 = Math.min(t1, b);
        if (t0 > t1) return false;
      }
    }
    return true;
  }
  function branchOf(n, vis) {
    const out = [];
    (function w(m) { out.push(m); m.children.forEach(k => { if (vis.has(k)) w(k); }); })(n);
    return out;
  }

  /* ---------- sibling sequence: the order of a box's children is also their order around it ---------- */
  // position of direction `a` in the child sequence of p. Around a box that has a parent the children fan out
  // from one flank of the parent's line to the other (the line itself is the wrap point), so the first and last
  // child sit right beside it. Around a centre box the sequence runs once round the circle, starting at the top.
  function seqKey(p, a) {
    if (p.parent) return normA(a - Math.atan2(p.y - p.parent.y, p.x - p.parent.x));
    const T = Math.PI * 2;
    return (((a + Math.PI / 2) % T) + T) % T;
  }
  const keyOf = (p, c) => seqKey(p, Math.atan2(c.y - p.y, c.x - p.x));
  // the angular range a child may occupy without passing a neighbour (or crossing the parent's line)
  function seqBounds(mv) {
    const p = mv.parent; if (!p) return null;
    const kids = p.children, i = kids.indexOf(mv); if (i < 0) return null;
    const root = !p.parent;
    let lo = root ? 0 : -Math.PI, hi = root ? Math.PI * 2 : Math.PI;
    if (i > 0 && nodeSet.has(kids[i - 1])) lo = keyOf(p, kids[i - 1]);
    if (i < kids.length - 1 && nodeSet.has(kids[i + 1])) hi = keyOf(p, kids[i + 1]);
    return [lo, hi];
  }
  // true if the children of p are no longer in angular order
  function seqBad(p) {
    const kids = p.children; if (kids.length < 2) return false;
    let prev = -Infinity;
    for (const c of kids) {
      if (!nodeSet.has(c)) return false;
      const k = keyOf(p, c);
      if (k <= prev + 1e-6) return true;
      prev = k;
    }
    return false;
  }

  /* ---------- "lollipop" hitboxes: box + the line corridor leading to its parent ---------- */
  // border point of rectangle (x,y,w,h) in the direction of point (tx,ty)
  function bpt(x, y, w, h, tx, ty) {
    const dx = tx - x, dy = ty - y;
    const a = dx ? (w / 2) / Math.abs(dx) : Infinity, b = dy ? (h / 2) / Math.abs(dy) : Infinity;
    const t = Math.min(a, b, 1);
    return { x: x + dx * t, y: y + dy * t };
  }
  // lollipop of node n sitting at (x,y) with its parent at (px,py).
  // sn / sp = size scale of n / of its parent (the tap bulge makes boxes bigger for a moment).
  // The corridor starts on the box border and stops short of the parent. That gap (the inset) follows the
  // live line length and grows with the number of siblings: the more lines leave the same parent, the
  // closer together their sticks run near it, so the corridor must stop earlier to stay clear of them.
  function mkL(n, x, y, px, py, sn, sp) {
    const w = n.w * sn, h = n.h * sn, p = n.parent;
    let seg = null, hw = 0;
    if (p) {
      hw = Math.max(1.8, 4.2 - 0.6 * n.depth) / 2 + 2;
      const a = bpt(x, y, w, h, px, py), b = bpt(px, py, p.w * sp, p.h * sp, x, y);
      const dx = a.x - b.x, dy = a.y - b.y, len = Math.hypot(dx, dy);
      const k = Math.max(1, p.children.length);                               // sibling count (this box included)
      const base = Math.min(14, Math.max(5, 0.05 * len));                     // the inset a lone child gets
      const off = Math.min(len * 0.4, 60, base * (1 + 0.45 * (k - 1)));       // proportional to the sibling count
      if (len > off + 1) { const q = off / len; seg = [a.x, a.y, b.x + dx * q, b.y + dy * q]; }
    }
    let x0 = x - w / 2, x1 = x + w / 2, y0 = y - h / 2, y1 = y + h / 2;
    if (seg) {
      x0 = Math.min(x0, seg[0], seg[2]); x1 = Math.max(x1, seg[0], seg[2]);
      y0 = Math.min(y0, seg[1], seg[3]); y1 = Math.max(y1, seg[1], seg[3]);
    }
    return { n, x, y, w, h, hw, seg, bx0: x0 - hw, bx1: x1 + hw, by0: y0 - hw, by1: y1 + hw };
  }
  // is segment s within m of rectangle R (centre x,y size w,h)?
  function segBox(s, R, m) {
    const x0 = s[0], y0 = s[1], dx = s[2] - x0, dy = s[3] - y0;
    const lx = R.x - R.w / 2 - m, hx = R.x + R.w / 2 + m, ly = R.y - R.h / 2 - m, hy = R.y + R.h / 2 + m;
    let t0 = 0, t1 = 1;
    if (Math.abs(dx) < 1e-9) { if (x0 < lx || x0 > hx) return false; }
    else {
      let a = (lx - x0) / dx, b = (hx - x0) / dx;
      if (a > b) { const t = a; a = b; b = t; }
      t0 = Math.max(t0, a); t1 = Math.min(t1, b);
      if (t0 > t1) return false;
    }
    if (Math.abs(dy) < 1e-9) { if (y0 < ly || y0 > hy) return false; }
    else {
      let a = (ly - y0) / dy, b = (hy - y0) / dy;
      if (a > b) { const t = a; a = b; b = t; }
      t0 = Math.max(t0, a); t1 = Math.min(t1, b);
      if (t0 > t1) return false;
    }
    return true;
  }
  function ptSeg(px, py, s) {
    const dx = s[2] - s[0], dy = s[3] - s[1], l2 = dx * dx + dy * dy;
    let t = l2 ? ((px - s[0]) * dx + (py - s[1]) * dy) / l2 : 0;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(px - (s[0] + dx * t), py - (s[1] + dy * t));
  }
  function segCross(a, b) {
    const o = (ax, ay, bx, by, cx, cy) => (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    const d1 = o(a[0], a[1], a[2], a[3], b[0], b[1]), d2 = o(a[0], a[1], a[2], a[3], b[2], b[3]);
    const d3 = o(b[0], b[1], b[2], b[3], a[0], a[1]), d4 = o(b[0], b[1], b[2], b[3], a[2], a[3]);
    return d1 * d2 < 0 && d3 * d4 < 0;
  }
  function segSeg(a, b) {
    if (segCross(a, b)) return 0;
    return Math.min(ptSeg(a[0], a[1], b), ptSeg(a[2], a[3], b), ptSeg(b[0], b[1], a), ptSeg(b[2], b[3], a));
  }
  // do two lollipops come closer than g? (box↔box, corridor↔box and corridor↔corridor are all checked)
  function lHit(A, B, g) {
    if (A.bx1 + g <= B.bx0 || B.bx1 + g <= A.bx0 || A.by1 + g <= B.by0 || B.by1 + g <= A.by0) return false;
    if (Math.max(Math.abs(A.x - B.x) - (A.w + B.w) / 2, Math.abs(A.y - B.y) - (A.h + B.h) / 2) < g) return true;
    if (A.seg && segBox(A.seg, B, A.hw + g)) return true;
    if (B.seg && segBox(B.seg, A, B.hw + g)) return true;
    if (A.seg && B.seg && segSeg(A.seg, B.seg) < A.hw + B.hw + g) return true;
    return false;
  }
  // a node and its direct parent are one connected shape, so that pair is never counted as a collision
  const lexempt = (a, b) => a === b || a.parent === b || b.parent === a;
  // nearest point of lollipop O to the point (x,y), and its distance (negative = inside)
  function nearestOnL(O, x, y) {
    const qx = Math.max(O.x - O.w / 2, Math.min(O.x + O.w / 2, x)), qy = Math.max(O.y - O.h / 2, Math.min(O.y + O.h / 2, y));
    let best = { x: qx, y: qy, d: Math.hypot(x - qx, y - qy) };
    if (O.seg) {
      const s = O.seg, dx = s[2] - s[0], dy = s[3] - s[1], l2 = dx * dx + dy * dy;
      let t = l2 ? ((x - s[0]) * dx + (y - s[1]) * dy) / l2 : 0;
      t = Math.max(0, Math.min(1, t));
      const sx = s[0] + dx * t, sy = s[1] + dy * t, dd = Math.hypot(x - sx, y - sy) - O.hw;
      if (dd < best.d) best = { x: sx, y: sy, d: dd };
    }
    return best;
  }

  /* ---------- layout (+ strict minimum distance between all lollipops) ---------- */
  function stretchMin(list, L) {
    L = Math.max(1, L || 1);
    for (const n of list) {
      if (!n.parent) { n.ux = 0; n.uy = 0; }
      else {
        const lm = lvMul(n), user = n.ov != null ? n.ov : lm;
        const m = user != null ? user : (n.au != null ? n.au : 1);
        const vx = n.dx * m, vy = n.dy * m, len = Math.hypot(vx, vy);
        const a0 = len > 1e-6 ? Math.atan2(vy, vx) : (n.ang || 0);
        const ang = a0 + (n.ba || 0) + (n.ta || 0);                 // ba = manual rotation, ta = guardrail rotation
        const ux = Math.cos(ang), uy = Math.sin(ang);
        const need = sepAlong(n.parent, n, ux, uy, MINGAP) / L;     // parent and child: exact, even at corners
        const len2 = Math.max(len, need, n.fl || 0, n.bf || 0);     // fl = guardrail clearance, bf = manual clearance
        n.ux = n.parent.ux + ux * len2;
        n.uy = n.parent.uy + uy * len2;
      }
      n.x = n.ux * L; n.y = n.uy * L;
    }
  }
  // tries to clear one lollipop collision by moving mv: out along its own line, or swung round its parent.
  // `tanFirst` (used for siblings) tries the swing first, because lines that start at the same parent
  // can only be pulled apart by changing their angle. A swing never passes a neighbouring sibling, and never
  // crosses the parent's own line: the sibling sequence stays as it is.
  function nudgeNode(mv, Do, L, tanFirst) {
    const p = mv.parent, dx = mv.x - p.x, dy = mv.y - p.y, r0 = Math.hypot(dx, dy);
    if (r0 < 1e-6) return false;
    const a0 = Math.atan2(dy, dx);
    const cross = dx * (Do.y - p.y) - dy * (Do.x - p.x);
    const s1 = cross > 0 ? -1 : 1;                                   // swing away from the other lollipop
    const sb = seqBounds(mv);
    const ok = (r, a) => !lHit(mkL(mv, p.x + Math.cos(a) * r, p.y + Math.sin(a) * r, p.x, p.y, 1, 1), Do, MINGAP);
    const radial = () => {
      for (let k = 1; k <= 110; k++) { const r = r0 + 3 * k; if (ok(r, a0)) { mv.fl = Math.max(mv.fl || 0, r / L); return true; } }
      return false;
    };
    const swing = () => {
      for (const s of [s1, -s1]) for (let k = 1; k <= 110; k++) {
        const a = a0 + s * 0.015 * k;
        if (sb) { const kk = seqKey(p, a); if (kk <= sb[0] + 0.01 || kk >= sb[1] - 0.01) break; }   // would pass a neighbour: stop this way
        if (ok(r0, a)) { mv.ta = (mv.ta || 0) + s * 0.015 * k; return true; }
      }
      return false;
    };
    return tanFirst ? (swing() || radial()) : (radial() || swing());
  }
  // guardrail: no two lollipops of a map may ever come closer than MINGAP (0.25 grid squares).
  // Lines count as active elements, so sibling lines are spread apart by angle, not only boxes by distance.
  // Candidate pairs come from a sweep along x, so the check stays quick on large maps.
  function separateTree(list, L) {
    const skip = new Set();
    for (let it = 0; it < 200; it++) {
      const D = list.map(n => mkL(n, n.x, n.y, n.parent ? n.parent.x : 0, n.parent ? n.parent.y : 0, 1, 1));
      const ord = D.slice().sort((a, b) => a.bx0 - b.bx0);
      let hit = null;
      for (let i = 0; i < ord.length && !hit; i++) {
        const A = ord[i];
        for (let j = i + 1; j < ord.length; j++) {
          const B = ord[j];
          if (B.bx0 >= A.bx1 + MINGAP) break;
          if (lexempt(A.n, B.n) || !lHit(A, B, MINGAP)) continue;
          if (skip.size && skip.has(A.n.id < B.n.id ? A.n.id + ':' + B.n.id : B.n.id + ':' + A.n.id)) continue;
          hit = { A, B }; break;
        }
      }
      if (!hit) return;
      const A = hit.A, B = hit.B, a = A.n, b = B.n;
      const deeperA = a.depth > b.depth || (a.depth === b.depth && a.id > b.id);
      const order = deeperA ? [[a, B, b], [b, A, a]] : [[b, A, a], [a, B, b]];
      const sib = !!a.parent && a.parent === b.parent;
      let done = false;
      for (const [mv, Do, ot] of order) {
        if (!mv.parent || isAnc(mv, ot)) continue;                   // never move something together with the thing it collides with
        if (nudgeNode(mv, Do, L, sib)) { done = true; break; }
      }
      if (!done) { skip.add(a.id < b.id ? a.id + ':' + b.id : b.id + ':' + a.id); continue; }
      stretchMin(list, L);
    }
  }
  // positions every box. A snapped-out (floating) box rides on its source box: it keeps a fixed offset from it.
  function restretch() {
    const rootOf = new Map(), L = Math.max(1, lenK);
    lists.forEach(({ r, list }) => {
      list.forEach(n => { n.fl = 0; n.ta = 0; });        // guardrail is recomputed fresh every time
      stretchMin(list, L);
      separateTree(list, L);
      list.forEach(n => { n.rx = n.x; n.ry = n.y; rootOf.set(n, r); });
    });
    for (let pass = 0; pass < 3; pass++) {
      lists.forEach(({ r, list }) => {
        if (r !== main) {
          const s = r.src;
          if (s && rootOf.has(s) && rootOf.get(s) !== r) { r.fx = s.x + r.sox; r.fy = s.y + r.soy; }
        }
        const ox = r === main ? 0 : r.fx, oy = r === main ? 0 : r.fy;
        list.forEach(n => { n.x = n.rx + ox; n.y = n.ry + oy; });
      });
    }
    const arr = [];
    lists.forEach(({ list }) => { for (const n of list) arr.push(n); });
    setNodes(arr);
  }
  // Locks keep lines where they are no matter how the layout is recomputed.
  //  · lkv = [dx, dy, angle, parentAngleAtLock]: the whole default vector. It stays attached to its parent, so when the
  //    parent's own direction changes the locked sub-branches turn with it (they orbit the parent as one cluster).
  //  · lkl = a locked default LENGTH only: the direction may still be re-spaced by the layout, the length stays.
  // Boxes without a lock take the fresh layout, turned to match the locked box above them.
  function applyLocks(list) {
    const rot = new Map();
    for (const n of list) {                                // pre-order: parents come first
      const p = n.parent;
      if (!p) { rot.set(n, 0); continue; }
      const pr = rot.get(p) || 0;
      let r = pr;
      if (n.lkv) {
        const ref = n.lkv.length > 3 ? n.lkv[3] : null;    // older locks have no reference and stay absolute
        const d = ref != null ? normA((p.ang || 0) - ref) : 0;
        const c = Math.cos(d), s = Math.sin(d), x = n.lkv[0], y = n.lkv[1], fa = n.ang || 0;
        n.dx = x * c - y * s; n.dy = x * s + y * c; n.ang = n.lkv[2] + d;
        r = n.ang - fa;
      } else {
        if (pr) {
          const c = Math.cos(pr), s = Math.sin(pr), x = n.dx, y = n.dy;
          n.dx = x * c - y * s; n.dy = x * s + y * c; n.ang = (n.ang || 0) + pr;
        }
        if (n.lkl != null) {
          const m0 = Math.hypot(n.dx, n.dy);
          if (m0 > 1e-6) { const q = n.lkl / m0; n.dx *= q; n.dy *= q; }
        }
      }
      rot.set(n, r);
    }
  }
  function layoutAll() {
    if (!main) { setNodes([]); lists = []; return; }
    const roots = [main].concat(floats), stash = [];
    roots.forEach(r => (function w(n) {
      if (n.hideKids && n.children.length) { stash.push([n, n.children]); n.children = []; }
      else n.children.forEach(w);
    })(r));
    lists = roots.map(r => ({ r, list: layout(r, lenK, levels) }));
    lists.forEach(({ list }) => applyLocks(list));
    stash.forEach(s => { s[0].children = s[1]; });
    restretch();
  }

  /* ---------- keeping lines as they are while the layout changes around them ---------- */
  const mkLock = n => [n.dx, n.dy, n.ang || 0, n.parent ? (n.parent.ang || 0) : 0];
  // every line of the map (except `skip`) keeps its vector exactly
  function lockAllLines(skip) {
    walkAll(n => {
      if (n.parent && !(skip && skip.has(n)) && !n.lkv && Number.isFinite(n.dx) && Number.isFinite(n.dy)) { n.lkv = mkLock(n); n.lkl = undefined; }
    });
  }
  // Used when a box leaves (snap out, delete) or arrives (add) under `parent`:
  //  · the other children of `parent` keep the LENGTH they have right now but re-space in angle to fill or share the gap
  //  · every other line in the map keeps its vector, so nothing else stretches or turns
  function freezeFor(parent, gone) {
    const L = Math.max(1, lenK);
    walkAll(n => {
      if (!n.parent || gone.has(n) || !nodeSet.has(n)) return;
      if (n.parent === parent) {
        const m = effMul(n), act = Math.hypot(n.x - parent.x, n.y - parent.y) / L;
        if (Number.isFinite(act) && act > 1e-6) n.lkl = m > 0.05 ? act / m : Math.hypot(n.dx, n.dy);
        n.lkv = undefined; n.ba = undefined; n.bf = undefined;
      } else if (!n.lkv && Number.isFinite(n.dx) && Number.isFinite(n.dy)) { n.lkv = mkLock(n); n.lkl = undefined; }
    });
  }

  /* ---------- manual fix: pull over-long lines back in ---------- */
  // true if moving branch S (boxes + connectors) now touches anything outside it
  function clash(S, others, g) {
    for (const a of S) for (const b of others) if (hitR(a, b, g)) return true;
    for (const a of S) { const p = a.parent; if (!p) continue; for (const b of others) if (b !== p && segHitsBox(p, a, b, 2)) return true; }
    for (const b of others) { const p = b.parent; if (!p) continue; for (const a of S) if (a !== p && segHitsBox(p, b, a, 2)) return true; }
    return false;
  }
  // slides box c (and everything beyond it) toward its parent, as far as it can go without touching anything
  function tighten(c, vis) {
    const p = c.parent;
    if (!p || !vis.has(c) || !vis.has(p)) return false;
    if (c.ov != null || lvMul(c) != null) return false;               // never override lengths the user chose
    const vx = c.x - p.x, vy = c.y - p.y, cur = Math.hypot(vx, vy);
    if (cur < 1) return false;
    const ux = vx / cur, uy = vy / cur;
    const base = Math.hypot(c.dx, c.dy);
    if (base < 1e-6) return false;
    const tmin = sepAlong(p, c, ux, uy, EDGE_GAP);
    if (!(cur > tmin + 3)) return false;
    const Sset = branchOf(c, vis), inS = new Set(Sset), others = nodes.filter(n => !inS.has(n));
    for (let t = tmin; t < cur - 2; t += 3) {
      const sh = cur - t;
      Sset.forEach(n => { n.x -= ux * sh; n.y -= uy * sh; });
      if (!clash(Sset, others, TIDY_GAP)) { c.au = (t / Math.max(1, lenK)) / base; return true; }   // automatic, not a user setting
      Sset.forEach(n => { n.x += ux * sh; n.y += uy * sh; });
    }
    return false;
  }
  // button "fix line lengths": clears leftover clearance in the chosen branch, then pulls every line as short as it safely goes
  function fixLengths(src) {
    try {
      if (!src || !nodeSet.has(src)) return false;
      const vis = nodeSet, Alist = branchOf(src, vis);
      let changed = false;
      Alist.forEach(n => { if (n.parent && (n.bf != null || n.au != null)) { n.bf = undefined; n.au = undefined; changed = true; } });
      if (changed) restretch();
      for (const n of Alist) if (n.parent && tighten(n, vis)) changed = true;
      if (changed) { restretch(); if (selected && selected.parent) syncLineUI(selected); touch(); }
      return changed;
    } catch (err) { console.error(err); return false; }
  }

  /* ---------- manual fix: directions ---------- */
  // button "fix directions": every box's sub-branches are re-fanned evenly, pointing outward from where its own line came from
  function fixDirection(src) {
    try {
      if (!src || !nodeSet.has(src)) return false;
      const vis = nodeSet, Alist = branchOf(src, vis), abs = new Map();
      let changed = false;
      for (const m of Alist) {
        const kids = m.children.filter(c => vis.has(c)), k = kids.length;
        if (!k) continue;
        const axis = m.parent ? (abs.has(m) ? abs.get(m) : Math.atan2(m.y - m.parent.y, m.x - m.parent.x)) : -Math.PI / 2;
        const span = Math.min(3.4, 0.55 * k + 0.3);
        kids.forEach((c, i) => {
          let ang;
          if (!m.parent) ang = -Math.PI / 2 + (i / k) * Math.PI * 2;     // a centre box: spread all the way round
          else if (k === 1) ang = axis;
          else ang = axis - span / 2 + span * i / (k - 1);
          const ba = normA(ang - baseAngle(c));
          if (Math.abs((c.ba || 0) - ba) > 0.01) changed = true;
          c.ba = ba; abs.set(c, ang);
        });
      }
      if (changed) { restretch(); if (selected && selected.parent) syncLineUI(selected); touch(); }
      return changed;
    } catch (err) { console.error(err); return false; }
  }

  /* ---------- manual fix: radial bloom physics for the chosen branch, inside a dynamic circular barrier ---------- */
  // Each box of the branch becomes a body (own offset d, velocity, mass = size of the sub-branch it carries).
  //  · radial force field from the chosen (source) box:  F_i = unit(P_i − P_src) · m_i · a_push, a_i = F_i / m_i,
  //    applied only to bodies whose lollipop is currently in a collision, tapering with depth
  //  · taper:  r_i = r_root · (1 − i/N), i = depth below the source; it sizes the circle-to-circle penetration
  //    that decides how hard colliding pairs are pushed apart
  //  · integrator: Velocity Verlet, followed by several constraint passes per step, until nothing touches
  //  · barrier: an invisible circle holds the chosen box and every descendant. Its radius comes from the total
  //    text length of the branch (as glyph area × spread, + 15% buffer); it is never smaller than the branch's
  //    present extent. Its centre is shifted away from every lollipop outside the branch, so nothing inside can
  //    be pushed onto an outside box or line. If the branch still cannot be untangled the barrier widens a little.
  //  · the result is saved into each box's rotation (ba) and clearance (bf), so it survives re-layouts
  //  · if the result would put a box past a neighbouring sibling, that parent's children get their old placement back
  function bloom(src) {
    try {
      if (!src || !nodeSet.has(src)) return false;
      const vis = nodeSet, Alist = branchOf(src, vis), A = new Set(Alist);
      const bodies = Alist.filter(n => n.parent);
      if (!bodies.length) return false;
      const Lk = Math.max(1, lenK), sc = n => (A.has(n) ? BULGE : 1);
      const myRoot = rootOfNode(src);
      const prevAdj = new Map(Alist.map(n => [n, [n.ba, n.bf]]));
      const R = new Map(nodes.map(n => [n, { x: n.x, y: n.y }]));
      const d = new Map(), vel = new Map(), mass = new Map();
      bodies.forEach(n => { d.set(n, { x: 0, y: 0 }); vel.set(n, { x: 0, y: 0 }); mass.set(n, branchOf(n, vis).length); });

      // boxes outside the branch never move (only those of the same map count: a floating box may overlap others)
      const stat = [];
      nodes.forEach(n => {
        if (A.has(n) || rootOfNode(n) !== myRoot) return;
        stat.push(mkL(n, n.x, n.y, n.parent ? n.parent.x : 0, n.parent ? n.parent.y : 0, 1, 1));
      });

      let maxRel = 0; bodies.forEach(n => { maxRel = Math.max(maxRel, n.depth - src.depth); });
      const N = maxRel + 2;                                              // keeps r_i > 0 at the deepest level
      const taper = n => 1 - (n.depth - src.depth) / N;
      const rRoot = Math.max(...Alist.map(n => n.rad || 0)) * BULGE;
      const circ = n => (A.has(n) ? Math.min((n.rad || 0) * BULGE, rRoot * taper(n)) : (n.rad || 0)) * BLOOM.CIRC;
      const hd = n => (Math.hypot(n.w, n.h) / 2) * sc(n);                // half-diagonal of a (bulged) box

      function frame() {
        const pos = new Map();
        nodes.forEach(n => { if (!A.has(n)) pos.set(n, R.get(n)); });
        for (const n of Alist) {                                         // pre-order: parents before children
          const r = R.get(n);
          if (!n.parent) { pos.set(n, { x: r.x, y: r.y }); continue; }
          const pp = pos.get(n.parent), rp = R.get(n.parent), dd = d.get(n);
          let x = pp.x + (r.x - rp.x) + dd.x, y = pp.y + (r.y - rp.y) + dd.y;
          let vx = x - pp.x, vy = y - pp.y, len = Math.hypot(vx, vy);
          if (len < 1e-6) { vx = r.x - rp.x; vy = r.y - rp.y; len = Math.hypot(vx, vy) || 1; }
          const ux = vx / len, uy = vy / len;
          const req = sepAlong({ w: n.parent.w * sc(n.parent), h: n.parent.h * sc(n.parent) }, { w: n.w * sc(n), h: n.h * sc(n) }, ux, uy, MINGAP);
          if (len < req) { const f = req - len; dd.x += ux * f; dd.y += uy * f; x += ux * f; y += uy * f; }
          pos.set(n, { x, y });
        }
        const Ls = Alist.map(n => {
          const pn = pos.get(n), pp = n.parent ? pos.get(n.parent) : null;
          return mkL(n, pn.x, pn.y, pp ? pp.x : 0, pp ? pp.y : 0, sc(n), n.parent ? sc(n.parent) : 1);
        });
        const pairs = [];
        for (let i = 0; i < Ls.length; i++) {
          for (let j = i + 1; j < Ls.length; j++) {
            if (lexempt(Ls[i].n, Ls[j].n)) continue;
            if (lHit(Ls[i], Ls[j], MINGAP)) pairs.push([Ls[i], Ls[j]]);
          }
          for (const o of stat) {
            if (lexempt(Ls[i].n, o.n)) continue;
            if (lHit(Ls[i], o, MINGAP)) pairs.push([Ls[i], o]);
          }
        }
        return { pos, pairs };
      }
      function accel(st) {
        const out = new Map(), conf = new Set();
        st.pairs.forEach(p => { conf.add(p[0].n); conf.add(p[1].n); });
        const ps = st.pos.get(src);
        bodies.forEach(n => {
          if (!conf.has(n)) { out.set(n, { x: 0, y: 0 }); return; }
          const pn = st.pos.get(n);
          let fx, fy;
          if (n === src) { const pp = st.pos.get(n.parent); fx = pn.x - pp.x; fy = pn.y - pp.y; }     // source box: out along its own line
          else { fx = pn.x - ps.x; fy = pn.y - ps.y; }                                                // everyone else: away from the source box
          let l = Math.hypot(fx, fy);
          if (l < 1e-6) { fx = R.get(n).x - R.get(src).x; fy = R.get(n).y - R.get(src).y; l = Math.hypot(fx, fy) || 1; }
          const m = mass.get(n), F = BLOOM.PUSH * m * taper(n);                                       // F_i = m_i · a_push (tapered)
          out.set(n, { x: (fx / l) * F / m, y: (fy / l) * F / m });                                   // a_i = F_i / m_i
        });
        return out;
      }
      function project(st) {
        st.pairs.forEach(([a, b]) => {
          let ux = a.x - b.x, uy = a.y - b.y, dist = Math.hypot(ux, uy);
          if (dist < 1e-6) { ux = 0; uy = -1; dist = 0; } else { ux /= dist; uy /= dist; }
          const pen = circ(a.n) + circ(b.n) - dist;                      // circle-to-circle penetration with tapered radii
          const s = Math.max(2, Math.min(10, pen * 0.15));
          const wa = d.has(a.n) ? 1 / mass.get(a.n) : 0, wb = d.has(b.n) ? 1 / mass.get(b.n) : 0, tot = wa + wb;
          if (!tot) return;
          if (wa) { const q = d.get(a.n); q.x += ux * s * wa / tot; q.y += uy * s * wa / tot; }
          if (wb) { const q = d.get(b.n); q.x -= ux * s * wb / tot; q.y -= uy * s * wb / tot; }
        });
      }

      let st = frame();

      /* ----- the invisible circular barrier ----- */
      const obst = stat.filter(o => o.n !== src.parent);                 // everything outside the branch (its own parent is attached, so exempt)
      let bar = null;
      function fitBar() {
        const ps = st.pos.get(src), hs = hd(src);
        for (let k = 0; k < 60; k++) {
          let wd = 0, wp = null;
          for (const o of obst) {
            const np = nearestOnL(o, bar.x, bar.y), def = bar.R + MINGAP - np.d;
            if (def > wd + 1e-6) { wd = def; wp = np; }
          }
          if (!wp) break;
          let ux = bar.x - wp.x, uy = bar.y - wp.y, l = Math.hypot(ux, uy);
          if (l < 1e-6) { ux = bar.x - ps.x; uy = bar.y - ps.y; l = Math.hypot(ux, uy) || 1; }
          bar.x += (ux / l) * wd; bar.y += (uy / l) * wd;
          const dc = Math.hypot(bar.x - ps.x, bar.y - ps.y), ex = dc + hs - bar.R;
          if (ex > 0 && dc > 1e-6) { bar.x -= ((bar.x - ps.x) / dc) * ex; bar.y -= ((bar.y - ps.y) / dc) * ex; }
        }
      }
      function contain(stt) {
        if (!bar) return false;
        const sh = new Map(); let moved = false;
        for (const n of Alist) {
          const ps = (n.parent && sh.get(n.parent)) || { x: 0, y: 0 };
          const q = stt.pos.get(n), ex = q.x + ps.x, ey = q.y + ps.y;
          let ax = 0, ay = 0;
          const dd = d.get(n);
          if (dd) {
            const dx = ex - bar.x, dy = ey - bar.y, dist = Math.hypot(dx, dy), lim = bar.R - hd(n);
            if (dist > lim && dist > 1e-6) { const f = dist - lim; ax = -(dx / dist) * f; ay = -(dy / dist) * f; dd.x += ax; dd.y += ay; moved = true; }
          }
          sh.set(n, { x: ps.x + ax, y: ps.y + ay });
        }
        return moved;
      }
      if (Alist.length > 1) {
        let cx = 0, cy = 0;
        Alist.forEach(n => { const q = st.pos.get(n); cx += q.x; cy += q.y; });
        cx /= Alist.length; cy /= Alist.length;
        let rInit = 0;
        Alist.forEach(n => { const q = st.pos.get(n); rInit = Math.max(rInit, Math.hypot(q.x - cx, q.y - cy) + hd(n)); });
        let area = 0;                                                    // total text of the branch, as glyph area
        Alist.forEach(n => { area += Math.max(1, n.text.length) * (n.fs * 0.56) * n.lh; });
        const rCap = BAR.BUF * Math.sqrt(BAR.SPREAD * area / Math.PI);   // capacity radius with the 15% buffer
        bar = { x: cx, y: cy, R: Math.max(rCap, rInit + MINGAP) };       // never smaller than what the branch already occupies
        fitBar();
      }

      const dt = BLOOM.DT;
      for (let g = 0; g <= BAR.GROW; g++) {
        for (let it = 0; it < BLOOM.ITER; it++) {
          if (!st.pairs.length) break;
          const a1 = accel(st);
          bodies.forEach(n => {                                          // Velocity Verlet: position step
            const q = d.get(n), v = vel.get(n), a = a1.get(n);
            q.x += v.x * dt + 0.5 * a.x * dt * dt; q.y += v.y * dt + 0.5 * a.y * dt * dt;
          });
          const st2 = frame(), a2 = accel(st2);
          bodies.forEach(n => {                                          // Velocity Verlet: velocity step (+ damping)
            const v = vel.get(n), a = a1.get(n), b = a2.get(n);
            v.x = (v.x + 0.5 * (a.x + b.x) * dt) * BLOOM.DAMP; v.y = (v.y + 0.5 * (a.y + b.y) * dt) * BLOOM.DAMP;
          });
          st = st2;
          if (contain(st)) st = frame();                                 // nothing may leave the barrier
          for (let k = 0; k < BLOOM.PASSES && st.pairs.length; k++) { project(st); contain(st); st = frame(); }   // constraint passes
        }
        if (!st.pairs.length || !bar || g === BAR.GROW) break;
        bar.R *= BAR.STEP; fitBar();                                     // still tangled: widen the barrier a little and shift it clear again
      }

      // save the result into the boxes that actually moved
      const stF = frame();
      let changed = false;
      for (const n of Alist) {
        if (!n.parent) continue;
        const dd = d.get(n);
        if (Math.hypot(dd.x, dd.y) < BLOOM.MOVE_MIN) continue;
        const pn = stF.pos.get(n), pp = stF.pos.get(n.parent);
        const vx = pn.x - pp.x, vy = pn.y - pp.y, len = Math.hypot(vx, vy);
        if (len < 1e-6) continue;
        const lm = lvMul(n), user = n.ov != null ? n.ov : lm, m = user != null ? user : (n.au != null ? n.au : 1);
        const bx = n.dx * m, by = n.dy * m, blen = Math.hypot(bx, by);
        const a0 = blen > 1e-6 ? Math.atan2(by, bx) : (n.ang || 0);
        n.ba = normA(Math.atan2(vy, vx) - a0);
        const ul = len / Lk;
        n.bf = ul > blen * 1.0001 ? ul : undefined;
        changed = true;
      }
      if (changed) {
        restretch();
        // the sibling sequence has to survive: a parent whose children got out of order gets its old placement back
        const bad = new Set();
        Alist.forEach(n => { if (n.parent && !bad.has(n.parent) && seqBad(n.parent)) bad.add(n.parent); });
        if (bad.size) {
          Alist.forEach(n => { if (n.parent && bad.has(n.parent)) { const q = prevAdj.get(n); n.ba = q[0]; n.bf = q[1]; } });
          restretch();
        }
        if (selected && selected.parent) syncLineUI(selected);
        touch();
      }
      return changed;
    } catch (err) { console.error(err); return false; }
  }

  function runFix(kind) {
    const n = selected;
    if (!n || !nodeSet.has(n) || dnode || mover) return;
    let ok = false, label;
    if (kind === 'o') { ok = bloom(n); label = 'overlaps'; }
    else if (kind === 'l') { ok = fixLengths(n); label = 'line lengths'; }
    else { ok = fixDirection(n); label = 'directions'; }
    render();
    if (n.parent) syncLineUI(n);
    buildLevelControls();
    placeBar();
    statusEl.textContent = ok ? 'Fixed ' + label + ' in this branch.' : 'Nothing to fix (' + label + ') in this branch.';
  }
  nbFixO.onclick = () => runFix('o');
  nbFixL.onclick = () => runFix('l');
    nbFixD.onclick = () => runFix('d');

  /* ---------- re-vector: re-align the sub-branches around the selected box ---------- */
  // The order of the children (the sequence) is never changed here, so manual swaps and drops are kept.
  // Around a box that has a parent line, the children are fanned in that order from one flank of that line to the
  // other (first child on one side, last on the other). The fan widens with every extra child until the first
  // and last sit right beside the parent's line. Around a centre box the sequence is spread evenly round the
  // circle, starting at the top. Every sub-branch turns together with its box.
  function reVector(src) {
    try {
      if (!src || !nodeSet.has(src)) return false;
      const kids = src.children.filter(c => nodeSet.has(c)), k = kids.length;
      if (!k) return false;
      const T = Math.PI * 2, root = !src.parent;
      const out = root ? -Math.PI / 2 : Math.atan2(src.y - src.parent.y, src.x - src.parent.x);   // points away from the parent line
      const span = root ? T : Math.min(T - 2 * 0.42, 0.95 * (k - 1));
      const plan = kids.map((c, i) => {
        const tgt = root ? out + T * i / k : (k === 1 ? out : out - span / 2 + span * i / (k - 1));
        const cur = Math.atan2(c.y - src.y, c.x - src.x);
        return { c, delta: normA(tgt - cur), ba: normA(tgt - baseAngle(c)) };
      });
      let changed = false;
      plan.forEach(q => {
        if (Math.abs(q.delta) > 0.005 || Math.abs((q.c.ba || 0) - q.ba) > 0.005) changed = true;
        q.c.ba = q.ba;
        if (Math.abs(q.delta) > 1e-6) (function w(x) { x.children.forEach(e => { e.ba = normA((e.ba || 0) + q.delta); w(e); }); })(q.c);
      });
      if (changed) { restretch(); if (selected && selected.parent) syncLineUI(selected); touch(); }
      return changed;
    } catch (err) { console.error(err); return false; }
  }
  nbRev.onclick = () => {
    const n = selected;
    if (!n || !nodeSet.has(n) || dnode || mover) return;
    const ok = reVector(n);
    render();
    if (n.parent) syncLineUI(n);
    buildLevelControls(); placeBar();
    statusEl.textContent = ok ? 'Re-vectored: the sub-branches are re-aligned around this box. Their order is unchanged.' : 'Nothing to re-vector here (already aligned, or no visible sub-branches).';
  };


  /* ---------- draw the graph into a <g> (used by screen AND pdf) ---------- */
  // the connector line(s) between a box and its parent; a gradient is drawn as short solid segments
  function edgeInto(n, grp) {
    const p = n.parent, a = borderPoint(p, n), b = borderPoint(n, p), col = TYPES[n.type].color;
    const w = Math.max(1.8, 4.2 - 0.6 * n.depth), STEPS = 10;
    if (isGrad(n)) {
      for (let i = 0; i < STEPS; i++) {
        const t0 = i / STEPS, t1 = (i + 1) / STEPS;
        S('path', {
          d: 'M' + (a.x + (b.x - a.x) * t0) + ' ' + (a.y + (b.y - a.y) * t0) +
             'L' + (a.x + (b.x - a.x) * t1) + ' ' + (a.y + (b.y - a.y) * t1),
          fill: 'none', stroke: mix(TEAL, col, (i + 0.5) / STEPS),
          'stroke-width': w, 'stroke-linecap': 'round'
        }, grp);
      }
    } else {
      S('path', { d: 'M' + a.x + ' ' + a.y + 'L' + b.x + ' ' + b.y, fill: 'none', stroke: col, 'stroke-width': w, 'stroke-linecap': 'round' }, grp);
    }
  }
  function drawGraph(list, g, defs, pre) {
    const eg = S('g', {}, g), ng = S('g', {}, g);
    const els = { nodes: new Map(), edges: new Map() };

    for (const n of list) {
      if (!n.parent) continue;
      const grp = S('g', { 'class': 'edge' }, eg);
      edgeInto(n, grp);
      els.edges.set(n.id, grp);
    }

    for (const n of list) {
      const grp = S('g', { 'data-id': n.id, 'class': 'node', style: 'cursor:pointer' }, ng);
      if (pre === 's') { n.dpx = n.x; n.dpy = n.y; }              // where it was drawn (live moves shift it with a transform)
      const col = TYPES[n.type].color;
      let fill = col, tc;
      if (isGrad(n) && n.parent) {
        const id = pre + 'ng' + n.id;
        let ux = n.parent.x - n.x, uy = n.parent.y - n.y; const L = Math.hypot(ux, uy) || 1; ux /= L; uy /= L;
        const lg = S('linearGradient', { id, x1: 0.5 + 0.5 * ux, y1: 0.5 + 0.5 * uy, x2: 0.5 - 0.5 * ux, y2: 0.5 - 0.5 * uy }, defs);
        S('stop', { offset: '0', 'stop-color': TEAL }, lg);
        S('stop', { offset: '1', 'stop-color': col }, lg);
        fill = 'url(#' + id + ')';
        tc = textColor([TEAL, col]);
      } else tc = textColor([col]);

      const rx = n.depth === 0 ? 18 : 10;
      S('rect', {
        x: n.x - n.w / 2, y: n.y - n.h / 2, width: n.w, height: n.h, rx,
        fill, stroke: dark ? '#ffffff' : '#000000', 'stroke-opacity': dark ? 0.22 : 0.12, 'stroke-width': 1
      }, grp);
      if (n.cover) {                                    // active-recall "patch tape"
        S('rect', { x: n.x - n.w / 2, y: n.y - n.h / 2, width: n.w, height: n.h, rx, fill: '#F4E7B0', stroke: '#C9B26B', 'stroke-width': 1.5 }, grp);
        S('line', { x1: n.x - n.w / 2 + 8, y1: n.y - n.h / 2 + 8, x2: n.x + n.w / 2 - 8, y2: n.y + n.h / 2 - 8, stroke: '#C9B26B', 'stroke-width': 1.5, 'stroke-opacity': 0.7 }, grp);
      } else {
        n.lines.forEach((ln, i) => {
          const t = S('text', {
            x: n.x, y: n.y - n.h / 2 + n.padY + i * n.lh + n.lh / 2 + n.fs * 0.35,
            'text-anchor': 'middle', 'font-family': FONT, 'font-size': n.fs, 'font-weight': n.fontWeight, fill: tc
          }, grp);
          t.textContent = ln;
        });
      }
      els.nodes.set(n.id, grp);
    }
    return els;
  }

  function clearIndicator() { indEls.forEach(e => e.remove()); indEls = []; }
  function drawIndicator() {
    clearIndicator();
    if (!dnode || !target || !world) return;
    const m = target.n, d = dnode;
    if (target.kind === 'connect') {
      const a = borderPoint(m, d), b = borderPoint(d, m);
      indEls.push(S('line', { x1: a.x, y1: a.y, x2: b.x, y2: b.y, stroke: '#2A9D8F', 'stroke-width': 6, 'stroke-linecap': 'round', 'stroke-opacity': 0.45 }, world));
    }
    indEls.push(S('rect', {
      x: m.x - m.w / 2 - 4, y: m.y - m.h / 2 - 4, width: m.w + 8, height: m.h + 8, rx: 14, fill: 'none',
      stroke: '#2A9D8F', 'stroke-width': 3, 'stroke-opacity': 0.55, 'stroke-dasharray': target.kind === 'merge' ? '6 4' : '0'
    }, world));
  }

  function render() {
    svg.innerHTML = '';
    indEls = [];
    const defs = S('defs', {}, svg);
    world = S('g', {}, svg);
    const els = drawGraph(nodes, world, defs, 's');
    nodeEls = els.nodes; edgeEls = els.edges;
    floats.forEach(f => { const el = nodeEls.get(f.id); if (el) el.style.filter = 'drop-shadow(0 6px 8px rgba(0,0,0,.35))'; });
    if (mover) { const el = nodeEls.get(mover.n.id); if (el) el.style.filter = 'drop-shadow(0 8px 10px rgba(0,0,0,.4))'; }
        drawIndicator();
    applyCamLock();
    applyView();
    applySelection();
    if (window.MMP && window.MMP.onRender) window.MMP.onRender();
    if (window.MMM && window.MMM.onRender) window.MMM.onRender();

    syncTape();
  }
  let raf = 0;
  const scheduleRender = () => { if (!raf) raf = requestAnimationFrame(() => { raf = 0; render(); }); };

  /* ---------- fast path while a box is being moved: only the moving boxes and their lines are touched ---------- */
  function quickUpdate(list) {
    if (!world) return;
    for (const n of list) {
      const g = nodeEls.get(n.id);
      if (g && n.dpx != null) g.setAttribute('transform', 'translate(' + (n.x - n.dpx) + ' ' + (n.y - n.dpy) + ')');
      const eg = edgeEls.get(n.id);
      if (eg && n.parent) { while (eg.firstChild) eg.removeChild(eg.firstChild); edgeInto(n, eg); }
    }
    drawIndicator();
  }
  const movingList = () => (mover ? mover.sub : (dnode ? [dnode] : []));
  let qraf = 0;
  const scheduleQuick = () => { if (!qraf) qraf = requestAnimationFrame(() => { qraf = 0; quickUpdate(movingList()); }); };

  /* ---------- camera lock on a merged / connected box ---------- */
  // keeps the box at the same spot on screen, however the map around it moves, until the canvas is touched again
  function holdCam(n, sx, sy) { camLock = { n, sx, sy }; applyCamLock(); }
  function applyCamLock() {
    if (!camLock) return;
    if (!nodeSet.has(camLock.n)) { camLock = null; return; }
    view.x = camLock.sx - camLock.n.x * view.k;
    view.y = camLock.sy - camLock.n.y * view.k;
  }
  function freeCam() { camLock = null; }

  /* ---------- selection hierarchy: 100% → semi-transparent → most transparent ---------- */
  function tiers(n) {
    const vis = nodeSet, t1 = new Set(), t2 = new Set();
    const addTree = (m, set) => { set.add(m); m.children.forEach(k => { if (vis.has(k)) addTree(k, set); }); };
    t1.add(n);                                                            // the chosen box + its immediate sub-branches
    n.children.forEach(c => {
      if (!vis.has(c)) return;
      t1.add(c);
      c.children.forEach(k => { if (vis.has(k)) addTree(k, t2); });       // deeper levels of the chosen branch
    });
    if (n.parent) {                                                       // the 2 closest siblings + all their descendants
      const sib = n.parent.children.filter(c => vis.has(c)), i = sib.indexOf(n), k = sib.length;
      const cyc = !n.parent.parent, cand = [];                            // around the centre box the ring wraps round
      sib.forEach((c, j) => {
        if (j === i) return;
        let d = Math.abs(j - i); if (cyc) d = Math.min(d, k - d);
        cand.push({ c, d, j });
      });
      cand.sort((a, b) => a.d - b.d || a.j - b.j);
      cand.slice(0, 2).forEach(o => addTree(o.c, t2));
    }
    return { t1, t2 };
  }
  function applySelection() {
    const sel = selected && nodeSet.has(selected) ? selected : null;
    if (!sel) {
      nodeEls.forEach(el => { el.classList.remove('dim'); el.classList.remove('semi'); });
      edgeEls.forEach(el => { el.classList.remove('dim'); el.classList.remove('semi'); });
      return;
    }
    const { t1, t2 } = tiers(sel), map = new Map(nodes.map(n => [n.id, n]));
    const lvl = m => (m && t1.has(m) ? 0 : (m && t2.has(m) ? 1 : 2));
    nodeEls.forEach((el, id) => {
      const l = lvl(map.get(id));
      el.classList.toggle('semi', l === 1); el.classList.toggle('dim', l === 2);
    });
    edgeEls.forEach((el, id) => {
      const m = map.get(id); let l = lvl(m);
      if (m === sel && l === 0) l = 1;                                    // the line coming into the chosen box
      el.classList.toggle('semi', l === 1); el.classList.toggle('dim', l === 2);
    });
  }
  function ripple(n) {
    const base = n.depth;
    (function walk(m) {
      const el = nodeEls.get(m.id);
      if (el && el.animate) {
        el.animate(
          [{ transform: 'scale(1)' }, { transform: 'scale(' + BULGE + ')', offset: 0.4 }, { transform: 'scale(1)' }],
          { duration: 520, delay: (m.depth - base) * 130, easing: 'ease-in-out', iterations: 1 }
        );
      }
      m.children.forEach(walk);
    })(n);
  }
  // selecting only highlights and animates: nothing is moved or re-spaced (use the fix buttons for that)
  function select(n, animate) {
    selected = n; editing = n;
    if (delArm && delArm !== n) disarmDel();
    nbDel.disabled = !!n && n === main;                  // the centre box cannot be deleted
    applySelection();
    if (n) {
      typeSel.value = n.type; syncLineUI(n);
      nbDot.style.background = TYPES[n.type].color;
      nbTape.textContent = n.cover ? '👁' : '🩹';
      if (animate) ripple(n);
    }
    buildLevelControls();                                // sliders re-base on the chosen box
    syncTape();
    placeBar();
  }
  function clearSel() { editor.hidden = true; select(null, false); }

  /* ---------- floating tools: node bar, unhide button, vertical line knob on the right edge ---------- */
  const uhTarget = () => {
    const f = dnode || (selected && floats.includes(selected) ? selected : null);
    return f && f.children.length ? f : null;
  };
  function placeBar() {
    const r = canvas.getBoundingClientRect(), k = view.k;
    const ok = selected && !dnode && !mover && !editNode && nodeSet.has(selected);
    nodebar.hidden = !ok;
    if (!ok) editor.hidden = true;
    else {
      const sx = selected.x * k + view.x, sy = selected.y * k + view.y, hh = selected.h * k / 2;
      const bw = nodebar.offsetWidth || 190, bh = nodebar.offsetHeight || 44;
      let top = sy - hh - bh - 8; if (top < 4) top = sy + hh + 8;
      const left = Math.max(4, Math.min(sx - bw / 2, r.width - bw - 4));
      nodebar.style.left = left + 'px'; nodebar.style.top = top + 'px';
      if (!editor.hidden) {
        editor.style.left = left + 'px';
        editor.style.top = Math.max(4, Math.min(top + bh + 6, r.height - 90)) + 'px';
      }
    }
    // the line knob lives at the far right (CSS); it only shows while a box with an incoming line is chosen
    rpanel.hidden = !(selected && selected.parent && !dnode && !mover && !editNode && nodeSet.has(selected));
    const f = uhTarget();
    if (f && nodeSet.has(f)) {
      unhide.hidden = false;
      unhide.textContent = f.hideKids ? '▸ Show ' + countKids(f) : '▾ Hide';
      unhide.style.left = Math.max(4, f.x * k + view.x + f.w * k / 2 - 70) + 'px';
      unhide.style.top = (f.y * k + view.y + f.h * k / 2 + 6) + 'px';
    } else unhide.hidden = true;
  }

  /* ---------- infinite canvas ---------- */
  function applyView() {
    if (world) world.setAttribute('transform', `translate(${view.x} ${view.y}) scale(${view.k})`);
    const s = GRID * view.k;
    canvas.style.backgroundSize = s + 'px ' + s + 'px';
        canvas.style.backgroundPosition = view.x + 'px ' + view.y + 'px';
    if (window.MMP && window.MMP.onView) window.MMP.onView();
    if (window.MMM && window.MMM.onView) window.MMM.onView();
    if (store) store.viewSoon();

    placeBar();

  }
  function zoomAt(px, py, f) {
    const k = Math.min(4, Math.max(0.01, view.k * f)), r = k / view.k;
    view.x = px - (px - view.x) * r; view.y = py - (py - view.y) * r; view.k = k; applyView();
  }
  function fit() {
    if (!nodes.length) return;
    const b = bounds(nodes, 60), r = canvas.getBoundingClientRect();
    view.k = Math.max(0.01, Math.min(r.width / b.w, r.height / b.h, 1.5));
    view.x = r.width / 2 - (b.x + b.w / 2) * view.k;
    view.y = r.height / 2 - (b.y + b.h / 2) * view.k;
    applyView();
  }

  /* ---------- canvas-only zoom: the page itself never zooms, only the workspace does ---------- */
  ['gesturestart', 'gesturechange', 'gestureend'].forEach(ev => document.addEventListener(ev, e => e.preventDefault(), { passive: false }));
  document.addEventListener('touchmove', e => { if (e.touches && e.touches.length > 1) e.preventDefault(); }, { passive: false });
  document.addEventListener('wheel', e => { if (e.ctrlKey) e.preventDefault(); }, { passive: false, capture: true });

  const ptrs = new Map(); let drag = null, pinch = null;
  const rel = e => { const r = canvas.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top }; };
  const toWorld = p => ({ x: (p.x - view.x) / view.k, y: (p.y - view.y) / view.k });
  const inRect = (m, x, y) => Math.abs(x - m.x) <= m.w / 2 && Math.abs(y - m.y) <= m.h / 2;

  canvas.addEventListener('pointerdown', e => {
    if (e.target.closest('#toolbar') || e.target.closest('#editor') || e.target.closest('#nodebar') ||
        e.target.closest('#unhide') || e.target.closest('#nodeEdit') || e.target.closest('#masterTape') ||
        e.target.closest('#rpanel') || e.target.closest('.rot')) return;
    freeCam();                                          // touching the canvas releases the camera lock
    if (editNode) nodeEdit.blur();
    canvas.setPointerCapture(e.pointerId);
    ptrs.set(e.pointerId, rel(e));
    clearTimeout(holdT);
    if (ptrs.size === 1) {
      drag = { sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y, moved: false, target: e.target };
      const el = e.target.closest && e.target.closest('[data-id]');
      if (el) {
        const n = byId(+el.getAttribute('data-id')), p0 = rel(e);
        // hold on a connected box: move it freely (stays connected). hold on a box that is already floating: pick it up.
        if (n && n !== main && !(window.MMM && window.MMM.lock())) holdT = setTimeout(() => (n.parent ? startFree(n, p0) : startDrag(n, p0)), 450);
      }
    } else if (ptrs.size === 2) {
      drag = null;
      const [a, b] = [...ptrs.values()], m = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), k: view.k, wx: (m.x - view.x) / view.k, wy: (m.y - view.y) / view.k };
    }
  });
  canvas.addEventListener('pointermove', e => {
    if (!ptrs.has(e.pointerId)) return;
    ptrs.set(e.pointerId, rel(e));
    if (mover) { moveFree(rel(e)); return; }
    if (dnode) { moveDrag(rel(e)); return; }
    if (ptrs.size === 2 && pinch) {
      const [a, b] = [...ptrs.values()], m = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      view.k = Math.min(4, Math.max(0.01, pinch.k * Math.hypot(a.x - b.x, a.y - b.y) / pinch.d));
      view.x = m.x - pinch.wx * view.k; view.y = m.y - pinch.wy * view.k; applyView();
    } else if (drag) {
      const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
      if (Math.hypot(dx, dy) > 4) { drag.moved = true; clearTimeout(holdT); }
      if (drag.moved) { view.x = drag.vx + dx; view.y = drag.vy + dy; applyView(); }
    }
  });
  const endPtr = e => {
    clearTimeout(holdT);
    if (mover) { dropFree(); ptrs.delete(e.pointerId); drag = null; pinch = null; return; }
    if (dnode) { dropDrag(); ptrs.delete(e.pointerId); drag = null; pinch = null; return; }
    if (drag && !drag.moved && ptrs.size === 1) {
      const el = drag.target.closest && drag.target.closest('[data-id]');
      const tn = el ? byId(+el.getAttribute('data-id')) : null;
      if (window.MMM && window.MMM.lockTap && window.MMM.lockTap(tn)) { /* handled by the current mode */ }
      else if (el) tapNode(tn);
      else clearSel();
    }
    ptrs.delete(e.pointerId); drag = null; if (ptrs.size < 2) pinch = null;
  };
  canvas.addEventListener('pointerup', endPtr);
  canvas.addEventListener('pointercancel', endPtr);
  canvas.addEventListener('wheel', e => {
    e.preventDefault();
    freeCam();
    const p = rel(e);
    zoomAt(p.x, p.y, Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0015)));
  }, { passive: false });
  rpanel.addEventListener('wheel', e => e.stopPropagation(), { passive: true });

  /* ---------- tap / double-tap ---------- */
  function tapNode(n) {
    if (!n) return;
    const now = Date.now();
    if (lastTap.id === n.id && now - lastTap.t < 320) { lastTap = { id: 0, t: 0 }; startEdit(n, false); return; }
    lastTap = { id: n.id, t: now };
    select(n, true);
  }

  /* ---------- text editing ---------- */
  function startEdit(n, fresh) {
    if (editNode) commitEdit();
    editNode = n; n.fresh = !!fresh;
    select(n, false);
    const r = canvas.getBoundingClientRect(), k = view.k;
    const sx = n.x * k + view.x, sy = n.y * k + view.y;
    const w = Math.max(n.w * k, 150), h = Math.max(n.h * k, 44);
    nodeEdit.hidden = false;
    nodeEdit.style.width = w + 'px'; nodeEdit.style.height = h + 'px';
    nodeEdit.style.left = Math.max(4, Math.min(sx - w / 2, r.width - w - 4)) + 'px';
    nodeEdit.style.top = Math.max(4, sy - h / 2) + 'px';
    nodeEdit.value = fresh ? '' : n.text;
    placeBar();
    nodeEdit.focus(); nodeEdit.select();
  }
  function commitEdit() {
    if (!editNode) return;
    const n = editNode; editNode = null;
    nodeEdit.hidden = true;
    const v = nodeEdit.value.replace(/\s+/g, ' ').trim();
    if (!v) { if (n.fresh && n.parent) { n.parent.children = n.parent.children.filter(c => c !== n); selected = null; } }
    else n.text = v;
    n.fresh = false;
    layoutAll(); render(); touch();
  }
  nodeEdit.addEventListener('blur', commitEdit);
  nodeEdit.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); nodeEdit.blur(); }
    else if (e.key === 'Escape' && editNode) { nodeEdit.value = editNode.fresh ? '' : editNode.text; nodeEdit.blur(); }
  });

  /* ---------- node bar buttons ---------- */
  Object.keys(TYPES).forEach(k => {
    const o = document.createElement('option'); o.value = k; o.textContent = TYPES[k].label; typeSel.appendChild(o);
  });
  nbType.onclick = () => { if (!selected) return; editor.hidden = !editor.hidden; placeBar(); };
  typeSel.addEventListener('change', () => {
    if (!editing) return;
    editing.type = typeSel.value; nbDot.style.background = TYPES[editing.type].color;
    render(); touch();
  });
  nbAdd.onclick = () => {
    const p = selected; if (!p) return;
    const c = { id: nextId++, text: 'New', type: p.group ? 'member' : 'label', parent: p, children: [], group: false, depth: p.depth + 1, isMember: !!p.group, cover: false };
    freezeFor(p, new Set());                           // the other children keep their line length and re-space around the new box
    p.hideKids = false; p.children.push(c);
    layoutAll(); render();
    dirty = true; if (store) store.request();
    startEdit(c, true);
                                // opens the keyboard
  };
  nbTape.onclick = () => {
    if (!selected) return;
    selected.cover = !selected.cover;
    nbTape.textContent = selected.cover ? '👁' : '🩹';
    render(); touch();
  };

  /* ---------- delete the selected box (with its sub-branches) ---------- */
  function disarmDel() { clearTimeout(delT); delT = 0; delArm = null; nbDel.classList.remove('arm'); }
  function deleteBox(n) {
    if (!n || n === main) return false;
    const gone = subtreeSet(n);
    if (n.parent) {
      const p = n.parent;
      freezeFor(p, gone);                               // the remaining siblings keep their line length and re-space into the gap
      p.children = p.children.filter(c => c !== n);
    } else floats = floats.filter(f => f !== n);
    floats.forEach(f => { if (f.src && gone.has(f.src)) f.src = null; });
    selected = null; editing = null; editor.hidden = true;
    layoutAll(); render();
    select(null, false);
    touch();
    return true;
  }
  nbDel.onclick = () => {
    const n = selected; if (!n) return;
    if (n === main) { statusEl.textContent = "The centre box can't be deleted."; return; }
    const kids = countKids(n);
    if (kids && delArm !== n) {                         // a box with sub-branches needs a second tap
      disarmDel(); delArm = n; nbDel.classList.add('arm');
      statusEl.textContent = 'Tap 🗑 again to delete this box and its ' + kids + ' sub-branch' + (kids > 1 ? 'es' : '') + '. Undo (↶) brings them back.';
      delT = setTimeout(disarmDel, 3500);
      return;
    }
    disarmDel();
    deleteBox(n);
    statusEl.textContent = kids ? 'Deleted the box and its sub-branches. Undo (↶) brings them back.' : 'Deleted the box. Undo (↶) brings it back.';
  };

  /* ---------- duplicate: tap = this box alone, double-tap = the whole branch ---------- */
  function cloneBranch(o, parent, full) {
    const c = {
      id: nextId++, text: o.text, type: o.type, parent, children: [], group: !!o.group,
      depth: parent ? parent.depth + 1 : o.depth, isMember: parent ? !!o.isMember : false,
      ov: o.ov, lv: o.lv ? Object.assign({}, o.lv) : undefined, lkv: parent && o.lkv ? o.lkv.slice() : undefined,
      lkl: parent ? o.lkl : undefined, ba: parent ? o.ba : undefined,
      cover: !!o.cover, hideKids: parent ? !!o.hideKids : false
    };
    if (parent) parent.children.push(c);
    if (full) o.children.forEach(k => cloneBranch(k, c, true));
    return c;
  }
  function duplicate(full, o) {
    if (!o || !nodeSet.has(o) || dnode || mover) return;
    const c = cloneBranch(o, null, full);               // a snapped-out box: no parent
    c.hideKids = full && c.children.length > 0;         // a copied branch stays collapsed under the show button
    c.fx = o.x + o.w / 2 + 36; c.fy = o.y + o.h / 2 + 44;   // just below and to the right of the original
    c.src = o; tether(c);                               // keeps a fixed distance from the box it was copied from
    floats.push(c);
    haptic();
    layoutAll(); render();
    select(c, false);
    touch();
    statusEl.textContent = full ? 'Duplicated the whole branch (collapsed). Tap ▸ Show to open it.' : 'Duplicated this box on its own.';
  }
  let dupT = 0;
  nbDup.onclick = () => {
    if (!selected) return;
    if (dupT) { clearTimeout(dupT); dupT = 0; duplicate(true, selected); return; }   // second tap in time: whole branch
    const n = selected;
    dupT = setTimeout(() => { dupT = 0; duplicate(false, n); }, 280);                // no second tap: this box only
  };

  // big tape button: tap = cover/uncover the SELECTED box · hold = cover/uncover EVERYTHING
  function syncTape() {
    const c = !!(selected && selected.cover);
    masterTape.classList.toggle('on', c);
    masterTape.classList.toggle('idle', !selected);
    masterTape.textContent = c ? '👁' : '🩹';
    if (selected) nbTape.textContent = c ? '👁' : '🩹';
    syncRot();
  }
  let tapeT = 0;
  const tapeCancel = () => { clearTimeout(tapeT); tapeT = 0; };
  masterTape.addEventListener('pointerdown', e => {
    e.preventDefault();
    tapeCancel();
    tapeT = setTimeout(() => {
      tapeT = 0;                                        // hold fired
      haptic();
      const any = nodes.some(n => !n.cover);
      walkAll(n => { n.cover = any; });
      render(); touch();
      statusEl.textContent = any ? 'All boxes covered. Hold the tape again to uncover all.' : 'All boxes uncovered.';
    }, 500);
  });
  masterTape.addEventListener('pointerup', () => {
    if (!tapeT) return;                                 // a hold already happened, or it was cancelled
    tapeCancel();
    if (!selected) { statusEl.textContent = 'Tap a box first, then tap the tape to cover it. Hold the tape to cover or uncover everything.'; return; }
    selected.cover = !selected.cover;
    render(); touch();
  });
  ['pointerleave', 'pointercancel'].forEach(ev => masterTape.addEventListener(ev, tapeCancel));
  masterTape.addEventListener('contextmenu', e => e.preventDefault());

  /* ---------- CCW / CW: swap the chosen branch with its neighbouring sibling ---------- */
  // The sequence has hard ends: the first child cannot go counter-clockwise, the last cannot go clockwise
  // (also around a centre box). Only these buttons, or moving a box between two siblings, change the order.
  function syncRot() {
    nbRev.disabled = !(selected && nodeSet.has(selected) && selected.children.some(c => nodeSet.has(c)));
    const n = selected, p = n && n.parent;
    const k = p ? p.children.length : 0, i = p ? p.children.indexOf(n) : -1;
    const ok = !!p && k > 1 && !dnode && !mover && i >= 0;
    ccwBtn.disabled = !(ok && i > 0);
    cwBtn.disabled = !(ok && i < k - 1);
  }
  function reorder(dir) {
    const n = selected; if (!n || !n.parent || dnode || mover) return;
    const p = n.parent, sib = p.children, i = sib.indexOf(n), j = i + dir;
    if (i < 0 || j < 0 || j >= sib.length) return;       // strict ends
    const o = sib[j];
    if (!nodeSet.has(o)) return;
    const L = Math.max(1, lenK);
    const va = [(n.x - p.x) / L, (n.y - p.y) / L], vo = [(o.x - p.x) / L, (o.y - p.y) / L];
    lockAllLines(null);                                  // nothing else moves
    sib[i] = o; sib[j] = n;
    // the two boxes trade places: each takes the other's exact vector and keeps its own sub-branches (they turn with it)
    const put = (c, v) => {
      const lm = lvMul(c), m = lm != null && lm > 0.05 ? lm : 1;
      c.ov = lm != null && lm <= 0.05 ? 1 : undefined;
      c.au = undefined; c.bf = undefined; c.ba = undefined; c.lkl = undefined;
      c.lkv = [v[0] / m, v[1] / m, Math.atan2(v[1], v[0]), p.ang || 0];
    };
    put(n, vo); put(o, va);
    layoutAll(); render(); touch();
  }

  ccwBtn.onclick = () => reorder(-1);
  cwBtn.onclick = () => reorder(1);

  unhide.onclick = () => {
    const f = uhTarget(); if (!f) return;
    f.hideKids = !f.hideKids;
    layoutAll(); render(); touch();
  };

  function syncLineUI(n) {
    const has = !!(n && n.parent);
    lineRow.hidden = !has;
    if (!has) return;
    rname.textContent = short(n.text);
    const v = Math.max(0, Math.min(400, Math.round(trueMul(n) * 100)));   // the real length, not just the setting
    lineLen.value = v; lineVal.textContent = v + '%';
    lineReset.disabled = n.ov == null;
  }

  /* ---------- hold to move (stays connected) · shake to snap out · merge text / connect ---------- */
  // a floating box keeps a fixed offset from the box it was pulled out of (its source)
  function tether(n) {
    const s = n.src;
    if (s && s !== n && nodeSet.has(s) && !inTree(n, s)) { n.sox = n.fx - s.x; n.soy = n.fy - s.y; }
    else n.src = null;
  }
  // camera tracking: slide the view so the touch point stays on the box
  function lockCamera(fp) {
    if (!dnode) return;
    const sx = (dnode.x + grab.x) * view.k + view.x, sy = (dnode.y + grab.y) * view.k + view.y;
    view.x += fp.x - sx; view.y += fp.y - sy;
  }
  // puts the box under the finger, wherever the view is right now
  function followPointer() {
    if (!lastPtr) return;
    const w = toWorld(lastPtr);
    if (mover) {
      // the box follows the finger. Its whole cluster (children, grandchildren…) orbits the parent by the same angle
      // and slides along the new line, so the first and last children stay on the same flanks of the line.
      const tx = w.x - grab.x, ty = w.y - grab.y, pp = mover.pp;
      const vx = tx - pp.x, vy = ty - pp.y, dist = Math.hypot(vx, vy);
      if (dist > 1) {
        mover.ux = vx / dist; mover.uy = vy / dist;
        mover.th = normA(Math.atan2(vy, vx) - mover.a0);
        mover.s = dist - mover.d0;
      }
      const c = Math.cos(mover.th), sn = Math.sin(mover.th), ux = mover.ux, uy = mover.uy, s = mover.s;
      mover.sub.forEach((m, i) => {
        const qx = mover.orig[i][0] - pp.x, qy = mover.orig[i][1] - pp.y;
        m.x = pp.x + qx * c - qy * sn + ux * s;
        m.y = pp.y + qx * sn + qy * c + uy * s;
      });
      if (Math.hypot(tx - mover.ox, ty - mover.oy) > 3) mover.moved = true;
    } else if (dnode) {
      dnode.fx = w.x - grab.x; dnode.fy = w.y - grab.y;
      dnode.x = dnode.fx; dnode.y = dnode.fy;
      tether(dnode);                                    // keep the offset from the source up to date
      target = findTarget();
    }
  }
  // near the canvas border the view scrolls so the box can keep going while the finger stays put
  function panSpeed(p, r) {
    const M = PAN.M, V = PAN.V;
    const f = (v, size) => (v < M ? Math.min(1.3, (M - v) / M) : (v > size - M ? -Math.min(1.3, (v - (size - M)) / M) : 0));
    return { x: f(p.x, r.width) * V, y: f(p.y, r.height) * V };
  }
  function panTick() {
    panRaf = 0;
    if (!(mover || dnode) || !lastPtr) return;
    const r = canvas.getBoundingClientRect(), s = panSpeed(lastPtr, r);
    if (!s.x && !s.y) return;
    view.x += s.x; view.y += s.y;
    followPointer();
    applyView();
    quickUpdate(movingList());
    panRaf = requestAnimationFrame(panTick);
  }
  function edgePan() {
    if (!(mover || dnode) || !lastPtr || panRaf) return;
    const s = panSpeed(lastPtr, canvas.getBoundingClientRect());
    if (s.x || s.y) panRaf = requestAnimationFrame(panTick);
  }

  // takes a box out of its parent (it becomes a floating box that remembers its source)
  function detach(n) {
    const x = n.x, y = n.y, src = n.parent;
    freezeFor(src, subtreeSet(n));                      // the siblings keep their line length and flow back into the gap
    src.children = src.children.filter(c => c !== n);
    n.parent = null; n.isMember = false; n.fx = x; n.fy = y; n.src = src;
    n.ba = undefined; n.bf = undefined; n.ov = undefined; n.au = undefined; n.lkv = undefined; n.lkl = undefined;
  }
  // a floating box is lifted: it follows the finger, its sub-branches hide under the show button
  function liftBox(n, fp, keepGrab) {
    if (!keepGrab) { const w0 = toWorld(fp); grab = { x: w0.x - n.x, y: w0.y - n.y }; }
    floats = floats.filter(f => f !== n);
    tether(n);                                          // fixed distance from the source box from now on
    floats.push(n);                                     // last = drawn on top
    n.hideKids = n.children.length > 0;
    dnode = n; target = null; mover = null; lastPtr = { x: fp.x, y: fp.y };
    editor.hidden = true; select(null, false);
    layoutAll();
    lockCamera(fp);                                     // the box stays under the finger
    render();
  }
  // hold on a box that is already floating
  function startDrag(n, p) {
    if (ptrs.size !== 1 || !drag || drag.moved) return;
    haptic();
    liftBox(n, [...ptrs.values()][0] || p, false);
  }

  // hold on a connected box: it can now be moved anywhere without leaving its parent
  function startFree(n, p) {
    if (ptrs.size !== 1 || !drag || drag.moved || !n.parent) return;
    haptic();
    const fp = [...ptrs.values()][0] || p;
    const w0 = toWorld(fp), sub = branchOf(n, nodeSet), par = n.parent;
    const d0 = Math.hypot(n.x - par.x, n.y - par.y) || 1, a0 = Math.atan2(n.y - par.y, n.x - par.x);
    grab = { x: w0.x - n.x, y: w0.y - n.y };
    mover = {
      n, ox: n.x, oy: n.y, sub, orig: sub.map(m => [m.x, m.y]), moved: false,
      pts: [{ x: fp.x, y: fp.y, t: performance.now() }],
      pp: { x: par.x, y: par.y }, d0, a0, th: 0, s: 0, ux: Math.cos(a0), uy: Math.sin(a0)
    };
    lastPtr = { x: fp.x, y: fp.y };
    editor.hidden = true; select(null, false);
    statusEl.textContent = 'Move it anywhere, it stays connected and its branches orbit with it. Shake it to snap it out.';
    render();
  }
  // counts direction reversals of at least th pixels in a series of coordinates
  function swings(vals, th) {
    let cnt = 0, dir = 0, ext = vals[0];
    for (let i = 1; i < vals.length; i++) {
      const v = vals[i];
      if (dir === 0) { if (Math.abs(v - ext) > th) { dir = v > ext ? 1 : -1; ext = v; } }
      else if (dir === 1) { if (v > ext) ext = v; else if (ext - v > th) { cnt++; dir = -1; ext = v; } }
      else { if (v < ext) ext = v; else if (v - ext > th) { cnt++; dir = 1; ext = v; } }
    }
    return cnt;
  }
  const shaken = pts => Math.max(swings(pts.map(q => q.x), SHAKE.TH), swings(pts.map(q => q.y), SHAKE.TH)) >= SHAKE.REV;
  function moveFree(p) {
    if (!mover) return;
    lastPtr = { x: p.x, y: p.y };
    followPointer();
    const now = performance.now(), pts = mover.pts;
    pts.push({ x: p.x, y: p.y, t: now });
    while (pts.length > 2 && now - pts[0].t > SHAKE.MS) pts.shift();
    if (pts.length > 6 && shaken(pts)) { shakeOut(); return; }
    edgePan();
    scheduleQuick();
  }
  // the box was shaken: it leaves its parent and is carried on as a snapped-out box
  function shakeOut() {
    const n = mover && mover.n;
    if (!n || !n.parent) return;
    const fp = lastPtr;
    mover = null;
    detach(n);
    haptic();
    liftBox(n, fp, true);
    statusEl.textContent = 'Snapped out. Drop it on a box to merge the text, near a box to connect, or anywhere to leave it floating.';
  }
  // the finger lifted while the box was only being moved. Its new place becomes a manual line length + direction,
  // its branches keep the turn they were given (they orbited with it), and if it now sits between other siblings
  // it takes that place in the sequence (that is a manual reorder).
  function dropFree() {
    const m = mover; mover = null; lastPtr = null;
    if (!m) return;
    const n = m.n, p = n.parent;
    if (!m.moved || !p) { restretch(); render(); select(n, false); return; }
    const L = Math.max(1, lenK), nx = n.x, ny = n.y, th = m.th || 0;
    lockAllLines(null);                                  // every line keeps its vector: nothing else shifts when the order changes
    const rest = p.children.filter(c => c !== n), kn = keyOf(p, n);
    let at = rest.findIndex(c => nodeSet.has(c) && keyOf(p, c) > kn);
    if (at < 0) at = rest.length;
    rest.splice(at, 0, n); p.children = rest;
    const vx = (nx - p.x) / L, vy = (ny - p.y) / L, len = Math.hypot(vx, vy), base = Math.hypot(n.dx, n.dy);
    if (base > 1e-6 && len > 1e-6) {
      n.ov = len / base;                                 // a line length you set by hand
      n.ba = normA(Math.atan2(vy, vx) - Math.atan2(n.dy, n.dx));
      n.ta = 0; n.au = undefined; n.bf = undefined; n.lkl = undefined;
    }
    if (Math.abs(th) > 1e-6) (function w(x) { x.children.forEach(c => { c.ba = normA((c.ba || 0) + th); w(c); }); })(n);
    restretch(); render();
    select(n, false);
    touch();
  }

  function findTarget() {
    const d = dnode;
    for (const m of nodes) if (m !== d && inRect(m, d.x, d.y)) return { kind: 'merge', n: m };
    let best = null, bg = SNAP + 1e-6;
    for (const m of nodes) {
      if (m === d) continue;
      const g = Math.hypot(Math.max(0, Math.abs(m.x - d.x) - (m.w + d.w) / 2), Math.max(0, Math.abs(m.y - d.y) - (m.h + d.h) / 2));
      if (g <= bg) { bg = g; best = m; }
    }
    return best ? { kind: 'connect', n: best } : null;
  }
  function moveDrag(p) {
    lastPtr = { x: p.x, y: p.y };
    followPointer();
    edgePan();
    scheduleQuick();
  }
  // where to put a newly connected box: in the widest free angle around its parent, as long as its neighbours' lines.
  // It takes the matching place in the sibling sequence (between the two boxes it ends up between).
    function placeNew(d, relAng) {
    try {
      const p = d.parent; if (!p) return;
      const vis = nodeSet;
      if (!vis.has(d)) return;
      const L = Math.max(1, lenK);
      const sibs = p.children.filter(c => c !== d && vis.has(c));
      const av = sibs.map(c => Math.atan2(c.y - p.y, c.x - p.x));
      if (p.parent) av.push(Math.atan2(p.parent.y - p.y, p.parent.x - p.x));
            const exact = typeof relAng === 'number' && Number.isFinite(relAng);
      if (!av.length && !exact) { branchOf(d, vis).forEach(e => { e.lkv = mkLock(e); e.lkl = undefined; }); return; }
      let best = 0, bd = -1;
      if (exact) best = relAng;                         // released here: keep exactly this direction
      else for (let k = 0; k < 72; k++) {
        const a = -Math.PI + k * Math.PI / 36; let md = Infinity;
        av.forEach(b => { md = Math.min(md, Math.abs(normA(a - b))); });
        if (md > bd) { bd = md; best = a; }
      }

      let sum = 0; sibs.forEach(c => { sum += Math.hypot(c.x - p.x, c.y - p.y) / L; });
      const len = sibs.length ? sum / sibs.length : Math.hypot(d.dx, d.dy);
      const lm = lvMul(d), m = lm != null ? lm : 1, base = m > 0.05 ? len / m : len;
      const fa = Math.hypot(d.dx, d.dy) > 1e-6 ? Math.atan2(d.dy, d.dx) : (d.ang || 0), delta = best - fa;
      const cs = Math.cos(delta), sn = Math.sin(delta);
      const all = branchOf(d, vis);
      all.forEach(e => {
        if (e === d) return;
        const x = e.dx, y = e.dy;
        e.dx = x * cs - y * sn; e.dy = x * sn + y * cs; e.ang = (e.ang || 0) + delta;   // its sub-branches turn with it
      });
      d.dx = Math.cos(best) * base; d.dy = Math.sin(best) * base; d.ang = best;
      all.forEach(e => { e.lkv = mkLock(e); e.lkl = undefined; });
      // keep the sequence equal to the angular order
      const kd = seqKey(p, best), rest = p.children.filter(c => c !== d);
      let at = rest.findIndex(c => vis.has(c) && keyOf(p, c) > kd);
      if (at < 0) at = rest.length;
      rest.splice(at, 0, d); p.children = rest;
      restretch();
    } catch (err) { console.error(err); }
  }
  // dropped ON another box: the two texts become one box ("0.5" + "3" → "0.5-3"), the dropped box disappears
  function mergeText(d, m) {
    const k = view.k, sx = m.x * k + view.x, sy = m.y * k + view.y;     // the merged box stays where it is on screen
    const sub = subtreeSet(d);
    lockAllLines(sub);                                 // every existing line is locked first, so nothing else moves
    const kids = d.children.slice();
    floats = floats.filter(f => f !== d);
    floats.forEach(f => { if (f.src === d) f.src = null; });
    m.text = m.text + '-' + d.text;
    d.children = [];
    kids.forEach(c => {                                // the dropped box's own sub-branches move over to the merged box
      c.parent = m; c.src = null; c.isMember = !!m.group;
      c.ov = undefined; c.au = undefined; c.bf = undefined; c.ba = undefined; c.lkv = undefined; c.lkl = undefined;
      m.children.push(c);
      setDepth(c, m.depth + 1);
    });
    layoutAll();
    kids.forEach(c => placeNew(c));
    haptic();
    holdCam(m, sx, sy);
    render();
    select(m, true);
    touch();
    statusEl.textContent = 'Merged the text into one box: “' + short(m.text) + '”.';
  }
  function dropDrag() {
    const d = dnode, t = findTarget();
    const kz = view.k, sx0 = d.x * kz + view.x, sy0 = d.y * kz + view.y;   // where the dragged box is on screen right now
    dnode = null; target = null; lastPtr = null;
    if (t && t.kind === 'merge') { mergeText(d, t.n); return; }
    if (t) {
      const par = t.n;
      const relAng = Math.atan2(d.y - par.y, d.x - par.x);
      lockAllLines(subtreeSet(d));                      // connecting must not move or turn any line that already exists
      floats = floats.filter(f => f !== d);
      d.parent = par;
      par.children.push(d);
      d.isMember = !!par.group; d.ov = undefined; d.au = undefined; d.bf = undefined; d.ba = undefined; d.lkv = undefined; d.lkl = undefined;
      d.hideKids = false; d.src = null;
      setDepth(d, par.depth + 1);
      haptic();
      layoutAll();
      placeNew(d, relAng);
;                                      // only the new box is placed; everything else stays exactly where it was
      holdCam(d, sx0, sy0);                             // camera stays on the connected box until the canvas is touched
    } else { tether(d); layoutAll(); }                  // left floating: stays a fixed distance from its source
    render();
    select(d, true);
    touch();
  }

  /* ---------- line-length sliders with a locked view anchor ---------- */
  let anchor = null;
  function grabAnchor() {
    if (!nodes.length) return;
    const r = canvas.getBoundingClientRect(), cx = r.width / 2, cy = r.height / 2;
    let best = null, bd = Infinity, bsx = 0, bsy = 0;
    for (const n of nodes) {
      const sx = n.x * view.k + view.x, sy = n.y * view.k + view.y;
      const d = (sx - cx) * (sx - cx) + (sy - cy) * (sy - cy);
      if (d < bd) { bd = d; best = n; bsx = sx; bsy = sy; }
    }
    anchor = best ? { n: best, sx: bsx, sy: bsy } : null;
  }
  const dropAnchor = () => { anchor = null; };
  function bindLock(el) {
    el.addEventListener('pointerdown', grabAnchor);
    el.addEventListener('keydown', () => { if (!anchor) grabAnchor(); });
    ['change', 'pointerup', 'pointercancel', 'blur'].forEach(ev => el.addEventListener(ev, dropAnchor));
  }
  // clr = the boxes whose lines the slider controls: any automatic length tidy-up on them is dropped, so the slider
  // value really is "percent of the default layout distance". Their rotation (direction) is left alone.
  function relayout(keepEditor, clr) {
    if (!nodes.length) return;
    if (clr) clr.forEach(n => { n.au = undefined; n.bf = undefined; });
    if (!anchor) grabAnchor();
    restretch();
    if (anchor) { view.x = anchor.sx - anchor.n.x * view.k; view.y = anchor.sy - anchor.n.y * view.k; }
    if (!keepEditor) editor.hidden = true;
    scheduleRender();
    touch();
  }

  bindLock(lenEl);
  lenEl.addEventListener('input', () => {
    lenK = (+lenEl.value) / 100;
    lenVal.textContent = Math.round(lenK * 100) + '%';
    relayout();
  });
  // all length knobs have − / + buttons that move exactly 1 unit
  const nudgeLen = dd => {
    lenEl.value = Math.max(+lenEl.min, Math.min(+lenEl.max, (+lenEl.value) + dd));
    grabAnchor(); lenEl.dispatchEvent(new Event('input')); dropAnchor();
  };
  lenMinus.onclick = () => nudgeLen(-1);
  lenPlus.onclick = () => nudgeLen(1);

  bindLock(lineLen);
  lineLen.addEventListener('input', () => {
    if (!editing || !editing.parent) return;
    editing.ov = (+lineLen.value) / 100;
    lineReset.disabled = false;
    relayout(true, [editing]);
    lineVal.textContent = Math.round(trueMul(editing) * 100) + '%';   // shows what the line really is now
  });
  lineLen.addEventListener('change', () => { if (editing && editing.parent) syncLineUI(editing); });
  lineReset.addEventListener('click', () => {
    if (!editing) return;
    editing.ov = undefined;
    grabAnchor(); relayout(true, [editing]); dropAnchor();
    syncLineUI(editing);
  });
  const nudge = d => {
    if (!editing || !editing.parent) return;
    lineLen.value = Math.max(0, Math.min(400, (+lineLen.value) + d));
    grabAnchor(); lineLen.dispatchEvent(new Event('input')); dropAnchor();
    syncLineUI(editing);
  };
  lineMinus.onclick = () => nudge(-1);
  linePlus.onclick = () => nudge(1);

  /* ---------- level sliders: whole map, or re-based on the chosen box ---------- */
  // Same mechanics both ways: a slider sets a multiplier for every line that ends at one level,
  // 100% = the default layout distance. Re-based mode just counts levels from the chosen box.
  function levelBase() {
    const s = selected;
    if (s && !dnode && !mover && nodeSet.has(s) && !s.hideKids && s.children.some(c => nodeSet.has(c))) return s;
    return null;                                        // nothing usable chosen: whole-map levels
  }
  function buildLevelControls() {
    levelsBody.innerHTML = '';
    if (!main) { levelsBody.innerHTML = '<small>Generate a map first.</small>'; return; }
    const sel = levelBase(), base = sel || main, isMain = base === main;
    const vis = nodeSet;
    let maxD = 0;
    (function w(m) { m.children.forEach(c => { if (vis.has(c)) { maxD = Math.max(maxD, c.depth - base.depth); w(c); } }); })(base);
    if (maxD < 1) { levelsBody.innerHTML = '<small>No branches yet.</small>'; return; }

    const scope = isMain ? nodes.slice() : branchOf(base, vis);                       // boxes these sliders can reach
    const atLevel = d => scope.filter(n => n.parent && (isMain ? n.depth : n.depth - base.depth) === d);
    const put = (d, v) => { if (isMain) levels[d] = v; else { if (!base.lv) base.lv = {}; base.lv[d] = v; } };

    const hint = document.createElement('small');
    hint.textContent = isMain
      ? 'Each slider changes only the lines that end at that level. 100% = the default layout distance. Boxes never get closer than 0.25 grid squares. Tap a box to re-base these sliders on it, or use the vertical knob on the right edge for just its own line.'
      : 'Re-based on “' + short(base.text) + '”: its direct sub-branches are now Level 1. 100% = the default layout distance, and boxes never get closer than 0.25 grid squares. Moving a slider takes over every line at that level inside this branch. Tap empty space to go back to the whole map.';
    levelsBody.appendChild(hint);

    const sliders = [];
    for (let d = 1; d <= maxD; d++) {
      const wrap = document.createElement('div'); wrap.className = 'lvl';
      const lab = document.createElement('label');
      const name = document.createElement('span');
      if (d === 1) name.textContent = isMain ? 'Level 1 · center → main branches' : 'Level 1 · chosen box → its sub-branches';
      else name.textContent = 'Level ' + d + ' · level ' + (d - 1) + ' → ' + d;
      const lvlNodes = atLevel(d), free = lvlNodes.filter(n => n.ov == null);
      const ref = free.length ? free[0] : lvlNodes[0];
      const cur = ref ? Math.max(0, Math.min(300, Math.round(effMul(ref) * 100))) : 100;   // shows the real current value
      const val = document.createElement('b'); val.textContent = cur + '%';
      lab.append(name, val);
      const sl = document.createElement('input');
      sl.type = 'range'; sl.min = 0; sl.max = 300; sl.step = 1; sl.value = cur;
      sl.addEventListener('input', () => {
        put(d, (+sl.value) / 100);
        val.textContent = sl.value + '%';
        const at = atLevel(d);
        if (!isMain) at.forEach(n => { n.ov = undefined; });      // the temporary slider takes over these lines
        relayout(false, at);
        if (selected && selected.parent) syncLineUI(selected);
      });
      bindLock(sl);
      // − / + buttons: exactly 1 unit per tap
      const row = document.createElement('div'); row.className = 'srow';
      const mb = document.createElement('button'); mb.textContent = '−'; mb.title = '1% shorter';
      const pb = document.createElement('button'); pb.textContent = '+'; pb.title = '1% longer';
      const step = dd => {
        sl.value = Math.max(0, Math.min(300, (+sl.value) + dd));
        grabAnchor(); sl.dispatchEvent(new Event('input')); dropAnchor();
      };
      mb.onclick = () => step(-1);
      pb.onclick = () => step(1);
      row.append(mb, sl, pb);
      wrap.append(lab, row);
      levelsBody.appendChild(wrap);
      sliders.push({ d, sl, val });
    }
    const rs = document.createElement('button');
    rs.className = 'reset'; rs.textContent = 'Reset levels';
    rs.onclick = () => {
      if (isMain) levels = {}; else base.lv = undefined;
      sliders.forEach(s => { s.sl.value = 100; s.val.textContent = '100%'; });
      grabAnchor(); relayout(false, scope); dropAnchor();
      if (selected && selected.parent) syncLineUI(selected);
    };
    levelsBody.appendChild(rs);

    const cl = document.createElement('button');
    cl.className = 'reset'; cl.textContent = 'Clear single-line overrides';
    cl.onclick = () => {
      scope.forEach(n => { n.ov = undefined; });
      grabAnchor(); relayout(false, scope); dropAnchor();
      if (selected) syncLineUI(selected);
    };
    levelsBody.appendChild(cl);
  }

  /* ---------- dark mode ---------- */
  function setTheme(d, save) {
    dark = d;
    document.body.classList.toggle('dark', dark);
    themeBtn.textContent = dark ? '☀' : '☾';
    if (save) { try { localStorage.setItem('mm-theme', dark ? 'dark' : 'light'); } catch (e) { /* ignore */ } }
    if (nodes.length) render();
  }
  themeBtn.onclick = () => setTheme(!dark, true);
  (function initTheme() {
    let t = null;
    try { t = localStorage.getItem('mm-theme'); } catch (e) { /* ignore */ }
    const pref = t ? t === 'dark' : !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    setTheme(pref, false);
  })();

  /* ---------- mind map → text (the reverse of the generator) ---------- */
  // Writes the map in the same syntax the generator reads: a title line, "-" bullets (nested with 2 spaces)
  // and "##" headings. Order is kept exactly: headings are only used where every plain item comes first.
  // Collapsed branches are included. Snapped-out (floating) boxes are written as extra top-level items at the end.
  function buildText() {
    if (!main) return '';
    const clean = s => s.replace(/\s+/g, ' ').trim();
    const rt = clean(main.text);
    const plain = rt.split(' ').length <= 12 && !/[.!?:;,]$/.test(rt) && !/^\s*(?:[-*•·–+#]|\d+[.)]|[a-z][.)])\s/i.test(rt);
    const out = [plain ? rt : '# ' + rt, ''];
    const bullets = (kids, ind) => kids.forEach(c => {
      out.push('  '.repeat(ind) + '- ' + clean(c.text));
      bullets(c.children, ind + 1);
    });
    const section = (kids, level) => {
      const first = kids.findIndex(c => c.children.length);
      const leafAfter = first >= 0 && kids.slice(first).some(c => !c.children.length);
      if (first < 0 || leafAfter || level + 1 > 6) { bullets(kids, 0); return; }
      kids.slice(0, first).forEach(c => out.push('- ' + clean(c.text)));
      kids.slice(first).forEach(c => {
        out.push('', '#'.repeat(level + 1) + ' ' + clean(c.text));
        section(c.children, level + 1);
      });
    };
    section(main.children.concat(floats), 1);
    while (out.length && !out[out.length - 1]) out.pop();
    return out.join('\n') + '\n';
  }
    /* ---------- export / import: outline text, map data text, and the .mindmap file ---------- */
  const expMeta = $('expMeta'), expExt = $('expExt');
  const FMT = 'mindmap', FMT_V = 1;
  const num = v => (typeof v === 'number' && Number.isFinite(v) ? v : undefined);
  const deg = a => Math.round(a * 18000 / Math.PI) / 100;     // radians → degrees, 2 decimals
  const r2 = v => Math.round(v * 100) / 100;

  // one box with its metadata, the exact layout settings that rebuild its place, and where it sits now
  function exNode(n) {
    const p = n.parent, shown = nodeSet.has(n);
    const o = { id: n.id, text: n.text, type: n.type, group: !!n.group, member: !!n.isMember, covered: !!n.cover, collapsed: !!n.hideKids };
    const a = {};
    if (n.ov != null) a.lengthSet = n.ov;
    if (n.au != null) a.tidy = n.au;
    if (n.bf != null) a.clearance = n.bf;
    if (n.ba != null) a.rotation = n.ba;
    if (n.lkv) a.lock = n.lkv;
    if (n.lkl != null) a.lockLength = n.lkl;
    if (n.lv) a.levelSliders = n.lv;
    if (Object.keys(a).length) o.layout = a;
    if (shown) {
      o.geometry = { x: r2(n.x), y: r2(n.y), width: r2(n.w), height: r2(n.h) };
      if (p && nodeSet.has(p)) {
        const vx = n.x - p.x, vy = n.y - p.y, ang = Math.atan2(vy, vx);
        const out = p.parent && nodeSet.has(p.parent) ? Math.atan2(p.y - p.parent.y, p.x - p.parent.x) : -Math.PI / 2;
        o.line = { length: r2(Math.hypot(vx, vy)), percent: r2(trueMul(n) * 100), angleDeg: deg(ang), vector: [r2(vx), r2(vy)], relativeDeg: deg(normA(ang - out)) };
      }
    }
    o.children = n.children.map(exNode);                // the order of this list is the sibling sequence
    return o;
  }
  function mapData(withInk) {
    if (!main) return null;
    const d = {
      format: FMT, version: FMT_V, app: 'Text → Mind Map', title: main.text, exported: new Date().toISOString(),
      settings: { lineLengthPercent: Math.round(lenK * 100), levelSliders: levels },
      root: exNode(main),
      floating: floats.map(f => ({
        depth: f.depth, x: r2(f.fx), y: r2(f.fy), sourceId: f.src ? f.src.id : null,
        sourceOffset: f.src ? [r2(f.sox), r2(f.soy)] : null, tree: exNode(f)
      }))
    };
    if (withInk) { const k = inkGet(); if (k) d.drawings = k; }     // drawings live only in the file
    const cc = cdGet(false); if (cc) d.cards = cc;
    return d;
  }
  // checks the data and turns it into the app's own saved form, so the normal restore does the rest
  function dataToSnap(o) {
    const used = new Set(), todo = [];
    const mk = x => {
      if (!x || typeof x !== 'object') throw new Error('a box in the data is damaged');
      const a = x.layout || {};
      const lock = Array.isArray(a.lock) && a.lock.length >= 3 && a.lock.every(v => typeof v === 'number' && Number.isFinite(v)) ? a.lock.slice(0, 4) : undefined;
      const n = {
        i: 0, t: String(x.text == null ? '' : x.text), y: TYPES[x.type] ? x.type : 'label',
        g: x.group ? 1 : 0, m: x.member ? 1 : 0, o: num(a.lengthSet), a: num(a.tidy), b: num(a.clearance), q: num(a.rotation),
        z: lock, u: num(a.lockLength), l: a.levelSliders && typeof a.levelSliders === 'object' ? Object.assign({}, a.levelSliders) : undefined,
        c: x.covered ? 1 : 0, h: x.collapsed ? 1 : 0, k: []
      };
      if (typeof x.id === 'number' && x.id > 0 && !used.has(x.id)) { n.i = x.id; used.add(x.id); } else todo.push(n);
      if (Array.isArray(x.children)) x.children.forEach(c => n.k.push(mk(c)));
      return n;
    };
    const m0 = mk(o.root);
    const fl = (Array.isArray(o.floating) ? o.floating : []).map(f => {
      const ox = f.sourceOffset ? num(f.sourceOffset[0]) : undefined, oy = f.sourceOffset ? num(f.sourceOffset[1]) : undefined;
      return {
        x: num(f.x) || 0, y: num(f.y) || 0, d: num(f.depth) || 1, n: mk(f.tree),
        s: (typeof f.sourceId === 'number' && ox != null && oy != null) ? f.sourceId : null, ox, oy
      };
    });
    let top = 0; used.forEach(v => { if (v > top) top = v; });
    todo.forEach(n => { n.i = ++top; });
    const st = o.settings || {}, pct = num(st.lineLengthPercent), lv = {};
    if (st.levelSliders && typeof st.levelSliders === 'object') Object.keys(st.levelSliders).forEach(k => { const v = num(st.levelSliders[k]); if (v != null && /^\d+$/.test(k)) lv[k] = v; });
    let ink; const dr = o.drawings;
    if (dr && Array.isArray(dr.s)) {
      const ids = new Set(); let sid = 0;
      dr.s.forEach(q => { if (q && typeof q.i === 'number' && q.i > sid) sid = q.i; });
      ink = { s: [] };
      dr.s.forEach(q => {
        if (!q || !Array.isArray(q.p) || q.p.length < 2 || q.p.length % 2 || !q.p.every(v => typeof v === 'number' && Number.isFinite(v))) return;
        const id = typeof q.i === 'number' && q.i > 0 && !ids.has(q.i) ? q.i : ++sid;
        ids.add(id);
        ink.s.push({ i: id, k: q.k === 'hl' || q.k === 'marker' ? q.k : 'pen', c: typeof q.c === 'string' ? q.c : '#000000', w: num(q.w) || 2, o: num(q.o) || 1, p: q.p });
      });
    }
    return { cd: (o.cards && typeof o.cards === 'object') ? o.cards : undefined, v: DATA_V, txt: '', main: m0, floats: fl, lenK: pct != null ? Math.max(1, Math.min(3, pct / 100)) : 1.2, levels: lv, ink };
  }
  function applyImport(o, withInk) {
    try {
      const snap = dataToSnap(o);
      if (!withInk) snap.ink = undefined;               // text never carries drawings
      restore(snap);
      input.value = buildText();
      mapName = ''; libName.value = main.text;
      dirty = true; resetHist(); fit(); saveDraft(); renderLib();
      const ns = snap.ink && snap.ink.s ? snap.ink.s.length : 0;
      statusEl.textContent = 'Imported “' + short(main.text) + '” · ' + nodes.length + ' boxes' + (ns ? ' · ' + ns + ' strokes' : '') + '.';
    } catch (err) { console.error(err); statusEl.textContent = 'Could not import: ' + err.message; }
  }
  // text or file contents → either map data (starts with {) or an outline for the generator
  function importAny(text, isFile, name) {
    const t = String(text || '').replace(/^\uFEFF/, '').trim();
    if (!t) { statusEl.textContent = 'Nothing to import.'; return; }
    if (t[0] === '{' || /\.(mindmap|json)$/i.test(name || '')) {
      let o;
      try { o = JSON.parse(t); } catch (e) { statusEl.textContent = 'That is not valid map data: ' + e.message; return; }
      if (!o || o.format !== FMT || !o.root) { statusEl.textContent = 'That data is not a mind map.'; return; }
      if (typeof o.version === 'number' && o.version > FMT_V) { statusEl.textContent = 'That file comes from a newer version of the app.'; return; }
      guard(() => applyImport(o, isFile));
      return;
    }
    guard(() => { input.value = t; generate(); });
  }
  function readImportFile(f) {
    if (!f) return;
    const rd = new FileReader();
    rd.onload = () => importAny(String(rd.result), true, f.name);
    rd.onerror = () => { statusEl.textContent = 'Could not read that file.'; };
    rd.readAsText(f);
  }
  function saveFile() {
    if (!main) return;
    const ext = expExt.value === '.json' ? '.json' : '.mindmap';
    const name = (main.text.replace(/[^\w\-]+/g, '_').replace(/^_+|_+$/g, '') || 'mindmap') + ext;
    const data = JSON.stringify(mapData(true), null, 2);
    try {
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.saveFile;
      if (h) { h.postMessage({ name, data }); statusEl.textContent = 'Choose where to save “' + name + '”.'; return; }
    } catch (e) { /* fall through to a normal download */ }
    try {
      const u = URL.createObjectURL(new Blob([data], { type: 'application/json' })), a = document.createElement('a');
      a.href = u; a.download = name; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(u), 4000);
      statusEl.textContent = 'Saved “' + name + '”.';
    } catch (err) { statusEl.textContent = 'Could not save the file: ' + err.message; }
  }
  function refreshExp() {
    if (!main) return;
    expText.value = expMeta.checked ? JSON.stringify(mapData(false), null, 2) + '\n' : buildText();
    $('expUse').disabled = expMeta.checked;
    $('expHint').textContent = expMeta.checked
      ? 'Map data as text: boxes, structure, and every line length, direction and orientation. Drawings are not part of the text.'
      : 'Outline text in the generator syntax. Tick the box above to include the layout.';
  }
  expMeta.onchange = refreshExp;
  function openExport() {
    if (!main) { statusEl.textContent = 'Generate a map first.'; return; }
    if (editNode) nodeEdit.blur();
    refreshExp();
    expDlg.hidden = false;
  }
  $('libExp').onclick = openExport;
  $('expFile').onclick = saveFile;
  $('expImp').onclick = () => { const t = expText.value; expDlg.hidden = true; importAny(t, false, ''); };
  $('expImpFile').onchange = e => { const f = e.target.files[0]; e.target.value = ''; expDlg.hidden = true; readImportFile(f); };
  $('impFile').onchange = e => { const f = e.target.files[0]; e.target.value = ''; readImportFile(f); };

  $('expClose').onclick = () => { expDlg.hidden = true; };
  $('expUse').onclick = () => {
    input.value = expText.value;
    expDlg.hidden = true;
    statusEl.textContent = 'The exported text is now in the text box. Press Generate to build a map from it.';
  };
  $('expCopy').onclick = () => {
    const b = $('expCopy'), old = 'Copy';
    const done = ok => { b.textContent = ok ? 'Copied ✓' : 'Hold the text, Select All, Copy'; setTimeout(() => { b.textContent = old; }, 1800); };
    const fallback = () => {
      try { expText.focus(); expText.select(); expText.setSelectionRange(0, expText.value.length); done(document.execCommand('copy')); }
      catch (e) { done(false); }
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(expText.value).then(() => done(true), fallback);
    else fallback();
  };

  /* ---------- library: save / open / draft ---------- */
  function ser(n) {
    return {
      i: n.id, t: n.text, y: n.type, g: n.group ? 1 : 0, m: n.isMember ? 1 : 0,
      o: n.ov != null ? n.ov : undefined, a: n.au != null ? n.au : undefined, b: n.bf != null ? n.bf : undefined,
      q: n.ba != null ? n.ba : undefined, z: n.lkv || undefined, u: n.lkl != null ? n.lkl : undefined,
      l: n.lv || undefined, c: n.cover ? 1 : 0, h: n.hideKids ? 1 : 0, k: n.children.map(ser)
    };
  }
  function deser(o, parent, depth) {
    const n = { id: o.i, text: o.t, type: o.y, parent, children: [], group: !!o.g, depth, isMember: !!o.m, ov: o.o, au: o.a, bf: o.b, ba: o.q, lkv: o.z, lkl: o.u, lv: o.l, cover: !!o.c, hideKids: !!o.h };
    if (parent) parent.children.push(n);
    o.k.forEach(k => deser(k, n, depth + 1));
    return n;
  }
  function snapshot(h) {
    if (!main) return null;
    return {
      v: DATA_V, txt: input.value, main: ser(main),
      floats: floats.map(f => ({ x: f.fx, y: f.fy, d: f.depth, n: ser(f), s: f.src ? f.src.id : null, ox: f.sox, oy: f.soy })),
            ink: inkGet(), cd: cdGet(h), lenK, levels, view: { x: view.x, y: view.y, k: view.k }

    };
  }
  function restore(s) {
    main = deser(s.main, null, 0);
    floats = (s.floats || []).map(f => {
      const r = deser(f.n, null, f.d);
      r.fx = f.x; r.fy = f.y; r._s = f.s; r.sox = f.ox; r.soy = f.oy;
      return r;
    });
    lenK = s.lenK || 1.2; levels = s.levels || {};
    lenEl.value = Math.round(lenK * 100); lenVal.textContent = Math.round(lenK * 100) + '%';
    input.value = s.txt || '';
    Object.assign(view, s.view || {});
    fixIds();
        inkSet(s.ink); cdSet(s.cd);
    const idm = new Map(); walkAll(n => idm.set(n.id, n));

    floats.forEach(r => { r.src = r._s != null ? (idm.get(r._s) || null) : null; delete r._s; });
    if (s.pe && s.pe.i != null) { const pn = idm.get(s.pe.i), pt = String(s.pe.t || '').replace(/\s+/g, ' ').trim(); if (pn && pt) pn.text = pt; }   // text that was still being typed

    // saves from older versions hold automatic spacing that was stored as if you had set it yourself;
    // it outranks every slider, so drop it (the default layout and your level sliders take over)
    if (!s.v || s.v < DATA_V) walkAll(n => { n.ov = undefined; n.au = undefined; n.bf = undefined; n.ba = undefined; });
    freeCam(); disarmDel();
    editor.hidden = true; editing = null; selected = null; editNode = null; nodeEdit.hidden = true; dnode = null; mover = null;
    layoutAll(); buildLevelControls(); render();
    statusEl.textContent = nodes.length + ' boxes · ' + HELP;
  }
    function saveDraftOld() {

    const s = snapshot();
    if (!s) { lsDel(DRAFT_KEY); return; }
    lsSet(DRAFT_KEY, { name: mapName, dirty, snap: s });
  }
    // the heavy saving (undo copy + draft) never runs while a stroke is being drawn or right after the pencil lifts
  function settle() {
    if (window.MMP && window.MMP.busy && window.MMP.busy()) { draftT = setTimeout(settle, 400); return; }
    pushHist(); saveDraft();
  }
    function touch() { dirty = true; clearTimeout(draftT); draftT = setTimeout(settle, 500); if (store) store.request(); }



  /* ---------- undo / redo ---------- */
  function updateUR() { undoBtn.disabled = hi <= 0; redoBtn.disabled = hi >= hist.length - 1; }
    const sameInk = (a, b) => {
    if (a === b) return true;
    if (!a || !b || a.s.length !== b.s.length) return false;
    for (let i = 0; i < a.s.length; i++) if (a.s[i] !== b.s[i]) return false;
    return true;
  };
  function pushHist() {
    const s = snapshot(true); if (!s) return;
    s.view = null;                                      // panning/zooming is not an undo step
    const ink = s.ink; s.ink = undefined;               // ink is kept by reference (each stroke is stored once), not re-converted every time
    const j = JSON.stringify(s), last = hist[hi];
    if (last && last.j === j && sameInk(last.ink, ink)) return;
    hist = hist.slice(0, hi + 1); hist.push({ j, ink });
    if (hist.length > 60) hist.shift();
    hi = hist.length - 1; updateUR();
  }

  function resetHist() { hist = []; hi = -1; pushHist(); updateUR(); }
  function stepHist(dir) {
    if (dnode || mover) return;
    if (editNode) nodeEdit.blur();
    clearTimeout(draftT); pushHist();                   // save any change that is still waiting
    const j = hi + dir;
    if (j < 0 || j >= hist.length) return;
    hi = j;
        const h = hist[hi], sn = JSON.parse(h.j); sn.ink = h.ink;
    restore(sn);

    dirty = true; clearTimeout(draftT); draftT = setTimeout(saveDraft, 500);
    updateUR();
    statusEl.textContent = (dir < 0 ? 'Undid' : 'Redid') + ' · ' + nodes.length + ' boxes';
  }

  function saveToLib(name) {
    const s = snapshot(); if (!s) return;
    const lib = lsGet(LIB_KEY) || {};
    lib[name] = { t: Date.now(), snap: s };
    if (!lsSet(LIB_KEY, lib)) { statusEl.textContent = 'Could not save: storage is unavailable.'; return; }
    mapName = name; dirty = false; saveDraft(); renderLib();
    statusEl.textContent = 'Saved “' + name + '” to the library.';
  }
  function openLib(name) {
    const lib = lsGet(LIB_KEY) || {};
    if (!lib[name]) return;
    restore(lib[name].snap);
    mapName = name; dirty = false; libName.value = name; saveDraft(); renderLib(); resetHist();
  }
  function newMap() {
    main = null; floats = []; setNodes([]); lists = []; mapName = ''; dirty = false;
        inkSet(null); cdSet(null);
    input.value = ''; libName.value = ''; svg.innerHTML = '';
 nodeEls = new Map(); edgeEls = new Map(); indEls = [];
    freeCam(); disarmDel();
    selected = null; editing = null; editor.hidden = true; unhide.hidden = true; nodebar.hidden = true; rpanel.hidden = true;
    levelsBody.innerHTML = '<small>Generate a map first.</small>';
        lsDel(DRAFT_KEY); renderLib(); resetHist(); syncRot(); saveDraft();

    statusEl.textContent = 'Type or paste text, then press Generate.';
  }
  function renderLib() {
    const lib = lsGet(LIB_KEY) || {};
    if (mapName && document.activeElement !== libName) libName.value = mapName;
    libList.innerHTML = '';
    const names = Object.keys(lib).sort((a, b) => lib[b].t - lib[a].t);
    if (!names.length) { libList.innerHTML = '<small>No saved maps yet.</small>'; return; }
    names.forEach(nm => {
      const row = document.createElement('div'); row.className = 'lib-item';
      const s = document.createElement('span'); s.textContent = nm + (nm === mapName && !dirty ? ' ✓' : '');
      const o = document.createElement('button'); o.className = 'mini'; o.textContent = 'Open';
      const d = document.createElement('button'); d.className = 'mini'; d.textContent = '🗑';
      o.onclick = () => guard(() => openLib(nm));
      let armed = false;
      d.onclick = () => {
        if (!armed) { armed = true; d.textContent = 'Sure?'; setTimeout(() => { armed = false; d.textContent = '🗑'; }, 2500); }
        else { const l = lsGet(LIB_KEY) || {}; delete l[nm]; lsSet(LIB_KEY, l); renderLib(); }
      };
      row.append(s, o, d);
      libList.appendChild(row);
    });
  }

  /* save prompt (shown before leaving a map, and when you come back to the app with unsaved changes) */
  function showSaveDialog(after) {
    dlgAfter = after || null;
    $('dlgName').value = mapName || (main ? main.text : '');
    dlg.hidden = false;
  }
  const guard = fn => { if (dirty && main) showSaveDialog(fn); else fn(); };
  $('dlgSave').onclick = () => {
    const nm = $('dlgName').value.trim(); if (!nm) return;
    saveToLib(nm); dlg.hidden = true;
    const a = dlgAfter; dlgAfter = null; if (a) a();
  };
  $('dlgNo').onclick = () => {
    dirty = false; saveDraft(); dlg.hidden = true;
    const a = dlgAfter; dlgAfter = null; if (a) a();
  };
  $('dlgCancel').onclick = () => { dlg.hidden = true; dlgAfter = null; };
  $('libSave').onclick = () => {
    if (!main) return;
    const nm = libName.value.trim() || main.text;
    saveToLib(nm);
  };
  $('libNew').onclick = () => guard(newMap);

  document.addEventListener('visibilitychange', () => {
        if (document.hidden) { flushAll(); needPrompt = dirty; }

    else if (needPrompt) { needPrompt = false; if (dirty && main) showSaveDialog(); }
  });
    window.addEventListener('pagehide', () => { flushAll(); });


  /* ---------- generate ---------- */
  function generate(quiet) {
    try {
      const root = parse(input.value);
      if (!root || !root.children.length) { statusEl.textContent = 'Nothing to map — add a few sentences or bullet points.'; return; }
      statusEl.textContent = 'Building…';
      setTimeout(() => {
        try {
                    inkSet(null); cdSet(null);
          main = root; floats = []; levels = {}; editNode = null; nodeEdit.hidden = true; mover = null; dnode = null;

          freeCam(); disarmDel();
          fixIds();
          editor.hidden = true; editing = null; selected = null;
          layoutAll();
          buildLevelControls();
          render(); fit();
          statusEl.textContent = nodes.length + ' boxes · ' + HELP;
          panel.classList.remove('open');
          if (quiet) { dirty = false; resetHist(); } else { mapName = ''; touch(); }
        } catch (err) { console.error(err); statusEl.textContent = 'Error: ' + err.message; }
      }, 20);
    } catch (err) { console.error(err); statusEl.textContent = 'Error: ' + err.message; }
  }

  /* ---------- PDF: everything that has data on it (boxes and drawings), shared through the iPad share sheet ---------- */
  function loadScript(src) {
    return new Promise((res, rej) => {
      const s = document.createElement('script'); s.src = src; s.onload = res;
      s.onerror = () => rej(new Error('could not load ' + src.split('/').pop() + ' (the PDF maker needs internet the first time)'));
      document.head.appendChild(s);
    });
  }
  async function pdfLibs() {
    if (!window.jspdf) await loadScript('https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js');
    if (!window.svg2pdf) await loadScript('https://cdn.jsdelivr.net/npm/svg2pdf.js@2.2.4/dist/svg2pdf.umd.min.js');
  }
  // the area that holds data: every box and every drawing stroke, plus a margin
  function contentBounds() {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    nodes.forEach(n => {
      x0 = Math.min(x0, n.x - n.w / 2); x1 = Math.max(x1, n.x + n.w / 2);
      y0 = Math.min(y0, n.y - n.h / 2); y1 = Math.max(y1, n.y + n.h / 2);
    });
    const ib = window.MMP && window.MMP.bounds ? window.MMP.bounds() : null;
    if (ib) { x0 = Math.min(x0, ib.x0); y0 = Math.min(y0, ib.y0); x1 = Math.max(x1, ib.x1); y1 = Math.max(y1, ib.y1); }
    if (!Number.isFinite(x0)) return null;
    const m = 40;
    return { x: x0 - m, y: y0 - m, w: x1 - x0 + 2 * m, h: y1 - y0 + 2 * m };
  }
  function toB64(buf) {
    const u = new Uint8Array(buf); let s = '';
    for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
    return btoa(s);
  }
  async function deliverPdf(pdf, name) {
    const buf = pdf.output('arraybuffer');
    try {                                                // 1) the app's own share sheet (Save to Files, AirDrop, …)
      const h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.saveFile;
      if (h) { h.postMessage({ name, b64: toB64(buf) }); statusEl.textContent = 'Choose where to save “' + name + '”.'; return; }
    } catch (e) { /* try the next way */ }
    try {                                                // 2) the browser share sheet
      const f = new File([buf], name, { type: 'application/pdf' });
      if (navigator.canShare && navigator.canShare({ files: [f] })) { await navigator.share({ files: [f] }); statusEl.textContent = 'Shared the PDF.'; return; }
    } catch (e) { if (e && e.name === 'AbortError') return; }
    pdf.save(name);                                      // 3) a normal download (works in Safari)
    statusEl.textContent = 'Saved “' + name + '”.';
  }
  let pdfBusy = false;
  async function downloadPDF() {
    const b = contentBounds();
    if (!b) { statusEl.textContent = 'Generate a map first.'; return; }
    if (pdfBusy) return;
    pdfBusy = true;
    statusEl.textContent = 'Making the PDF…';
    let holder = null;
    try {
      await pdfLibs();
      const { jsPDF } = window.jspdf;
      const W = Math.max(40, Math.ceil(b.w)), H = Math.max(40, Math.ceil(b.h));
      const s = Math.min(1, 19000 / Math.max(W, H));          // PDF page-size limit

      holder = document.createElement('div');
      holder.style.cssText = 'position:fixed;left:-99999px;top:0;opacity:0;pointer-events:none';
      document.body.appendChild(holder);
      const out = S('svg', { xmlns: NS, width: W, height: H, viewBox: `0 0 ${W} ${H}` }, holder);
      const defs = S('defs', {}, out);
      S('rect', { x: 0, y: 0, width: W, height: H, fill: PAGE_BG() }, out);
      const g = S('g', { transform: `translate(${-b.x} ${-b.y})` }, out);
      drawGraph(nodes, g, defs, 'p');
      if (window.MMP && window.MMP.draw) window.MMP.draw(g);   // the drawings go on top, as on screen

      const pdf = new jsPDF({ orientation: W >= H ? 'l' : 'p', unit: 'px', format: [W * s, H * s], hotfixes: ['px_scaling'] });
      const opts = { x: 0, y: 0, width: W * s, height: H * s };
      if (typeof pdf.svg === 'function') await pdf.svg(out, opts);
      else await (window.svg2pdf.svg2pdf || window.svg2pdf)(out, pdf, opts);
      const base = ((nodes[0] ? nodes[0].text : 'mindmap').replace(/[^\w\-]+/g, '_').replace(/^_+|_+$/g, '')) || 'mindmap';
      await deliverPdf(pdf, base + '_mindmap' + (dark ? '_dark' : '') + '.pdf');
    } catch (err) { console.error(err); statusEl.textContent = 'PDF error: ' + err.message; }
    finally { if (holder) holder.remove(); pdfBusy = false; }
  }


  /* ---------- legend & wiring ---------- */
  const lg = $('legendBody');
  Object.keys(TYPES).forEach(k => {
    lg.insertAdjacentHTML('beforeend', `<div><span class="sw" style="background:${TYPES[k].color}"></span>${TYPES[k].label} <small>${TYPES[k].color}</small></div>`);
  });
  lg.insertAdjacentHTML('beforeend', `<div><span class="sw" style="background:linear-gradient(90deg,${TEAL},#9B5DE5)"></span>Group member with a type (teal → type colour)</div>`);

  $('gen').onclick = () => generate();
  $('sample').onclick = () => guard(() => { input.value = SAMPLE; generate(); });
  $('fit').onclick = () => { freeCam(); fit(); };
  undoBtn.onclick = () => stepHist(-1);
  redoBtn.onclick = () => stepHist(1);
  $('zin').onclick = () => { freeCam(); const r = canvas.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 1.3); };
  $('zout').onclick = () => { freeCam(); const r = canvas.getBoundingClientRect(); zoomAt(r.width / 2, r.height / 2, 1 / 1.3); };
  $('pdf').onclick = downloadPDF;
  function togglePanel() {
    if (window.matchMedia('(max-width:760px)').matches) panel.classList.toggle('open');
    else document.body.classList.toggle('collapsed');
  }
  $('menuBtn').onclick = togglePanel;
  $('panelHide').onclick = togglePanel;
  $('file').onchange = e => {
    const f = e.target.files[0]; if (!f) return;
    const rd = new FileReader();
    rd.onload = () => guard(() => { input.value = rd.result; generate(); });
    rd.readAsText(f);
  };
  window.addEventListener('resize', () => { if (nodes.length) applyView(); });

  lenVal.textContent = Math.round(lenK * 100) + '%';
  renderLib();
    /* ---------- bridge for the painting package (PaintJS.swift) ---------- */
  function inkGet() { return window.MMP ? window.MMP.get() : window.__inkPending; }
  function inkSet(s) { if (window.MMP) window.MMP.set(s); else window.__inkPending = s; }
  function cdGet(h) { return window.MMM ? window.MMM.get(h) : window.__cdPending; }
  function cdSet(s) { if (window.MMM) window.MMM.set(s); else window.__cdPending = s || null; }
  window.MMX = {
    view,
    nodes: () => nodes,
    roots: () => (main ? [main].concat(floats) : []),
    main: () => main,
    visible: n => nodeSet.has(n),
    world: () => world, nodeEls: () => nodeEls, edgeEls: () => edgeEls,
    applyView: () => applyView(),
    persist: () => { if (store) store.request(); },
        isMain: n => n === main,
    deliver: (pdf, name) => deliverPdf(pdf, name),

    touch: () => touch(),
    // move boxes (and everything below them) together; connected boxes stay connected
    moveBoxes(ids, dx, dy) {
      try {
        const set = new Set();
        ids.forEach(id => { const n = byId(id); if (n) branchOf(n, nodeSet).forEach(m => set.add(m)); });
        if (!set.size) return false;
        const L = Math.max(1, lenK);
        lockAllLines(null);
        [...set].filter(n => !n.parent || !set.has(n.parent)).forEach(n => {
          if (n === main) return;
          const p = n.parent;
          if (!p) { n.fx += dx; n.fy += dy; if (n.src) { n.sox += dx; n.soy += dy; } return; }
          const vx = (n.x + dx - p.x) / L, vy = (n.y + dy - p.y) / L, len = Math.hypot(vx, vy), base = Math.hypot(n.dx, n.dy);
          if (base > 1e-6 && len > 1e-6) {
            n.ov = len / base;
            n.ba = normA(Math.atan2(vy, vx) - Math.atan2(n.dy, n.dx));
            n.ta = 0; n.au = undefined; n.bf = undefined; n.lkl = undefined; n.lkv = undefined;
          }
        });
        layoutAll(); render(); touch();
        return true;
      } catch (err) { console.error(err); return false; }
    },
    coverBoxes(ids) {
      const arr = ids.map(byId).filter(Boolean);
      if (!arr.length) return false;
      const any = arr.some(n => !n.cover);
      arr.forEach(n => { n.cover = any; });
      render(); touch();
      return any;
    },
    deleteBoxes(ids) {
      let c = 0;
      ids.forEach(id => { const n = byId(id); if (n && n !== main && deleteBox(n)) c++; });
      return c;
    }
  };
    /* ---------- auto-save ---------- */
  // What is saved: the box structure (one text) and every drawing stroke as its own record. A save only writes what
  // changed since the last one, so its cost does not depend on how much ink there is. Saves are throttled, never run
  // while a stroke or a drag is in progress, and use asynchronous storage (IndexedDB, plus a file inside the app).
  function captureState() {
    const name = mapName, dr = dirty, txt = input.value;
    if (!main) return { empty: true, json: null, order: [], cur: new Map(), name, dirty: dr, txt, key: 'E|' + name + '|' + dr + '|' + txt };
    const s = snapshot(), ink = s.ink;
    s.ink = undefined;
    if (editNode && nodeSet.has(editNode)) s.pe = { i: editNode.id, t: nodeEdit.value };   // text still being typed
    const json = JSON.stringify(s), arr = ink && ink.s ? ink.s : [], cur = new Map(), order = [];
    for (const o of arr) { cur.set(o.i, o); order.push(o.i); }
    return { empty: false, json, order, cur, name, dirty: dr, txt, key: json + '|' + name + '|' + dr + '|' + order.join(',') };
  }
  function saveDraft() { if (store) store.request(); }
  // the app is leaving the screen: finish everything that is in progress, then save right now
  function flushAll() {
    try {
      if (window.MMP && window.MMP.flush) window.MMP.flush();          // strokes, lasso, eraser, paint settings
      if (mover) dropFree(); else if (dnode) dropDrag();               // a box that is being moved is put down where it is
      if (editNode) commitEdit();                                      // text that is still being typed
    } catch (err) { console.error(err); }
    clearTimeout(draftT);
    if (store) store.flush();
  }

  var store = (function () {
    const MIN_WAIT = 400, MAX_WAIT = 3000, NAT_GAP = 2500;
    const nat = () => { try { return window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.autosave; } catch (e) { return null; } };
    let db = null, opening = null, dbFail = false, fails = 0, busy = false, again = false, warned = false;
    let seq = 0, ready = false, pending = false, timer = 0, natT = 0, viewT = 0, firstReq = 0, lastReq = 0, lastNat = 0, legacyDone = false;
    const base = { idb: { ink: new Map(), key: null }, nat: { ink: new Map(), key: null } };   // what each store already holds
    const hard = () => !!(mover || dnode || (window.MMP && window.MMP.hard && window.MMP.hard()));
    const warn = m => { if (!warned) { warned = true; statusEl.textContent = m; } };
    const timeout = ms => new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms));

    function openDB() {
      if (db) return Promise.resolve(db);
      if (opening) return opening;
      opening = new Promise((res, rej) => {
        let rq;
        try { rq = indexedDB.open('mm-autosave', 1); } catch (e) { rej(e); return; }
        rq.onupgradeneeded = () => {
          const d = rq.result;
          if (!d.objectStoreNames.contains('kv')) d.createObjectStore('kv');
          if (!d.objectStoreNames.contains('ink')) d.createObjectStore('ink');
        };
        rq.onsuccess = () => {
          db = rq.result;
          db.onclose = () => { db = null; opening = null; };
          db.onversionchange = () => { try { db.close(); } catch (e) { /* ignore */ } db = null; opening = null; };
          res(db);
        };
        rq.onerror = () => rej(rq.error || new Error('indexedDB'));
        rq.onblocked = () => rej(new Error('indexedDB blocked'));
      });
      opening.catch(() => { opening = null; });
      return opening;
    }
    function idbLoad() {
      return openDB().then(d => new Promise((res, rej) => {
        const tx = d.transaction(['kv', 'ink'], 'readonly');
        const rs = tx.objectStore('kv').get('state'), ri = tx.objectStore('ink').getAll();
        tx.oncomplete = () => res({ rec: rs.result || null, ink: ri.result || [] });
        tx.onerror = tx.onabort = () => rej(tx.error || new Error('read failed'));
      }));
    }
    // one atomic transaction: the new strokes, the removed strokes and the state either all land or none do
    function idbCommit(rec, put, del) {
      return openDB().then(d => new Promise((res, rej) => {
        const tx = d.transaction(['kv', 'ink'], 'readwrite');
        const ink = tx.objectStore('ink'), kv = tx.objectStore('kv');
        put.forEach(o => ink.put(o, o.i));
        del.forEach(id => ink.delete(id));
        kv.put(rec, 'state');
        tx.oncomplete = () => res();
        tx.onerror = () => rej(tx.error || new Error('write failed'));
        tx.onabort = () => rej(tx.error || new Error('write aborted'));
      }));
    }
    function plan(b, cur, key) {
      const put = [], del = [];
      cur.forEach((o, id) => { if (b.ink.get(id) !== o) put.push(o); });
      b.ink.forEach((o, id) => { if (!cur.has(id)) del.push(id); });
      return { put, del, same: b.key === key && !put.length && !del.length };
    }
    // only used when the database cannot be used at all and there is no file copy either
    function fallback(cap) {
      if (nat()) return;
      let ok = false;
      try {
        const s = main ? snapshot() : null;
        if (s) ok = lsSet(DRAFT_KEY, { name: cap.name, dirty: cap.dirty, snap: s }); else { lsDel(DRAFT_KEY); ok = true; }
      } catch (e) { ok = false; }
      if (!ok) warn('Auto-save is not possible right now (storage is full or blocked). Use Export / import → Save file to keep a copy.');
    }
    function idbError(err) {
      console.error(err);
      db = null; opening = null;
      if (err && err.name === 'QuotaExceededError') {
        dbFail = true;
        warn('Auto-save: the database is full. Use Export / import → Save file to keep a copy.');
        return;
      }
      if (++fails >= 5) { dbFail = true; warn('Auto-save to the database stopped working. A backup copy is kept instead.'); return; }
      setTimeout(request, 800 * fails);
    }
    function commit(force) {
      let cap;
      try { cap = captureState(); } catch (err) { console.error(err); return; }
      const rec = { v: 1, seq: ++seq, t: Date.now(), name: cap.name, dirty: cap.dirty, json: cap.json, order: cap.order, empty: cap.empty, txt: cap.txt };
      const now = performance.now();
      if (!dbFail) {                                                   // 1) IndexedDB (asynchronous, written by the browser)
        const pl = plan(base.idb, cap.cur, cap.key);
        if (!pl.same) {
          if (busy) again = true;
          else {
            busy = true;
            Promise.race([idbCommit(rec, pl.put, pl.del), timeout(8000)]).then(() => {
              base.idb.ink = cap.cur; base.idb.key = cap.key; busy = false; fails = 0;
              if (!legacyDone) { legacyDone = true; lsDel(DRAFT_KEY); }   // the old single-key draft is no longer needed
              if (again) { again = false; request(); }
            }, err => { busy = false; again = false; idbError(err); });
          }
        }
      } else fallback(cap);
      const n = nat();                                                  // 2) a second copy as files inside the app
      if (n) {
        const pn = plan(base.nat, cap.cur, cap.key);
        if (!pn.same) {
          if (force || now - lastNat >= NAT_GAP) {
            try {
              for (let i = 0; i < pn.put.length; i += 300) n.postMessage({ put: pn.put.slice(i, i + 300).map(o => [o.i, JSON.stringify(o)]) });
              n.postMessage({ state: JSON.stringify(rec), del: pn.del });
              base.nat.ink = cap.cur; base.nat.key = cap.key; lastNat = now;
            } catch (err) { console.error(err); }
          } else { clearTimeout(natT); natT = setTimeout(request, Math.max(150, NAT_GAP - (now - lastNat) + 50)); }
        }
      }
    }
    function arm() {
      clearTimeout(timer);
      timer = setTimeout(run, Math.max(30, Math.min(lastReq + MIN_WAIT, firstReq + MAX_WAIT) - performance.now()));
    }
    function run() {
      timer = 0;
      if (hard()) { timer = setTimeout(run, 200); return; }            // never while a stroke is being drawn or a box is dragged
      firstReq = 0;
      commit(false);
    }
    function request() {
      if (!ready) { pending = true; return; }
      const t = performance.now();
      if (!firstReq) firstReq = t;
      lastReq = t; arm();
    }
    function putView() { try { localStorage.setItem('mm-view', JSON.stringify({ t: Date.now(), x: view.x, y: view.y, k: view.k })); } catch (e) { /* ignore */ } }
    function viewSoon() { if (!ready) return; clearTimeout(viewT); viewT = setTimeout(putView, 800); }
    function loadView() { try { return JSON.parse(localStorage.getItem('mm-view') || 'null'); } catch (e) { return null; } }
    function flush() {
      clearTimeout(timer); timer = 0; firstReq = 0; clearTimeout(viewT);
      if (!ready) return;
      putView();
      commit(true);
    }

    const inkMapOf = list => { const m = new Map(); list.forEach(o => { if (o && typeof o.i === 'number') m.set(o.i, o); }); return m; };
    const rank = c => (c.src === 'idb' ? 0 : c.src === 'native' ? 1 : 2);
    async function candidates() {
      const out = [];
      try {
        const r = await Promise.race([idbLoad(), timeout(3500)]);
        if (r && r.rec) out.push({ src: 'idb', t: r.rec.t || 0, rec: r.rec, inkMap: inkMapOf(r.ink) });
        else if (r) base.idb.ink = inkMapOf(r.ink);
      } catch (err) { console.error(err); }
      try {
        const b = window.__nativeBoot;
        if (b && b.state) {
          const rec = JSON.parse(b.state), ink = [];
          (b.ink || []).forEach(s => { try { const o = JSON.parse(s); if (o && typeof o.i === 'number') ink.push(o); } catch (e) { /* skip a damaged stroke */ } });
          out.push({ src: 'native', t: rec.t || 0, rec, inkMap: inkMapOf(ink) });
        }
      } catch (err) { console.error(err); }
      const lg = lsGet(DRAFT_KEY);
      if (lg && lg.snap) out.push({ src: 'legacy', t: 0, rec: { legacy: lg.snap, name: lg.name, dirty: lg.dirty }, inkMap: new Map() });
      out.sort((a, b) => (b.t - a.t) || (rank(a) - rank(b)));
      return out;
    }
    // after the start-up restore: tells each store what it already holds, so the first save only writes what is missing
    function adopt(used, cands) {
      cands.forEach(c => { if (c.rec && c.rec.seq > seq) seq = c.rec.seq; });
      const idb = cands.find(c => c.src === 'idb'), nt = cands.find(c => c.src === 'native');
      const same = c => !!(c && used && !used.rec.legacy && c.t === used.t);
      base.idb.ink = same(idb) ? used.inkMap : (idb ? idb.inkMap : base.idb.ink);
      base.nat.ink = same(nt) ? used.inkMap : (nt ? nt.inkMap : new Map());
      base.idb.key = null; base.nat.key = null;
      const stale = !same(idb) || (!!nat() && !same(nt));
      ready = true;
      if (pending || stale) { pending = false; request(); }
    }
    // a saved copy that could not be opened is kept aside instead of being overwritten
    function keepBad(c) {
      openDB().then(d => { d.transaction('kv', 'readwrite').objectStore('kv').put({ t: Date.now(), src: c.src, rec: c.rec }, 'bad-' + Date.now()); }).catch(() => { /* best effort */ });
    }
    return { request, flush, candidates, adopt, keepBad, viewSoon, loadView };
  })();

  function applyCandidate(c, partial) {
    const rec = c.rec;
    if (rec.legacy) {                                                  // the old single-key draft
      restore(rec.legacy);
      mapName = rec.name || ''; dirty = !!rec.dirty; libName.value = mapName; renderLib(); resetHist();
      if (dirty) showSaveDialog();
      return true;
    }
    if (rec.empty) {                                                   // "New map" was the last thing done
      if (rec.txt) {
        input.value = rec.txt; mapName = ''; dirty = false; resetHist();
        levelsBody.innerHTML = '<small>Generate a map first.</small>';
        statusEl.textContent = 'Type or paste text, then press Generate.';
      } else { input.value = SAMPLE; generate(true); }
      return true;
    }
    const s = JSON.parse(rec.json), arr = [];
    let miss = 0;
    (rec.order || []).forEach(id => { const o = c.inkMap.get(id); if (o) arr.push(o); else miss++; });
    if (miss && !partial) return false;                                // this copy is incomplete: try another one first
    s.ink = arr.length ? { s: arr } : undefined;
    restore(s);
    mapName = rec.name || ''; dirty = !!rec.dirty; libName.value = mapName; renderLib(); resetHist();
    const mv = store.loadView();                                       // the last pan / zoom, saved separately
    if (mv && mv.t >= (rec.t || 0) && Number.isFinite(mv.x) && Number.isFinite(mv.y) && mv.k > 0) { view.x = mv.x; view.y = mv.y; view.k = mv.k; applyView(); }
    if (miss) statusEl.textContent = miss + ' drawing stroke' + (miss > 1 ? 's' : '') + ' could not be recovered.';
    if (dirty) showSaveDialog();
    return true;
  }
  async function bootFromStore() {
    statusEl.textContent = 'Opening your last map…';
    let cands = [];
    try { cands = await store.candidates(); } catch (err) { console.error(err); }
    let used = null;
    const tryOne = (c, partial) => {
      try { return applyCandidate(c, partial); }
      catch (err) { console.error(err); store.keepBad(c); statusEl.textContent = 'One saved copy could not be opened. A backup of it was kept aside.'; return false; }
    };
    for (const c of cands) { if (tryOne(c, false)) { used = c; break; } }
    if (!used) for (const c of cands) { if (tryOne(c, true)) { used = c; break; } }
    if (!used) { input.value = SAMPLE; generate(true); }
    store.adopt(used, cands);
  }
  function bootAfterParse() {                                          // wait until the painting script has also started
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bootFromStore, { once: true });
    else bootFromStore();
  }
  nodeEdit.addEventListener('input', () => { if (store) store.request(); });
  input.addEventListener('input', () => { if (store) store.request(); });
  ['freeze', 'beforeunload'].forEach(ev => window.addEventListener(ev, flushAll));
  const d0 = null;


  let restored = false;
  if (d0 && d0.snap) {
    try { restore(d0.snap); mapName = d0.name || ''; dirty = !!d0.dirty; restored = true; libName.value = mapName; renderLib(); resetHist(); }
    catch (err) { console.error(err); }
  }
    if (!restored) bootAfterParse();

  else if (dirty) showSaveDialog();
})();
"""#







