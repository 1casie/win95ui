import AppKit
import Win95

/// Minimal Gemini95 demo — shows off W95Window, W95TabStrip, W95IconButton,
/// W95TextField, and the vendored R95/Fixedsys fonts. No actual Gemini client;
/// this is just the chrome.

@MainActor
final class DemoWindow: NSObject {
    let window: W95Window
    private let root = NSView()
    private let tabStrip = W95TabStrip(tabs: ["Home", "gemini://example.com"])
    private let address = W95TextField(frame: .zero)
    private let textView = NSTextView()

    override init() {
        window = W95Window(title: "Gemini 95 Demo", contentRect: NSRect(x: 200, y: 200, width: 640, height: 480))
        super.init()

        root.frame = window.clientArea.bounds
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = W95.face.cgColor
        window.clientArea.addSubview(root)

        // tab strip
        tabStrip.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: 22)
        tabStrip.autoresizingMask = [.width]
        root.addSubview(tabStrip)

        // toolbar
        let toolbar = NSView(frame: NSRect(x: 0, y: 22, width: root.bounds.width, height: 30))
        toolbar.autoresizingMask = [.width]
        root.addSubview(toolbar)

        var x: CGFloat = 4
        for icon in ["go-previous", "go-next", "view-refresh", "go-home"] {
            let b = W95IconButton(iconName: icon, bundle: .module)
            b.frame = NSRect(x: x, y: 3, width: 34, height: 23)
            toolbar.addSubview(b)
            x += 38
        }
        address.frame = NSRect(x: x + 2, y: 3, width: toolbar.bounds.width - x - 60, height: 23)
        address.autoresizingMask = [.width]
        address.font = W95.font(18)
        address.placeholderString = "gemini://"
        toolbar.addSubview(address)

        let go = W95Button(title: "Go", isDefault: true)
        go.frame = NSRect(x: toolbar.bounds.width - 56, y: 3, width: 52, height: 23)
        go.autoresizingMask = [.minXMargin]
        toolbar.addSubview(go)

        // document area
        let scroll = NSScrollView(frame: NSRect(x: 4, y: 54, width: root.bounds.width - 8, height: root.bounds.height - 58))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        root.addSubview(scroll)

        textView.isEditable = false
        textView.font = W95.font(12)
        textView.string = """
        Gemini 95 Demo

        This is a demo of the Win95 UI library with vendored fonts.

        • R95 Sans Serif — real MS Sans Serif bitmaps
        • BigBlueTerm437 — monospace for ASCII art
        • GNU Unifont — cascade for non-Latin glyphs
        • Chicago95 icons — pixel-perfect toolbar buttons

        The tab strip above shows W95TabStrip. The address field uses
        W95TextField with an 18pt bitmap font. Everything is drawn with
        font smoothing disabled for that authentic 1995 crunch.
        """
        scroll.documentView = textView

        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var demo: DemoWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        W95Menus.installMainMenu(appName: "Gemini 95 Demo")
        demo = DemoWindow()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
