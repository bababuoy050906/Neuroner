import SwiftUI
import WebKit
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    var body: some View {
        WebView(html: fullHTML)
            .ignoresSafeArea()
    }
}

// The old app-internal copy. It is only read once, so the page can move it into the chosen folder, then it is deleted.
enum Legacy {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindMap", isDirectory: true)
    }
    static var inkDir: URL { dir.appendingPathComponent("ink", isDirectory: true) }
    
    static func bootScript() -> String {
        var payload: [String: Any] = [:]
        if let d = try? Data(contentsOf: dir.appendingPathComponent("state.json")),
           let s = String(data: d, encoding: .utf8) {
            payload["state"] = s
            var strokes: [String] = []
            if let files = try? FileManager.default.contentsOfDirectory(at: inkDir, includingPropertiesForKeys: nil) {
                for f in files where f.pathExtension == "json" {
                    if let sd = try? Data(contentsOf: f), let ss = String(data: sd, encoding: .utf8) { strokes.append(ss) }
                }
            }
            payload["ink"] = strokes
        }
        guard !payload.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let js = String(data: data, encoding: .utf8) else { return "" }
        return "window.__nativeBoot = " + js + ";"
    }
    
    static func clear() { try? FileManager.default.removeItem(at: dir) }
}

// The folder the user picked. Every map is one .mindmap file in it, plus settings.json.
// The folder is remembered as a security-scoped bookmark.
final class LibraryStore: NSObject, UIDocumentPickerDelegate {
    static let shared = LibraryStore()
    let io = DispatchQueue(label: "mindmap.library")
    private let lock = NSLock()
    private let key = "mm.folder.bookmark"
    private var root: URL?
    private var pickDone: ((Bool) -> Void)?
    
    var folderName: String? { resolve()?.lastPathComponent }
    
