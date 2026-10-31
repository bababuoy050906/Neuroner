const BUILD = '__BUILD__';
const CACHE = 'mindmap-' + BUILD;
const SHELL = ['./', 'index.html', 'css/app.css', 'js/bridge.js', 'js/nlp.js', 'js/layout.js', 'js/app.js', 'js/paint.js',
  'vendor/jspdf.umd.min.js', 'vendor/svg2pdf.umd.min.js', 'manifest.webmanifest',
  'icons/icon-180.png', 'icons/icon-192.png', 'icons/icon-512.png'];

// No skipWaiting: a new version takes over only after every open tab is closed,
// so one page never mixes old and new files.
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(SHELL.map(u => c.add(new Request(u, { cache: 'reload' })).catch(() => {})))));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k.startsWith('mindmap-') && k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
// stale-while-revalidate: instant + works offline, refreshes in the background
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET' || !/^https?:$/.test(new URL(r.url).protocol)) return;
  e.respondWith(caches.open(CACHE).then(async c => {
    const hit = await c.match(r, { ignoreSearch: true });
    const net = fetch(r).then(res => { if (res && (res.ok || res.type === 'opaque')) c.put(r, res.clone()); return res; }).catch(() => null);
    return hit || (await net) || (r.mode === 'navigate' && await c.match('index.html')) || new Response('Offline', { status: 503 });
  }));
});

