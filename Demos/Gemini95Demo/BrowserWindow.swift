import AppKit
import Win95

/// Sunken document well: draws the 2px inset bevel around a scroll view.
private final class W95DocWell: NSView {
    let scroll = NSScrollView()
    override init(frame f: NSRect) {
        super.init(frame: f)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.scrollerStyle = .legacy
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        scroll.frame = bounds.insetBy(dx: 2, dy: 2)
    }
    override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// W95IconButton moved upstream to win95ui — use `W95IconButton(win95Icon:)`.

/// Root content: menu bar on top, tab strip under it, toolbar under that,
/// document well filling the rest. All laid out in flipped coordinates.
private final class BrowserRootView: NSView {
    let menubar = W95MenuBar()
    let tabStrip = W95TabStrip(tabs: [])
    let toolbar = W95FlippedView()
    let well = W95DocWell()

    let backBtn = W95IconButton(win95Icon: "go-previous")
    let fwdBtn = W95IconButton(win95Icon: "go-next")
    let reloadBtn = W95IconButton(win95Icon: "view-refresh")
    let homeBtn = W95IconButton(win95Icon: "go-home")
    let address = W95TextField(frame: .zero)
    let goBtn = W95Button(title: "Go", isDefault: true)

    override init(frame f: NSRect) {
        super.init(frame: f)
        wantsLayer = true
        layer?.backgroundColor = W95.face.cgColor
        addSubview(menubar)
        addSubview(tabStrip)
        addSubview(toolbar)
        addSubview(well)
        for b in [backBtn, fwdBtn, reloadBtn, homeBtn] { toolbar.addSubview(b) }
        toolbar.addSubview(address)
        toolbar.addSubview(goBtn)
        address.placeholderString = "gemini://"
        // 18pt bitmap — fills the bar without being too bold
        address.font = W95Font.font(18)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        menubar.frame = NSRect(x: 0, y: 0, width: w, height: 20)
        tabStrip.frame = NSRect(x: 0, y: 20, width: w, height: 22)
        toolbar.frame = NSRect(x: 0, y: 42, width: w, height: 30)
        well.frame = NSRect(x: 4, y: 74, width: w - 8, height: max(0, h - 78))

        var x: CGFloat = 4
        for b in [backBtn, fwdBtn, reloadBtn, homeBtn] {
            b.frame = NSRect(x: x, y: 3, width: 34, height: 23)
            x += 38
        }
        goBtn.frame = NSRect(x: w - 60, y: 3, width: 52, height: 23)
        address.frame = NSRect(x: x + 2, y: 3, width: w - 60 - x - 8, height: 23)
    }
}

/// Per-tab state: history, current URL, rendered content.
private final class BrowserTab {
    var history: [URL] = []
    var historyIndex = -1
    var currentURL: URL?
    var title: String = "New Tab"
    var content: NSAttributedString?
    var linkRegions: [Gemtext.LinkRegion] = []
}

/// One browser window: chrome + tabs + navigation + gemtext rendering.
@MainActor
final class BrowserWindow: NSObject, NSTextViewDelegate {
    let window: W95Window
    private let root = BrowserRootView()
    private let textView = W95TextView()
    private let client = GeminiClient()

    private var tabs: [BrowserTab] = []
    private var currentTabIndex = 0
    private var currentTab: BrowserTab { tabs[currentTabIndex] }

    private let mono = W95Font.mono(12)
    private let proportional = W95Font.font(12)  // native 12pt bitmap size
    private let headingFont: (CGFloat) -> NSFont = { W95Font.font($0, bold: true) }