    func resolve() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let r = root { return r }
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let nd = try? url.bookmarkData() { UserDefaults.standard.set(nd, forKey: key) }
        root = url
        return url
    }
    
    // MARK: folder picker
    func choose(from host: UIViewController, done: @escaping (Bool) -> Void) {
        pickDone = done
        let pk = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        pk.delegate = self
        pk.allowsMultipleSelection = false
        host.present(pk, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, url.startAccessingSecurityScopedResource(),
              let data = try? url.bookmarkData() else { finish(false); return }
        lock.lock(); root?.stopAccessingSecurityScopedResource(); root = url; lock.unlock()
        UserDefaults.standard.set(data, forKey: key)
        finish(true)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }
    private func finish(_ ok: Bool) {
        let d = pickDone; pickDone = nil
        DispatchQueue.main.async { d?(ok) }
    }
    
    // MARK: files (always called on `io`, never on the main thread)
    private func fail(_ m: String) -> NSError { NSError(domain: "mindmap", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
    private func safe(_ n: String) -> String? {
        let ext = (n as NSString).pathExtension.lowercased()
        guard !n.isEmpty, !n.contains("/"), n != ".", n != "..", ["mindmap", "json", "bak"].contains(ext) else { return nil }
        return n
    }
    private func mtime(_ u: URL) -> Double? {
        guard let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        return d.timeIntervalSince1970 * 1000
    }
    
    func list() -> [[String: Any]] {
        guard let r = resolve() else { return [] }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: r, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let rows: [[String: Any]] = items.filter { $0.pathExtension.lowercased() == "mindmap" }.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return ["name": u.lastPathComponent,
                    "t": (v?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000,
                    "size": v?.fileSize ?? 0]
        }
        return rows.sorted { ($0["t"] as? Double ?? 0) > ($1["t"] as? Double ?? 0) }
    }
    func read(_ name: String) -> String? {
        guard let r = resolve(), let n = safe(name),
              let d = try? Data(contentsOf: r.appendingPathComponent(n)) else { return nil }
        return String(data: d, encoding: .utf8)
    }
    func stat(_ name: String) -> Double? {
        guard let r = resolve(), let n = safe(name) else { return nil }
        return mtime(r.appendingPathComponent(n))
    }
    // temp file first, then an atomic replace; the file it replaces is kept as one .bak
    func write(_ name: String, _ text: String, bak: Bool) throws -> Double {
        guard let r = resolve(), let n = safe(name), let data = text.data(using: .utf8) else { throw fail("bad request") }
        let fm = FileManager.default
        let dst = r.appendingPathComponent(n), tmp = r.appendingPathComponent(".\(n).tmp")
        do {
            try data.write(to: tmp)
            if fm.fileExists(atPath: dst.path) {
                _ = try fm.replaceItemAt(dst, withItemAt: tmp)      // the temp file is consumed by the replace
            } else {
                try fm.moveItem(at: tmp, to: dst)
            }
            try? fm.removeItem(at: r.appendingPathComponent(n + ".bak"))   // no backup copy stays behind
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        return mtime(dst) ?? Date().timeIntervalSince1970 * 1000
    }
    func rename(_ a: String, _ b: String) throws {
        guard let r = resolve(), let x = safe(a), let y = safe(b) else { throw fail("bad name") }
        let fm = FileManager.default
        let src = r.appendingPathComponent(x), dst = r.appendingPathComponent(y)
        if fm.fileExists(atPath: dst.path) && x.lowercased() != y.lowercased() { throw fail("A file with that name already exists") }
        try fm.moveItem(at: src, to: dst)
        let ob = r.appendingPathComponent(y + ".bak")
        try? fm.removeItem(at: ob)
        try? fm.moveItem(at: r.appendingPathComponent(x + ".bak"), to: ob)
    }
    func remove(_ name: String) throws {
        guard let r = resolve(), let n = safe(name) else { throw fail("bad name") }
        try FileManager.default.removeItem(at: r.appendingPathComponent(n))
        try? FileManager.default.removeItem(at: r.appendingPathComponent(n + ".bak"))
    }
    
    // handed to the page before it starts: the folder and the app settings, so the first screen already has them
    func bootScript() -> String {
        var p: [String: Any] = ["has": false, "folder": ""]
        if let r = resolve() {
            p["has"] = true
            p["folder"] = r.lastPathComponent
            if let d = try? Data(contentsOf: r.appendingPathComponent("settings.json")),
               let s = String(data: d, encoding: .utf8) { p["settings"] = s }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: p),
              let js = String(data: data, encoding: .utf8) else { return "" }
        return "window.__libBoot = " + js + ";"
    }
}

struct WebView: UIViewRepresentable {
    let html: String
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "lib" { handleLib(message.body); return }
            if message.name == "saveFile" {
                guard let d = message.body as? [String: Any],
                      let name = d["name"] as? String else { return }
                var data: Data? = nil
                if let b64 = d["b64"] as? String { data = Data(base64Encoded: b64) }
                else if let text = d["data"] as? String { data = text.data(using: .utf8) }
                guard let bytes = data else { return }
                share(name: name, data: bytes)
                return
            }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        
        // library requests from the page: the work runs on a background queue, the answer goes back by id
        private func handleLib(_ body: Any) {
            guard let d = body as? [String: Any], let id = d["id"] as? Int, let op = d["op"] as? String else { return }
            if op == "choose" {
                guard let host = topVC() else { reply(id, ["ok": false]); return }
                LibraryStore.shared.choose(from: host) { [weak self] ok in
                    self?.reply(id, ["ok": ok, "folder": LibraryStore.shared.folderName ?? ""])
                }
                return
            }
            var task: UIBackgroundTaskIdentifier = .invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "mindmap-library") {
                UIApplication.shared.endBackgroundTask(task)
                task = .invalid
            }
            LibraryStore.shared.io.async { [weak self] in
                let r = self?.run(op, d) ?? ["ok": false]
                DispatchQueue.main.async {
                    self?.reply(id, r)
                    if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
                }
            }
        }
        
        private func run(_ op: String, _ d: [String: Any]) -> [String: Any] {
            let L = LibraryStore.shared
            let name = d["name"] as? String ?? ""
            do {
                switch op {
                case "list":
                    return ["ok": true, "files": L.list()]
                case "read":
                    if let s = L.read(name) { return ["ok": true, "text": s] }
                    return ["ok": false]
                case "stat":
                    if let t = L.stat(name) { return ["ok": true, "t": t] }
                    return ["ok": true, "t": NSNull()]
                case "write":
                    let t = try L.write(name, d["text"] as? String ?? "", bak: d["bak"] as? Bool ?? false)
                    return ["ok": true, "t": t]
                case "rename":
                    try L.rename(d["from"] as? String ?? "", d["to"] as? String ?? "")
                    return ["ok": true]
                case "remove":
                    try L.remove(name)
                    return ["ok": true]
                case "legacyClear":
                    Legacy.clear()
                    return ["ok": true]
                default:
                    return ["ok": false, "err": "unknown request"]
                }
            } catch {
                return ["ok": false, "err": error.localizedDescription]
            }
        }
        
        private func reply(_ id: Int, _ r: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: r),
                  let js = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.__libReply && window.__libReply(\(id), \(js))")
        }
        
        private func topVC() -> UIViewController? {
            var top = web?.window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            return top
        }
        
        // writes the file to a temporary place and opens the share sheet (Save to Files, AirDrop, …)
        private func share(name: String, data: Data) {
            let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(clean)
            do { try data.write(to: url, options: .atomic) } catch { return }
            DispatchQueue.main.async {
                guard let web = self.web, let host = self.topVC() else { return }
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                if let pop = vc.popoverPresentationController {
                    pop.sourceView = web
                    pop.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 1, height: 1)
                    pop.permittedArrowDirections = []
                }
                host.present(vc, animated: true)
            }
        }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "haptic")
        config.userContentController.add(context.coordinator, name: "saveFile")
        config.userContentController.add(context.coordinator, name: "lib")
        var boot = LibraryStore.shared.bootScript()
        boot += Legacy.bootScript()
        if !boot.isEmpty {
            config.userContentController.addUserScript(
                WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.web = webView
        webView.isOpaque = false
        // the page itself never zooms or bounces: only the canvas pans and zooms
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        // leaving the screen: the page writes its file right now (the write itself runs inside a background-task grace period)
        for n in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak webView] _ in
                webView?.evaluateJavaScript("window.__mmFlush && window.__mmFlush()")
            }
        }
        webView.loadHTMLString(html, baseURL: URL(string: "https://mindmap.local"))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
