import AppKit
import Win95

/// Owns the browser windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var browsers: [BrowserWindow] = []

    func newWindow(cascadeFrom p: NSPoint? = nil) -> BrowserWindow {
        let b = BrowserWindow(cascadeFrom: p)
        browsers.append(b)
        b.show()
        return b
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
W95Menus.installMainMenu(appName: "Gemini 95")
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate

let screen = NSScreen.main!.frame

// --- Render mode: draw a browser window offscreen to a PNG ------------------
// --render [out.png] [gemini://url-to-fetch-first]
if CommandLine.arguments.contains("--render") {
    var out = "/tmp/gemini95.png"
    var fetchURL: URL?
    if let i = CommandLine.arguments.firstIndex(of: "--render") {
        for arg in CommandLine.arguments[(i + 1)...] {
            if arg.hasPrefix("gemini://") { fetchURL = URL(string: arg) }
            else { out = arg }
        }
    }
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = W95.desktopTeal.cgColor

    let b = BrowserWindow()

    func snapshot() -> Never {
        b.window.contentView!.layoutSubtreeIfNeeded()
        b.window.contentView!.frame = NSRect(origin: NSPoint(x: 60, y: 60),
                                             size: b.window.contentView!.frame.size)
        canvas.addSubview(b.window.contentView!)

        canvas.layoutSubtreeIfNeeded()
        let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
        rep.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let png = rep.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
        exit(0)
    }

    if let u = fetchURL {
        GeminiClient().fetch(u) { result in
            if case .success(let r) = result, r.status / 10 == 2 {
                let text = String(decoding: r.body, as: UTF8.self)
                b.renderForSnapshot(lines: Gemtext.parse(text), url: u)
            } else {
                print("fetch failed: \(result)")
            }
            snapshot()
        }
        app.run()
    }
    snapshot()
}

// --- Headless fetch test: --fetch gemini://host/path ------------------------
if let i = CommandLine.arguments.firstIndex(of: "--fetch"),
   CommandLine.arguments.count > i + 1,
   let url = URL(string: CommandLine.arguments[i + 1]) {
    GeminiClient().fetch(url) { result in
        switch result {
        case .failure(let e): print("ERR \(e.localizedDescription)")
        case .success(let r):
            print("STATUS \(r.status) META \(r.meta)")
            print(String(decoding: r.body.prefix(2000), as: UTF8.self))
        }
        exit(0)
    }
    app.run()
}

delegate.newWindow()
app.activate(ignoringOtherApps: true)
app.run()