    init(cascadeFrom other: NSPoint? = nil) {
        var rect = NSRect(x: 140, y: 160, width: 720, height: 520)
        if let o = other { rect.origin = NSPoint(x: o.x + 24, y: o.y - 24) }
        window = W95Window(title: "Gemini 95", contentRect: rect)
        super.init()

        root.frame = window.clientArea.bounds
        root.autoresizingMask = [.width, .height]
        window.clientArea.addSubview(root)

        // document view
        let tv = textView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        tv.onClick = { [weak self] idx in self?.clickLink(at: idx) ?? false }
        root.well.scroll.documentView = tv

        // menus
        root.menubar.menus = [
            ("File", ["Open Location...", "Save Page As...", "-", "New Tab", "New Window", "Close Tab", "Close"]),
            ("Go", ["Back", "Forward", "Reload", "-", "Home"]),
            ("Help", ["About Gemini 95"]),
        ]
        root.menubar.onSelect = { [weak self] m, i in self?.menu(m, i) }

        // tab strip
        root.tabStrip.target = self
        root.tabStrip.action = #selector(tabSelected)

        // toolbar wiring
        root.backBtn.target = self;  root.backBtn.action = #selector(goBack)
        root.fwdBtn.target = self;   root.fwdBtn.action = #selector(goForward)
        root.reloadBtn.target = self; root.reloadBtn.action = #selector(reload)
        root.homeBtn.target = self;  root.homeBtn.action = #selector(goHome)
        root.goBtn.target = self;    root.goBtn.action = #selector(goPressed)
        root.address.target = self;  root.address.action = #selector(goPressed)

        status("Ready")
        newTab()  // start with one tab showing home
    }

    var cascadePoint: NSPoint { window.frame.origin }

    func show() { window.makeKeyAndOrderFront(nil) }

    private func status(_ s: String) { window.frameView.statusText = s }

    private func setTitle(_ pageTitle: String?) {
        let t = pageTitle.map { "\($0) - Gemini 95" } ?? "Gemini 95"
        window.title = t
        window.frameView.windowTitle = t
    }

    // MARK: tabs

    private func newTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
        updateTabStrip()
        showHome()
    }

    private func closeTab() {
        guard tabs.count > 1 else { window.close(); return }
        tabs.remove(at: currentTabIndex)
        currentTabIndex = min(currentTabIndex, tabs.count - 1)
        updateTabStrip()
        loadTabContent()
    }

    private func updateTabStrip() {
        root.tabStrip.tabs = tabs.map { $0.title }
        root.tabStrip.selected = currentTabIndex
    }

    @objc private func tabSelected() {
        saveTabContent()
        currentTabIndex = root.tabStrip.selected
        loadTabContent()
    }

    /// Save current text view content into the tab before switching away.
    private func saveTabContent() {
        guard tabs.indices.contains(currentTabIndex) else { return }
        currentTab.content = textView.textStorage?.copy() as? NSAttributedString
    }

    /// Restore a tab's content into the text view after switching to it.
    private func loadTabContent() {
        guard tabs.indices.contains(currentTabIndex) else { return }
        let tab = currentTab
        if let content = tab.content {
            textView.textStorage?.setAttributedString(content)
        } else {
            textView.string = ""
        }
        root.address.stringValue = tab.currentURL?.absoluteString ?? ""
        setTitle(tab.title == "New Tab" ? nil : tab.title)
        status(tab.currentURL == nil ? "Ready" : "Done")
    }

    // MARK: navigation

    func navigate(to url: URL, pushHistory: Bool = true, redirectCount: Int = 0) {
        guard let scheme = url.scheme?.lowercased() else {
            showError("Bad address", detail: url.absoluteString)
            return
        }
        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            status("Opened in your real browser. How modern.")
            return
        }
        guard scheme == "gemini" else {
            showError("Unsupported protocol", detail: "Gemini 95 only speaks gemini:// — not \(scheme)://")
            return
        }
        let tab = currentTab
        if pushHistory {
            tab.history = Array(tab.history.prefix(tab.historyIndex + 1))
            tab.history.append(url)
            tab.historyIndex = tab.history.count - 1
        }
        tab.currentURL = url
        root.address.stringValue = url.absoluteString
        status("Connecting to \(url.host ?? "?")…")
        setTitle(nil)

