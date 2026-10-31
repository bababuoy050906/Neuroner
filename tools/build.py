#!/usr/bin/env python3
"""Builds the static site in ./docs from the Swift sources in ./swift-src."""
import hashlib, math, re, shutil, struct, subprocess, sys, urllib.request, zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SWIFT, WEB, OUT = ROOT / "swift-src", ROOT / "web-src", ROOT / "docs"
VENDOR = {
    "jspdf.umd.min.js": "https://cdn.jsdelivr.net/npm/jspdf@2.5.1/dist/jspdf.umd.min.js",
    "svg2pdf.umd.min.js": "https://cdn.jsdelivr.net/npm/svg2pdf.js@2.2.4/dist/svg2pdf.umd.min.js",
}

def die(msg):
    print("ERROR: " + msg); sys.exit(1)

def swift_raw_strings():
    """Finds every  let NAME = #\"\"\" ... \"\"\"#  in swift-src/*.swift (first definition wins)."""
    found = {}
    pat = re.compile(r'\blet\s+(\w+)\s*(?::\s*String)?\s*=\s*#"""[ \t]*\n(.*?)\n([ \t]*)"""#', re.S)
    for f in sorted(SWIFT.rglob("*.swift")):
        text = f.read_text(encoding="utf-8").replace("\r\n", "\n")
        for m in pat.finditer(text):
            name, body, indent = m.groups()
            if indent:  # Swift strips the closing delimiter's indentation
                body = "\n".join(l[len(indent):] if l.startswith(indent) else l for l in body.split("\n"))
            found.setdefault(name, body)
    return found

def between(s, a, b):
    i = s.find(a)
    if i < 0: return ""
    i += len(a); j = s.find(b, i)
    return s[i:j] if j >= 0 else ""

def write_png(path, w, h, raw):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

def make_icon(path, s):
    bg = (42, 157, 143)
    cx = cy = s / 2
    sats = [(.27, .28, (230, 57, 70)), (.73, .28, (244, 162, 97)), (.27, .72, (155, 93, 229)), (.73, .72, (233, 196, 106))]
    sats = [(x * s, y * s, c) for x, y, c in sats]
    rc, rs, lw = s * .15, s * .085, s * .022
    def seg(px, py, ax, ay, bx, by):
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        return math.hypot(px - ax - t * dx, py - ay - t * dy)
    def cov(d, r): return max(0.0, min(1.0, r - d + 0.5))
    raw = bytearray()
    for y in range(s):
        raw.append(0)
        for x in range(s):
            px = list(bg)
            def over(c, a):
                if a > 0:
                    for i in range(3): px[i] = px[i] + (c[i] - px[i]) * a
            for sx, sy, _ in sats: over((255, 255, 255), cov(seg(x, y, cx, cy, sx, sy), lw / 2))
            over((255, 255, 255), cov(math.hypot(x - cx, y - cy), rc))
            for sx, sy, c in sats: over(c, cov(math.hypot(x - sx, y - sy), rs))
            raw.extend(int(v) for v in px)
    write_png(path, s, s, raw)

def main():
    if not SWIFT.is_dir(): die("put your .swift files in " + str(SWIFT))
    S = swift_raw_strings()
    for n in ("extraCSS", "bodyHTML", "pageHTML", "appJS", "paintJS"):
        if n not in S: die('`let %s = #"""..."""#` not found in swift-src/*.swift' % n)

    page = S["pageHTML"]
    old_css = between(page, "<style>", "</style>")
    nlp_b = between(page, "(function (global) {", "})(window);")
    lay_b = between(page, "(function (g) {", "})(window);")
    if not (old_css and nlp_b and lay_b): die("could not slice pageHTML (style / nlp / layout)")
    if "window.MMX" not in S["appJS"]: die("appJS does not define window.MMX")

    if OUT.exists(): shutil.rmtree(OUT)
    for d in ("css", "js", "vendor", "icons"): (OUT / d).mkdir(parents=True)
    (OUT / ".nojekyll").write_text("")

    css = old_css + "\n" + S["extraCSS"] + "\n" + (WEB / "web.css").read_text(encoding="utf-8")
    (OUT / "css/app.css").write_text(css, encoding="utf-8")
    (OUT / "js/nlp.js").write_text("(function (global) {" + nlp_b + "})(window);", encoding="utf-8")
    (OUT / "js/layout.js").write_text("(function (g) {" + lay_b + "})(window);", encoding="utf-8")
    (OUT / "js/app.js").write_text(S["appJS"], encoding="utf-8")
    (OUT / "js/paint.js").write_text(S["paintJS"], encoding="utf-8")
    shutil.copy(WEB / "bridge.js", OUT / "js/bridge.js")
    shutil.copy(WEB / "manifest.webmanifest", OUT / "manifest.webmanifest")
    html = (WEB / "index.template.html").read_text(encoding="utf-8").replace("%%BODY%%", S["bodyHTML"])
    (OUT / "index.html").write_text(html, encoding="utf-8")

    cache = WEB / "vendor"; cache.mkdir(exist_ok=True)
    for name, url in VENDOR.items():
        f = cache / name
        if not f.exists():
            try: f.write_bytes(urllib.request.urlopen(url, timeout=30).read())
            except Exception as e: print("warn: could not download", name, e); continue
        shutil.copy(f, OUT / "vendor" / name)

    for size in (180, 192, 512):
        custom = WEB / "icons" / ("icon-%d.png" % size)
        if custom.exists(): shutil.copy(custom, OUT / "icons" / custom.name)
        else: make_icon(OUT / "icons" / ("icon-%d.png" % size), size)

    h = hashlib.sha1()
    for f in sorted(OUT.rglob("*")):
        if f.is_file(): h.update(f.read_bytes())
    sw = (WEB / "sw.template.js").read_text(encoding="utf-8").replace("__BUILD__", h.hexdigest()[:10])
    (OUT / "sw.js").write_text(sw, encoding="utf-8")

    node = shutil.which("node")
    if node:
        for js in sorted((OUT / "js").glob("*.js")):
            r = subprocess.run([node, "--check", str(js)], capture_output=True, text=True)
            print(("ok   " if r.returncode == 0 else "FAIL ") + js.name + ("" if r.returncode == 0 else "\n" + r.stderr))
    print("Built", OUT)

if __name__ == "__main__":
    main()

