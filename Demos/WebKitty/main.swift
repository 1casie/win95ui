import AppKit
import Win95

// WebKitty: Hacker News in full Win95 chrome. Ridiculous on purpose.
// Tabs like the Gemini browser: one W95WebView per tab, flipped root view
// laying everything out from its bounds in layout().

// MARK: - click bridge (Win95 controls are final, so target/action goes here)

final class ClickBridge: NSObject, @unchecked Sendable {
    static let shared = ClickBridge()
    private var handlers: [ObjectIdentifier: @MainActor () -> Void] = [:]
    func attach(_ control: NSControl, _ fn: @MainActor @escaping () -> Void) {
        handlers[ObjectIdentifier(control)] = fn
        control.target = self
        control.action = #selector(fire(_:))
    }
    @objc private func fire(_ sender: NSControl) {
        MainActor.assumeIsolated { handlers[ObjectIdentifier(sender)]?() }
    }
}

// MARK: - root view: menubar, tabs, toolbar, progress, current browser

final class WebKittyRootView: NSView {
    let menubar = W95MenuBar()
    let tabStrip = W95TabStrip(tabs: [])
    let toolbar = W95FlippedView()
    let progress = W95ProgressBar()

    let backBtn = W95IconButton(win95Icon: "go-previous")
    let fwdBtn = W95IconButton(win95Icon: "go-next")
    let reloadBtn = W95IconButton(win95Icon: "view-refresh")
    let homeBtn = W95IconButton(win95Icon: "go-home")
    let address = W95TextField(frame: .zero)
    let goBtn = W95Button(title: "Go", isDefault: true)

    /// The visible tab's browser. Swapped on tab switch.
    var content: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let content {
                addSubview(content)
                needsLayout = true
            }
        }
    }

    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        layer?.backgroundColor = W95.face.cgColor
        addSubview(menubar)
        addSubview(tabStrip)
        addSubview(toolbar)
        addSubview(progress)
        for b in [backBtn, fwdBtn, reloadBtn, homeBtn] { toolbar.addSubview(b) }
        toolbar.addSubview(address)
        toolbar.addSubview(goBtn)
        address.placeholderString = "https://"
        // 18pt bitmap — fills the bar without being too bold
        address.font = W95.font(18)
        progress.value = 0
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        menubar.frame = NSRect(x: 0, y: 0, width: w, height: 20)
        tabStrip.frame = NSRect(x: 0, y: 20, width: w, height: 22)
        toolbar.frame = NSRect(x: 0, y: 42, width: w, height: 30)
        progress.frame = NSRect(x: 8, y: 74, width: w - 16, height: 12)
        content?.frame = NSRect(x: 4, y: 90, width: w - 8, height: max(0, h - 94))

        var x: CGFloat = 4
        for b in [backBtn, fwdBtn, reloadBtn, homeBtn] {
            b.frame = NSRect(x: x, y: 3, width: 34, height: 23)
            x += 38
        }
        goBtn.frame = NSRect(x: w - 60, y: 3, width: 52, height: 23)
        address.frame = NSRect(x: x + 2, y: 3, width: w - 60 - x - 8, height: 23)
    }
}

// MARK: - controller: window, tabs, navigation

@MainActor
final class WebKitty: NSObject {
    let home = URL(string: "https://news.ycombinator.com")!
    let window: W95Window
    let root = WebKittyRootView()

    var tabs: [W95WebView] = []
    var titles: [String] = []
    var selected = 0
    var current: W95WebView { tabs[selected] }

    override init() {
        let screen = NSScreen.main!.frame
        window = W95Window(title: "WebKitty",
                           contentRect: NSRect(x: screen.midX - 460, y: screen.midY - 60,
                                               width: 920, height: 660))
        super.init()
        root.frame = window.clientArea.bounds
        root.autoresizingMask = [.width, .height]
        window.clientArea.addSubview(root)

        root.menubar.menus = [("File", ["New Tab", "Close Tab", "-", "Close Window"]),
                              ("View", ["Back", "Forward", "Reload", "-", "Home"]),
                              ("Help", ["About WebKitty"])]
        root.menubar.onSelect = { [weak self] m, i in self?.menu(m, i) }

        root.tabStrip.target = self
        root.tabStrip.action = #selector(tabSelected)

        let bridge = ClickBridge.shared
        bridge.attach(root.backBtn) { [weak self] in self?.goBack() }
        bridge.attach(root.fwdBtn) { [weak self] in self?.goForward() }
        bridge.attach(root.reloadBtn) { [weak self] in self?.current.web.reload() }
        bridge.attach(root.homeBtn) { [weak self] in self?.current.goHome() }
        bridge.attach(root.goBtn) { [weak self] in
            if let s = self?.root.address.stringValue { self?.go(s) }
        }
        root.address.delegate = self
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    /// New tab. Pass a URL to load it, or nothing for a blank tab
    /// (caller loads home explicitly when it wants the start page).
    func newTab(url: URL? = nil) {
        let b = W95WebView(home: home)
        b.onProgress = { [weak self, weak b] v in
            guard let self, let b, b === self.current else { return }
            self.root.progress.value = v
        }
        b.onTitle = { [weak self, weak b] t in
            guard let self, let b, b === self.current,
                  let t, !t.isEmpty else { return }
            self.titles[self.selected] = t
            self.syncStrip()
            self.showTitle(t)
        }
        b.onState = { [weak self, weak b] in
            guard let self, let b, b === self.current else { return }
            self.syncChrome()
        }
        b.onStatus = { [weak self] s in self?.status(s) }
        tabs.append(b)
        titles.append("New Tab")
        selected = tabs.count - 1
        syncStrip()
        root.content = b
        syncChrome()
        showTitle(nil)
        if let u = url { b.load(url: u) }
    }

    func closeTab() {
        guard tabs.count > 1 else { window.close(); return }
        tabs.remove(at: selected)
        titles.remove(at: selected)
        selected = min(selected, tabs.count - 1)
        syncStrip()
        root.content = tabs[selected]
        syncChrome()
        showTitle(titles[selected] == "New Tab" ? nil : titles[selected])
    }

    @objc func tabSelected() {
        selected = root.tabStrip.selected
        root.content = tabs[selected]
        syncChrome()
        showTitle(titles[selected] == "New Tab" ? nil : titles[selected])
    }

    func go(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t) else {
            status("Nope, that is not a URL.")
            return
        }
        current.load(url: u)
    }