        client.fetch(url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.showError("Connection failed", detail: err.localizedDescription)
                self.status("Done (with regrets)")
            case .success(let resp):
                self.handle(resp, for: url, redirectCount: redirectCount)
            }
        }
    }

    private func handle(_ resp: GeminiResponse, for url: URL, redirectCount: Int) {
        switch resp.status {
        case 10...19:
            promptInput(prompt: resp.meta, sensitive: resp.status == 11, for: url)
            status("Input requested")
        case 20...29:
            renderSuccess(resp, for: url)
        case 30...39:
            guard redirectCount < 5 else {
                showError("Redirect loop", detail: "More than 5 redirects. The capsule is stalling.")
                return
            }
            guard let next = URL(string: resp.meta, relativeTo: url)?.absoluteURL else {
                showError("Bad redirect", detail: resp.meta)
                return
            }
            // replace the history entry we just pushed
            let tab = currentTab
            if tab.historyIndex >= 0 { tab.history[tab.historyIndex] = next }
            navigate(to: next, pushHistory: false, redirectCount: redirectCount + 1)
        case 40...49:
            showError("Temporary failure (\(resp.status))", detail: resp.meta)
            status("Done (with regrets)")
        case 50...59:
            showError("Permanent failure (\(resp.status))", detail: resp.meta)
            status("Done (with regrets)")
        case 60...69:
            showError("Client certificate required (\(resp.status))",
                      detail: resp.meta + "\n\nGemini 95 doesn't carry ID papers yet.")
            status("Done (with regrets)")
        default:
            showError("Unknown status \(resp.status)", detail: resp.meta)
            status("Done (with regrets)")
        }
    }

    private func renderSuccess(_ resp: GeminiResponse, for url: URL) {
        let mime = resp.mime.isEmpty ? "text/gemini" : resp.mime
        if mime == "text/gemini" {
            let text = String(data: resp.body, encoding: .utf8)
                ?? String(decoding: resp.body, as: UTF8.self)
            let lines = Gemtext.parse(text)
            let (attr, links) = Gemtext.render(lines, base: url, mono: mono,
                                               proportional: proportional, headingFont: headingFont)
            currentTab.linkRegions = links
            textView.textStorage?.setAttributedString(attr)
            textView.scrollToBeginningOfDocument(nil)
            let pageTitle = Gemtext.title(of: lines)
            currentTab.title = pageTitle ?? url.host ?? "Gemini"
            updateTabStrip()
            setTitle(pageTitle)
            status("Done — \(resp.body.count) bytes of pure gemtext")
        } else if mime.hasPrefix("text/") {
            let text = String(data: resp.body, encoding: .utf8)
                ?? String(decoding: resp.body, as: UTF8.self)
            let attrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.black]
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
            textView.scrollToBeginningOfDocument(nil)
            setTitle(url.lastPathComponent.isEmpty ? nil : url.lastPathComponent)
            status("Done — \(mime)")
        } else {
            offerDownload(resp, for: url, mime: mime)
        }
    }

    private func offerDownload(_ resp: GeminiResponse, for url: URL, mime: String) {
        status("Binary payload: \(mime)")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "download.bin" : url.lastPathComponent
        panel.message = "The capsule sent a \(mime) file (\(resp.body.count) bytes)."
        panel.beginSheetModal(for: window) { [weak self] rc in
            guard let self else { return }
            if rc == .OK, let dest = panel.url {
                do {
                    try resp.body.write(to: dest)
                    self.status("Saved \(resp.body.count) bytes to \(dest.lastPathComponent)")
                    self.showError("Download complete",
                                   detail: "\(resp.body.count) bytes of \(mime)\nsaved to:\n\(dest.path)")
                } catch {
                    self.showError("Save failed", detail: error.localizedDescription)
                }
            } else {
                self.showError("Download declined",
                               detail: "A \(mime) file (\(resp.body.count) bytes) was offered.\nYou said no. Fair.")
            }
        }
    }

    private func showError(_ title: String, detail: String) {
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: "⚠ " + title + "\n\n", attributes: [
            .font: W95.font(14, bold: true), .foregroundColor: NSColor.black]))
        out.append(NSAttributedString(string: detail + "\n", attributes: [
            .font: proportional, .foregroundColor: NSColor.black]))
        textView.textStorage?.setAttributedString(out)
        setTitle(title)
    }

    // MARK: input prompt (status 1x)

    /// Retains input boxes so they don't get deallocated while the dialog is open.
    private var inputBoxes: [InputBox] = []

    private func promptInput(prompt: String, sensitive: Bool, for url: URL) {
        let w: CGFloat = 320
        let h: CGFloat = 150
        let pw = W95Window(title: "Gemini Input",
                           contentRect: NSRect(x: window.frame.midX - w/2,
                                               y: window.frame.midY - h/2,
                                               width: w, height: h))
        pw.frameView.showsStatusBar = false
        let ca = pw.clientArea
        ca.wantsLayer = true
        ca.layer?.backgroundColor = W95.face.cgColor
        pw.contentView!.layoutSubtreeIfNeeded()

        let label = NSTextField(labelWithString: prompt.isEmpty ? "The capsule asks:" : prompt)
        label.font = W95.font(11)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.frame = NSRect(x: 10, y: 8, width: w - 20, height: 30)
        ca.addSubview(label)

        let field: NSTextField = sensitive ? W95SecureField(frame: .zero) : W95TextField(frame: .zero)
        field.font = W95.font(12)
        field.frame = NSRect(x: 10, y: 42, width: w - 20, height: 24)
        ca.addSubview(field)

        // Client area is narrower than window due to borders — use ca.bounds
        let cw = ca.bounds.width
        let ok = W95Button(title: "OK", isDefault: true)
        ok.frame = NSRect(x: cw - 172, y: 76, width: 80, height: 24)
        let cancel = W95Button(title: "Cancel")
        cancel.frame = NSRect(x: cw - 86, y: 76, width: 80, height: 24)
        ca.addSubview(ok); ca.addSubview(cancel)

        let box = InputBox()
        box.field = field
        box.submit = { [weak self, weak pw] text in
            pw?.close()
            guard let self else { return }
            // Gemini input: append query to URL, replacing any existing query
            var u = url.absoluteString
            if let q = u.firstIndex(of: "?") { u = String(u[..<q]) }
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            if let newURL = URL(string: u + "?" + encoded) {
                self.navigate(to: newURL)
            }
        }
        ok.target = box; ok.action = #selector(InputBox.fire)
        cancel.target = pw; cancel.action = #selector(NSWindow.performClose(_:))
        field.target = box; field.action = #selector(InputBox.fire)

        // Retain the box so it lives as long as the dialog
        inputBoxes.append(box)
        // Clean up when the window closes
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: pw, queue: .main) { [weak self] _ in
            self?.inputBoxes.removeAll { $0 === box }
        }

        pw.makeKeyAndOrderFront(nil)
        pw.makeFirstResponder(field)
    }

    // MARK: menus & buttons

    private func menu(_ m: Int, _ i: Int) {
        switch (m, i) {
        case (0, 0): focusAddress()
        case (0, 1): saveCurrentPage()
        case (0, 3): newTab()
        case (0, 4): _ = AppDelegate.shared?.newWindow(cascadeFrom: cascadePoint)
        case (0, 5): closeTab()
        case (0, 6): window.close()
        case (1, 0): goBack()
        case (1, 1): goForward()
        case (1, 2): reload()
        case (1, 4): goHome()
        case (2, 0): showAbout()
        default: break
        }
    }

    func focusAddress() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(root.address)
    }

    private func saveCurrentPage() {
        guard let url = currentTab.currentURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (url.lastPathComponent.isEmpty ? "index" : url.lastPathComponent) + ".txt"
        panel.beginSheetModal(for: window) { [weak self] rc in
            if rc == .OK, let dest = panel.url {
                try? self?.textView.string.write(to: dest, atomically: true, encoding: .utf8)
            }
        }
    }

    private func showAbout() {
        let text = """
        GEMINI 95

        A small-web browser for the Gemini protocol,
        dressed like it's 1995.

        No JavaScript. No cookies. No tracking.
        Just bevels, teal, and text.
        """
        let attrs: [NSAttributedString.Key: Any] = [.font: proportional, .foregroundColor: NSColor.black]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        setTitle("About")
    }

    private func showHome() {
        let lines: [GemLine] = [
            .heading(level: 1, text: "Gemini 95"),
            .text("Welcome to the small web. Dial-up not included."),
            .text(""),
            .heading(level: 2, text: "Suggested capsules"),
            .link(url: "gemini://geminiprotocol.net/", label: "The Gemini Protocol"),
            .link(url: "gemini://tlgs.one/", label: "TLGS — Totally Legit Gemini Search"),
            .link(url: "gemini://gemini.bortzmeyer.org/", label: "bortzmeyer's capsule"),
            .link(url: "gemini://rawtext.club/", label: "rawtext.club"),
            .link(url: "gemini://midnight.pub/", label: "The Midnight Pub"),
            .text(""),
            .heading(level: 2, text: "How this works"),
            .listItem("Type a gemini:// address up top, hit Go"),
            .listItem("Links are the navy underlined things"),
            .listItem("Everything else is a 4xx error and a shrug"),
            .quote("Powered by trust-on-first-use and nostalgia."),
        ]
        let base = URL(string: "gemini://home/")!
        let (attr, links) = Gemtext.render(lines, base: base, mono: mono,
                                           proportional: proportional, headingFont: headingFont)
        currentTab.linkRegions = links
        currentTab.title = "Home"
        updateTabStrip()
        textView.textStorage?.setAttributedString(attr)
        setTitle("Home")
        status("Ready")
    }

    // MARK: link clicks

    /// Hit-test a character index against stored link regions.
    private func clickLink(at idx: Int) -> Bool {
        for region in currentTab.linkRegions where NSLocationInRange(idx, region.range) {
            navigate(to: region.url)
            return true
        }
        return false
    }

    /// Used by --render to paint a fetched page without full navigation.
    func renderForSnapshot(lines: [GemLine], url: URL) {
        currentTab.currentURL = url
        root.address.stringValue = url.absoluteString
        let (attr, links) = Gemtext.render(lines, base: url, mono: mono,
                                           proportional: proportional, headingFont: headingFont)
        currentTab.linkRegions = links
        textView.textStorage?.setAttributedString(attr)
        let pageTitle = Gemtext.title(of: lines)
        currentTab.title = pageTitle ?? url.host ?? "Gemini"
        updateTabStrip()
        setTitle(pageTitle)
        status("Done")
    }

    // MARK: selectors

    @objc func goBack() {
        let tab = currentTab
        guard tab.historyIndex > 0 else { NSSound.beep(); return }
        tab.historyIndex -= 1
        navigate(to: tab.history[tab.historyIndex], pushHistory: false)
    }
    @objc func goForward() {
        let tab = currentTab
        guard tab.historyIndex < tab.history.count - 1 else { NSSound.beep(); return }
        tab.historyIndex += 1
        navigate(to: tab.history[tab.historyIndex], pushHistory: false)
    }
    @objc func reload() {
        guard let url = currentTab.currentURL else { NSSound.beep(); return }
        navigate(to: url, pushHistory: false)
    }
    @objc func goHome() { showHome() }
    @objc func goPressed() {
        var s = root.address.stringValue.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return }
        if !s.contains("://") { s = "gemini://" + s }
        guard let url = URL(string: s) else { showError("Bad address", detail: s); return }
        navigate(to: url)
    }
}

/// Secure variant of the sunken text field, for status-11 sensitive input.
private final class W95SecureField: NSSecureTextField {
    override init(frame f: NSRect) {
        super.init(frame: f)
        isBezeled = false; drawsBackground = true
        backgroundColor = .white
        font = W95.font(11)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirty: NSRect) {
        super.draw(dirty)
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// Action target for the input prompt: forwards the field's text to `submit`.
@MainActor
private final class InputBox: NSObject {
    weak var field: NSTextField?
    var submit: ((String) -> Void)?
    @objc func fire() { submit?(field?.stringValue ?? "") }
}
