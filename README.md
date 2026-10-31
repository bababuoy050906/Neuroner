# Text → Mind Map (web)

Static site built from the Swift sources.

    python3 tools/build.py               # writes docs/
    python3 -m http.server -d docs 8080  # http://localhost:8080

Keep swift-src/ in the repo: the build extracts the web code from it.
Deploy: push to main, then Settings → Pages → Source: GitHub Actions.

Backups: Library → Export / import → Save file (.mindmap, includes drawings).
Browser storage can be cleared by the browser, so export now and then.

