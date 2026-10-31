import SwiftUI
import WebKit
import UIKit

struct ContentView: View {
    var body: some View {
        WebView(html: fullHTML)
            .ignoresSafeArea()
    }
}

// A second copy of your work, kept as files inside the app (next to the web database):
//   state.json = the map structure, ink/<id>.json = one file per drawing stroke
enum Autosave {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindMap", isDirectory: true)
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("ink", isDirectory: true), withIntermediateDirectories: true)
        return base
    }()
    static var inkDir: URL { dir.appendingPathComponent("ink", isDirectory: true) }
    static let queue = DispatchQueue(label: "mindmap.autosave")
    
    // reads the saved copy and returns a script that hands it to the page before the page starts
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
    
    // strokes first, then the state, then deletions: the state on disk always refers to strokes that exist
    static func write(_ d: [String: Any]) {
        let fm = FileManager.default
        if let put = d["put"] as? [[Any]] {
            for e in put where e.count == 2 {
                guard let n = e[0] as? NSNumber, let s = e[1] as? String, let data = s.data(using: .utf8) else { continue }
                try? data.write(to: inkDir.appendingPathComponent("\(n.intValue).json"), options: .atomic)
            }
        }
        if let s = d["state"] as? String, let data = s.data(using: .utf8) {
            try? data.write(to: dir.appendingPathComponent("state.json"), options: .atomic)
        }
        if let del = d["del"] as? [NSNumber] {
            for n in del { try? fm.removeItem(at: inkDir.appendingPathComponent("\(n.intValue).json")) }
        }
    }
}

struct WebView: UIViewRepresentable {
    let html: String
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var web: WKWebView?
        
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "autosave" {
                guard let d = message.body as? [String: Any] else { return }
                var task: UIBackgroundTaskIdentifier = .invalid
                task = UIApplication.shared.beginBackgroundTask(withName: "mindmap-autosave") {
                    UIApplication.shared.endBackgroundTask(task)
                    task = .invalid
                }
                Autosave.queue.async {
                    Autosave.write(d)
                    DispatchQueue.main.async {
                        if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
                    }
                }
                return
            }
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
        
        // writes the file to a temporary place and opens the share sheet (Save to Files, AirDrop, …)
        private func share(name: String, data: Data) {
            let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(clean)
            do { try data.write(to: url, options: .atomic) } catch { return }
            DispatchQueue.main.async {
                guard let web = self.web else { return }
                var top = web.window?.rootViewController
                while let next = top?.presentedViewController { top = next }
                guard let host = top else { return }
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
        config.userContentController.add(context.coordinator, name: "autosave")
        let boot = Autosave.bootScript()
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
        webView.loadHTMLString(html, baseURL: URL(string: "https://mindmap.local"))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}


