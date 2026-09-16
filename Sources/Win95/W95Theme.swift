import AppKit

// MARK: - hex helpers

extension NSColor {
    /// #RRGGBB, clamped to opaque sRGB.
    public var w95Hex: String {
        let c = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public convenience init(w95Hex hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        self.init(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - theme model

/// File-backed color scheme. Stored as JSON at the dotfile path
/// (see W95ThemeManager.themeFileURL). Hex strings so it stays
/// hand-editable.
public struct W95Theme: Codable, Equatable, Sendable {
    public var name: String
    public var face: String
    public var highlight: String
    public var light: String
    public var shadow: String
    public var darkShadow: String
    public var titleActive: String
    public var titleInactive: String
    public var titleTextActive: String
    public var titleTextInactive: String
    public var desktopTeal: String
    public var selection: String
    public var tooltipBG: String
    public var link: String

    public static let windows95 = W95Theme(
        name: "Windows 95",
        face: "#C0C0C0", highlight: "#FFFFFF", light: "#DFDFDF",
        shadow: "#808080", darkShadow: "#000000",
        titleActive: "#000080", titleInactive: "#808080",
        titleTextActive: "#FFFFFF", titleTextInactive: "#C0C0C0",
        desktopTeal: "#008080", selection: "#000080",
        tooltipBG: "#FFFFE1", link: "#000080"
    )

    public static let presets: [W95Theme] = [
        .windows95,
        W95Theme(
            name: "Hot Dog Stand",
            face: "#C0C0C0", highlight: "#FFFFFF", light: "#DFDFDF",
            shadow: "#808080", darkShadow: "#000000",
            titleActive: "#FF0000", titleInactive: "#808080",
            titleTextActive: "#FFFF00", titleTextInactive: "#C0C0C0",
            desktopTeal: "#FF0000", selection: "#FF0000",
            tooltipBG: "#FFFFE1", link: "#000080"
        ),
        W95Theme(
            name: "Teal",
            face: "#C0C0C0", highlight: "#FFFFFF", light: "#DFDFDF",
            shadow: "#808080", darkShadow: "#000000",
            titleActive: "#008080", titleInactive: "#808080",
            titleTextActive: "#FFFFFF", titleTextInactive: "#C0C0C0",
            desktopTeal: "#004040", selection: "#008080",
            tooltipBG: "#FFFFE1", link: "#008080"
        ),
        W95Theme(
            name: "Plum",
            face: "#D8CCE0", highlight: "#FFFFFF", light: "#EDE6F2",
            shadow: "#8A7A96", darkShadow: "#2A2230",
            titleActive: "#4B2A5B", titleInactive: "#8A7A96",
            titleTextActive: "#FFFFFF", titleTextInactive: "#EDE6F2",
            desktopTeal: "#3A2A44", selection: "#4B2A5B",
            tooltipBG: "#FFFFE1", link: "#4B2A5B"
        ),
        W95Theme(
            name: "Olive",
            face: "#C8C4A8", highlight: "#FFFFFF", light: "#E4E0C8",
            shadow: "#84805C", darkShadow: "#202010",
            titleActive: "#4C4C00", titleInactive: "#84805C",
            titleTextActive: "#FFFFFF", titleTextInactive: "#E4E0C8",
            desktopTeal: "#404000", selection: "#4C4C00",
            tooltipBG: "#FFFFE1", link: "#4C4C00"
        ),
    ]
}

public extension Notification.Name {
    static let w95ThemeChanged = Notification.Name("com.win95ui.themeChanged")
}

// MARK: - store

/// Loads the theme from disk, writes the default when missing, and keeps
/// every linked app in sync via file watching + a distributed notification.
/// Thread-safe; UI work hops to main.
public final class W95ThemeManager: @unchecked Sendable {
    public static let shared = W95ThemeManager()

    public static let distributedName = Notification.Name("com.win95ui.themeChanged")

    public static var themeFileURL: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("win95ui/theme.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/win95ui/theme.json")
    }

    private let lock = NSLock()
    private var _current: W95Theme = .windows95
    private var started = false
    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFD: CInt = -1

    public var current: W95Theme {
        get { lock.withLock { _current } }
        set {
            lock.withLock { _current = newValue }
            DispatchQueue.main.async { self.redrawAll() }
            NotificationCenter.default.post(name: .w95ThemeChanged, object: nil)
        }
    }

    public var themeFilePath: String { Self.themeFileURL.path }

    /// Idempotent. Safe from any thread. First call loads (or auto-gens)
    /// the dotfile and starts watching it.
    public func startIfNeeded() {
        let shouldStart: Bool = lock.withLock {
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }
        loadFromDisk()
        DispatchQueue.main.async { self.startObservers() }
    }

    public func reload() {
        // No time-based debounce: an atomic save fires a create event and a
        // rename event back to back, and dropping the second one drops the
        // actual update. Instead, skip work when nothing really changed.
        // (Dir watcher + distributed note both landing is harmless then.)
        let old = current
        loadFromDisk()
        guard current != old else { return }
        DispatchQueue.main.async { self.redrawAll() }
        NotificationCenter.default.post(name: .w95ThemeChanged, object: nil)
    }

    @discardableResult
    public func save(_ theme: W95Theme) -> Bool {
        let url = Self.themeFileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(theme)
            // Pretty-print for hand editing, sorted keys for clean diffs.
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try pretty.write(to: url, options: .atomic)
            } else {
                try data.write(to: url, options: .atomic)
            }
            lock.withLock { _current = theme }
            DistributedNotificationCenter.default().postNotificationName(
                Self.distributedName, object: nil, userInfo: nil, deliverImmediately: true)
            DispatchQueue.main.async { self.redrawAll() }
            NotificationCenter.default.post(name: .w95ThemeChanged, object: nil)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func resetToDefault() -> Bool { save(.windows95) }

    // MARK: - internals

    private func loadFromDisk() {
        let url = Self.themeFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            // No dotfile yet: auto-gen the stock 95 look so editors
            // and hand edits start from something sane.
            _ = save(.windows95)
            return
        }
        guard let data = try? Data(contentsOf: url),
              let theme = try? JSONDecoder().decode(W95Theme.self, from: data) else {
            return // corrupt file: keep running with whatever we have
        }
        lock.withLock { _current = theme }
    }

    @MainActor
    private func startObservers() {
        // Another process saved (ControlTheme): reload right away.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(distributedChanged(_:)),
            name: Self.distributedName, object: nil)

        // Hand edits to the dotfile: watch the parent dir.
        let dir = Self.themeFileURL.deletingLastPathComponent().path
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        dirFD = open(dir, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 { close(fd) }
            self?.dirFD = -1
        }
        source.resume()
        dirSource = source
    }

    @objc private func distributedChanged(_ note: Notification) { reload() }

    @MainActor
    private func redrawAll() {
        for window in NSApp.windows {
            window.contentView?.w95MarkDirty()
        }
    }
}

private extension NSView {
    func w95MarkDirty() {
        needsDisplay = true
        setNeedsDisplay(bounds)
        for sub in subviews { sub.w95MarkDirty() }
    }
}