    func goBack() { if current.web.canGoBack { current.web.goBack() } }
    func goForward() { if current.web.canGoForward { current.web.goForward() } }

    // MARK: - chrome sync

    func syncStrip() {
        root.tabStrip.tabs = titles
        root.tabStrip.selected = selected
    }

    func syncChrome() {
        let w = current.web
        root.backBtn.isEnabled = w.canGoBack
        root.fwdBtn.isEnabled = w.canGoForward
        if let u = w.url { root.address.stringValue = u.absoluteString }
    }

    func showTitle(_ t: String?) {
        let full = t.map { "\($0) - WebKitty" } ?? "WebKitty"
        window.title = full
        window.frameView.windowTitle = full
    }

    func status(_ s: String) { window.frameView.statusText = s }

    func menu(_ m: Int, _ i: Int) {
        switch (m, i) {
        case (0, 0): newTab()
        case (0, 1): closeTab()
        case (0, 3): window.close()
        case (1, 0): goBack()
        case (1, 1): goForward()
        case (1, 2): current.web.reload()
        case (1, 4): current.goHome()
        case (2, 0): status("WebKitty: Hacker News, but it is 1995.")
        default: break
        }
    }
}

// Return key in the address field goes.
extension WebKitty: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            go(root.address.stringValue)
            return true
        }
        return false
    }
}

// MARK: - launch

W95ThemeManager.shared.startIfNeeded()

let app = NSApplication.shared
app.setActivationPolicy(.regular)
W95Menus.installMainMenu(appName: "WebKitty")

let kitty = WebKitty()

// --- Render mode: load (optionally a URL), wait until idle, snapshot ------
if CommandLine.arguments.contains("--render") {
    var startURL: URL? = kitty.home
    var outArg: String?
    if let i = CommandLine.arguments.firstIndex(of: "--render") {
        for arg in CommandLine.arguments[(i + 1)...] {
            if arg.hasPrefix("http://") || arg.hasPrefix("https://") { startURL = URL(string: arg) }
            else if arg.hasPrefix("--") { startURL = nil } // e.g. --no-load: chrome only
            else { outArg = arg }
        }
    }
    let out = outArg ?? "/tmp/webkitty.png"
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = W95.desktopTeal.cgColor

    func snapshot() -> Never {
        kitty.window.contentView!.layoutSubtreeIfNeeded()
        kitty.window.contentView!.frame = NSRect(origin: NSPoint(x: 40, y: 20),
                                                 size: kitty.window.contentView!.frame.size)
        canvas.addSubview(kitty.window.contentView!)
        canvas.layoutSubtreeIfNeeded()
        // Let the web paint settle before grabbing pixels.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            rep.size = canvas.bounds.size
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try! png.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
            exit(0)
        }
        app.run()
        fatalError("unreachable")
    }

    kitty.newTab(url: startURL)
    if startURL != nil {
        // Wait until the page settles (or 25s, then shoot anyway).
        let deadline = Date().addingTimeInterval(25)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
            if !kitty.current.web.isLoading || Date() >= deadline {
                t.invalidate()
                snapshot()
            }
        }
    } else {
        snapshot()
    }
}

// --- Probe mode: print geometry facts, no pixels -------------------------
if CommandLine.arguments.contains("--probe") {
    var startURL: URL? = kitty.home
    if let i = CommandLine.arguments.firstIndex(of: "--probe"),
       CommandLine.arguments.count > i + 1,
       let u = URL(string: CommandLine.arguments[i + 1]) { startURL = u }
    kitty.newTab(url: startURL)
    let deadline = Date().addingTimeInterval(25)
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { t in
        if !kitty.current.web.isLoading || Date() >= deadline {
            t.invalidate()
            kitty.window.contentView!.layoutSubtreeIfNeeded()
            let b = kitty.current
            let sv = b.web.enclosingScrollView
            print("window=\(kitty.window.frame)")
            print("root=\(kitty.root.frame)")
            print("browser=\(b.frame)")
            print("web=\(b.web.frame)")
            print("scrollView=\(String(describing: sv)) hasVScroller=\(String(describing: sv?.hasVerticalScroller)) style=\(String(describing: sv?.scrollerStyle))")
            b.web.evaluateJavaScript(
                "JSON.stringify({w: window.innerWidth, h: window.innerHeight, url: location.href})"
            ) { result, err in
                print("js=\(String(describing: result)) err=\(String(describing: err))")
                exit(0)
            }
        }
    }
    app.run()
}

kitty.newTab()
kitty.current.goHome()
kitty.root.backBtn.isEnabled = false
kitty.root.fwdBtn.isEnabled = false
kitty.show()
app.activate(ignoringOtherApps: true)
app.run()
