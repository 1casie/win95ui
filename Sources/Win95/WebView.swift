import AppKit
import WebKit

/// WKWebView dropped into Win95 chrome. Fills its superview and reports
/// progress, title, nav state and status text so plain W95 widgets
/// (buttons, progress bar, status bar) can dress it up.
public final class W95WebView: NSView, WKNavigationDelegate {
    public let web: WKWebView
    public var home: URL

    /// 0...1 while loading.
    public var onProgress: ((Double) -> Void)?
    public var onTitle: ((String?) -> Void)?
    /// Back/forward availability or URL changed.
    public var onState: (() -> Void)?
    /// Human line for the status bar: Loading..., Done, errors.
    public var onStatus: ((String) -> Void)?

    private var observations: [NSKeyValueObservation] = []

    public init(home: URL) {
        self.home = home
        let config = WKWebViewConfiguration()
        self.web = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        addSubview(web)
        observations = [
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] w, _ in
                self?.onProgress?(w.estimatedProgress)
            },
            web.observe(\.title, options: [.new]) { [weak self] w, _ in
                self?.onTitle?(w.title)
            },
            web.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                self?.onState?()
            },
            web.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                self?.onState?()
            },
            web.observe(\.url, options: [.new]) { [weak self] _, _ in
                self?.onState?()
            },
        ]
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        web.frame = bounds
        styleScrollers()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        styleScrollers()
    }

    /// Classic always-visible scrollbars, like the Gemini doc well.
    /// The scroll view is created lazily, so this no-ops until it exists.
    private func styleScrollers() {
        guard let sv = web.enclosingScrollView else { return }
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = false
        sv.scrollerStyle = .legacy
    }

    public func load(url: URL) {
        onStatus?("Loading...")
        onProgress?(0)
        web.load(URLRequest(url: url))
    }

    public func goHome() { load(url: home) }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onProgress?(1)
        onStatus?("Done")
        onState?()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onStatus?("Error: \(error.localizedDescription)")
        onState?()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        // Aborted loads (link clicked twice in a row, etc.) are noise.
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        onStatus?("Error: \(error.localizedDescription)")
        onState?()
    }
}
