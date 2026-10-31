/* Web replacement for the Swift/WKWebView bridge (autosave, saveFile, haptic, boot data).
   NOTE on storage: the app's own autosave (IndexedDB "mm-autosave") is the main copy.
   "mm-mirror" below is a second IndexedDB on the same site. It guards against a damaged
   database, NOT against the browser clearing site data (both would go together).
   Real backups: Export / import -> Save file (.mindmap). */
(function () {
  'use strict';

  function showErr(msg) {
    var b = document.getElementById('errBar');
    if (!b) {
      b = document.createElement('div'); b.id = 'errBar';
      b.style.cssText = 'position:fixed;left:0;right:0;top:0;z-index:99999;background:#E63946;color:#fff;font:12px/1.35 Helvetica,Arial,sans-serif;padding:8px 10px;white-space:pre-wrap;max-height:40vh;overflow:auto';
      document.body.appendChild(b);
    }
    b.textContent += '⚠ ' + msg + '\n';
  }
  window.addEventListener('error', function (e) { showErr(e.message); });
  window.addEventListener('unhandledrejection', function (e) { showErr(String((e.reason && e.reason.message) || e.reason)); });

  /* ---------- mirror database ---------- */
  function openMirror() {
    return new Promise(function (res, rej) {
      if (!window.indexedDB) return rej(new Error('no IndexedDB'));
      var r;
      try { r = indexedDB.open('mm-mirror', 1); } catch (e) { return rej(e); }
      r.onupgradeneeded = function () { r.result.createObjectStore('kv'); r.result.createObjectStore('ink'); };
      r.onsuccess = function () { res(r.result); };
      r.onerror = function () { rej(r.error); };
      r.onblocked = function () { rej(new Error('blocked')); };
    });
  }
  function mirrorLoad(db) {
    return new Promise(function (res, rej) {
      var tx = db.transaction(['kv', 'ink'], 'readonly');
      var s = tx.objectStore('kv').get('state'), i = tx.objectStore('ink').getAll();
      tx.oncomplete = function () { res({ state: s.result || null, ink: i.result || [] }); };
      tx.onerror = tx.onabort = function () { rej(tx.error); };
    });
  }
  // strokes, then the state, then deletions, all in ONE transaction (atomic)
  function mirrorApply(db, d) {
    return new Promise(function (res, rej) {
      var tx = db.transaction(['kv', 'ink'], 'readwrite'), ink = tx.objectStore('ink'), kv = tx.objectStore('kv');
      (d.put || []).forEach(function (e) { if (e && e.length === 2) ink.put(String(e[1]), Number(e[0])); });
      if (typeof d.state === 'string') kv.put(d.state, 'state');
      (d.del || []).forEach(function (n) { ink.delete(Number(n)); });
      tx.oncomplete = function () { res(); };
      tx.onerror = tx.onabort = function () { rej(tx.error); };
    });
  }

  /* ---------- save / share a file (PDF, .mindmap, .json) ---------- */
  var MIME = { pdf: 'application/pdf', json: 'application/json', mindmap: 'application/json', txt: 'text/plain' };
  function download(blob, name) {
    var url = URL.createObjectURL(blob), a = document.createElement('a');
    a.href = url; a.download = name; a.style.display = 'none';
    document.body.appendChild(a); a.click();
    setTimeout(function () { a.remove(); URL.revokeObjectURL(url); }, 60000);
  }
  function saveFile(d) {
    if (!d || !d.name) return;
    var name = String(d.name).replace(/[\/:\\]/g, '-'), ext = (name.split('.').pop() || '').toLowerCase();
    var type = MIME[ext] || 'application/octet-stream', blob;
    if (d.b64) {
      var bin = atob(d.b64), u = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
      blob = new Blob([u], { type: type });
    } else if (typeof d.data === 'string') blob = new Blob([d.data], { type: type });
    else return;
    var file = null; try { file = new File([blob], name, { type: type }); } catch (e) { /* old browser */ }
    var touch = window.matchMedia && matchMedia('(pointer:coarse)').matches;
    // phones/tablets: share sheet (Save to Files, AirDrop, Drive...). Desktop: plain download.
    if (touch && file && navigator.canShare && navigator.canShare({ files: [file] })) {
      navigator.share({ files: [file] }).catch(function (e) { if (!e || e.name !== 'AbortError') download(blob, name); });
    } else download(blob, name);
  }

  /* ---------- the three "native" handlers ---------- */
  function install(db) {
    var chain = Promise.resolve();
    var H = {
      haptic: { postMessage: function () { try { if (navigator.vibrate) navigator.vibrate(30); } catch (e) { /* iOS has none */ } } },
      saveFile: { postMessage: saveFile }
    };
    if (db) H.autosave = {
      postMessage: function (d) {
        if (!d || typeof d !== 'object') return;
        var job = { put: (d.put || []).slice(), state: d.state, del: (d.del || []).slice() };
        chain = chain.then(function () { return mirrorApply(db, job); }).catch(function (e) { console.warn('mirror save failed', e); });
      }
    };
    try {
      var w = window.webkit || (window.webkit = {});
      try { w.messageHandlers = H; } catch (e) { Object.defineProperty(w, 'messageHandlers', { value: H, configurable: true }); }
    } catch (e) { try { Object.defineProperty(window, 'webkit', { value: { messageHandlers: H }, configurable: true }); } catch (e2) { /* ignore */ } }
  }

  /* ---------- input hardening + shortcuts ---------- */
  document.addEventListener('contextmenu', function (e) {           // Android long-press / Windows right-click on the canvas
    if (e.target.closest && e.target.closest('#canvas')) e.preventDefault();
  });
  document.addEventListener('keydown', function (e) {               // Ctrl/Cmd+Z, Ctrl+Shift+Z, Ctrl+Y
    if (!(e.ctrlKey || e.metaKey)) return;
    var t = e.target, tag = t && t.tagName, type = t && t.type;
    var typing = tag === 'TEXTAREA' || tag === 'SELECT' || (tag === 'INPUT' && type !== 'range' && type !== 'checkbox' && type !== 'button');
    if (typing) return;                                              // sliders and checkboxes do not use Ctrl+Z themselves
    var k = (e.key || '').toLowerCase(), id = k === 'z' ? (e.shiftKey ? 'redoBtn' : 'undoBtn') : (k === 'y' ? 'redoBtn' : null);
    var b = id && document.getElementById(id);
    if (b && !b.disabled) { e.preventDefault(); b.click(); }
  });
  try { if (navigator.storage && navigator.storage.persist) navigator.storage.persist(); } catch (e) { /* ignore */ }

  /* ---------- boot: install handlers and restore the mirror BEFORE the app scripts run ---------- */
  function load(src, alt) {
    return new Promise(function (res, rej) {
      var s = document.createElement('script');
      s.src = src; s.onload = res;
      s.onerror = function () { s.remove(); if (alt) load(alt).then(res, rej); else rej(new Error('Failed to load ' + src)); };
      document.body.appendChild(s);
    });
  }
  // [local file, CDN fallback, optional]  (the PDF libraries are reloaded on demand by the app if missing)
  var ORDER = [
    ['vendor/jspdf.umd.min.js', 'https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js', true],
    ['vendor/svg2pdf.umd.min.js', 'https://cdn.jsdelivr.net/npm/svg2pdf.js@2.2.4/dist/svg2pdf.umd.min.js', true],
    ['js/nlp.js'], ['js/layout.js'], ['js/app.js'], ['js/paint.js']
  ];

  openMirror()
    .then(function (db) { return mirrorLoad(db).then(function (s) { return { db: db, saved: s }; }, function () { return { db: db, saved: null }; }); },
          function () { return { db: null, saved: null }; })
    .then(function (r) {
      install(r.db);
      if (r.saved && r.saved.state) window.__nativeBoot = { state: r.saved.state, ink: r.saved.ink };   // same shape Swift injected
      return ORDER.reduce(function (p, s) {
        return p.then(function () { return load(s[0], s[1]).catch(function (e) { if (!s[2]) throw e; }); });
      }, Promise.resolve());
    })
    .catch(function (e) { showErr(e.message); });

  /* ---------- offline support ---------- */
  if ('serviceWorker' in navigator && location.protocol !== 'file:') {
    window.addEventListener('load', function () { navigator.serviceWorker.register('sw.js').catch(function () {}); });
  }
})();

