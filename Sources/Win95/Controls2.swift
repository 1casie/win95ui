import AppKit

/// Round radio button — white well, black dot when on. Group by shared `group`.
public final class W95Radio: NSControl {
    public var title = "" { didSet { needsDisplay = true } }
    public var selected = false { didSet { needsDisplay = true } }
    public var group: [W95Radio] = []

    public init(title: String, selected: Bool = false) {
        self.title = title; self.selected = selected
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        let w = title.size(withAttributes: [.font: W95.font(11)]).width
        return NSSize(width: 20 + w, height: 16)
    }

    public override func draw(_ dirty: NSRect) {
        let d: CGFloat = 12
        let r = NSRect(x: 0.5, y: (bounds.height - d) / 2, width: d, height: d)
        // sunken round well
        NSColor.white.setFill()
        NSBezierPath(ovalIn: r).fill()
        W95.shadow.setStroke(); NSBezierPath(ovalIn: r).stroke()
        W95.darkShadow.setStroke()
        NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).stroke()
        if selected {
            NSColor.black.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 4, dy: 4)).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        title.draw(at: NSPoint(x: 19, y: (bounds.height - 14) / 2), withAttributes: attrs)
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        for r in group where r !== self { r.selected = false }
        selected = true
        sendAction(action, to: target)
    }
}

/// Drop-down combo: sunken field + raised arrow button, NSMenu for the list.
public final class W95ComboBox: NSControl {
    public var items: [String] = [] { didSet { needsDisplay = true } }
    public var selectedIndex = 0 { didSet { needsDisplay = true } }
    public var text: String { items.indices.contains(selectedIndex) ? items[selectedIndex] : "" }

    public init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var buttonRect: NSRect {
        NSRect(x: bounds.maxX - bounds.height + 2, y: 2, width: bounds.height - 4, height: bounds.height - 4)
    }

    public override func draw(_ dirty: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        text.draw(in: NSRect(x: 5, y: (bounds.height - 14) / 2, width: buttonRect.minX - 8, height: 14),
                  withAttributes: attrs)
        let br = buttonRect
        W95.face.setFill(); br.fill()
        NSBezierPath.w95Raised(br.insetBy(dx: 0.5, dy: 0.5))
        // down arrow (non-flipped view: +y is up, apex at bottom points down)
        NSColor.black.setFill()
        let a = NSBezierPath()
        let cx = br.midX, cy = br.midY
        a.move(to: NSPoint(x: cx - 4, y: cy + 2)); a.line(to: NSPoint(x: cx + 4, y: cy + 2))
        a.line(to: NSPoint(x: cx, y: cy - 3)); a.close(); a.fill()
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        let menu = NSMenu()
        for (i, item) in items.enumerated() {
            let mi = NSMenuItem(title: item, action: #selector(pick(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = i
            menu.addItem(mi)
        }
        menu.font = W95.font(11)
        // Non-flipped view: bottom edge is minY; anchor the drop-down below the field.
        let p = NSPoint(x: bounds.minX, y: bounds.minY)
        menu.popUp(positioning: nil, at: p, in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        selectedIndex = sender.tag
        sendAction(action, to: target)
    }
}

/// Sunken list box with selection highlight. Click selects, double-click fires action.
public final class W95ListBox: NSControl {
    public var items: [String] = [] { didSet { needsDisplay = true } }
    public var selectedIndex: Int? { didSet { needsDisplay = true } }
    private let rowH: CGFloat = 16

    public init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirty: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        let selAttrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.white]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)).setClip()
        for (i, item) in items.enumerated() {
            let r = NSRect(x: 2, y: 2 + CGFloat(i) * rowH, width: bounds.width - 4, height: rowH)
            if r.minY >= bounds.maxY - 2 { break }
            if i == selectedIndex {
                W95.selection.setFill(); r.fill()
                item.draw(in: r.insetBy(dx: 4, dy: 1), withAttributes: selAttrs)
            } else {
                item.draw(in: r.insetBy(dx: 4, dy: 1), withAttributes: attrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        let p = convert(e.locationInWindow, from: nil)
        guard p.x >= 2, p.x < bounds.maxX - 2, p.y >= 2, p.y < bounds.maxY - 2 else { return }
        let i = Int((p.y - 2) / rowH)
        guard i >= 0, i < items.count else { return }
        selectedIndex = i
        sendAction(action, to: target)
    }
}

/// Chunky blue-block progress bar.
public final class W95ProgressBar: NSView {
    public var value: Double = 0 { didSet { needsDisplay = true } } // 0...1

    public override func draw(_ dirty: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
        let inner = bounds.insetBy(dx: 2, dy: 2)
        let blockW: CGFloat = 10, gap: CGFloat = 2
        let filled = Int((inner.width * CGFloat(max(0, min(1, value)))) / (blockW + gap))
        W95.selection.setFill()
        for i in 0..<filled {
            NSRect(x: inner.minX + CGFloat(i) * (blockW + gap), y: inner.minY,
                   width: blockW, height: inner.height).fill()
        }
    }
}

/// Horizontal slider: sunken channel + raised thumb.
public final class W95Slider: NSControl {
    public var value: Double = 0.5 { didSet { needsDisplay = true } } // 0...1
    private var dragging = false
    private var grabOffset: CGFloat = 0

    private var channel: NSRect {
        NSRect(x: 4, y: bounds.midY - 2, width: bounds.width - 8, height: 4)
    }
    private func thumbRect() -> NSRect {
        let ch = channel
        return NSRect(x: ch.minX + CGFloat(value) * (ch.width - 12), y: bounds.midY - 10,
                      width: 12, height: 20)
    }

    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        NSBezierPath.w95Sunken(channel.insetBy(dx: 0.5, dy: 0.5))
        let t = thumbRect()
        W95.face.setFill(); t.fill()
        NSBezierPath.w95Raised(t.insetBy(dx: 0.5, dy: 0.5))
        // thumb grip line
        W95.shadow.setStroke()
        let g = NSBezierPath(); g.lineWidth = 1
        g.move(to: NSPoint(x: t.midX + 0.5, y: t.minY + 3)); g.line(to: NSPoint(x: t.midX + 0.5, y: t.maxY - 3))
        g.stroke()
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        dragging = true
        let p = convert(e.locationInWindow, from: nil)
        // Grabbing the thumb preserves the grab point; clicking the channel centers there.
        grabOffset = thumbRect().contains(p) ? p.x - thumbRect().midX : 0
        track(e)
    }
    public override func mouseDragged(with e: NSEvent) { if dragging { track(e) } }
    public override func mouseUp(with e: NSEvent) { dragging = false }

    private func track(_ e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let ch = channel
        value = Double(max(0, min(1, (p.x - grabOffset - ch.minX - 6) / (ch.width - 12))))
        sendAction(action, to: target)
    }
}

/// Spin box: sunken field + up/down arrow buttons.
public final class W95Spinner: NSControl {
    public var value = 0 { didSet { needsDisplay = true } }
    public var range: ClosedRange<Int> = 0...99

    private var upRect: NSRect {
        NSRect(x: bounds.maxX - 16, y: bounds.midY, width: 16, height: bounds.height / 2 - 1)
    }
    private var downRect: NSRect {
        NSRect(x: bounds.maxX - 16, y: 1, width: 16, height: bounds.height / 2 - 1)
    }

    public override func draw(_ dirty: NSRect) {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: bounds.width - 16, height: bounds.height).fill()
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        String(value).draw(in: NSRect(x: 5, y: (bounds.height - 14) / 2, width: bounds.width - 24, height: 14),
                           withAttributes: attrs)
        for (r, up) in [(upRect, true), (downRect, false)] {
            W95.face.setFill(); r.fill()
            NSBezierPath.w95Raised(r.insetBy(dx: 0.5, dy: 0.5))
            NSColor.black.setFill()
            let a = NSBezierPath()
            let cx = r.midX, cy = r.midY
            if up {
                // up chevron: base at bottom, apex at top (non-flipped: +y is up)
                a.move(to: NSPoint(x: cx - 3, y: cy - 2)); a.line(to: NSPoint(x: cx + 3, y: cy - 2))
                a.line(to: NSPoint(x: cx, y: cy + 3))
            } else {
                // down chevron: base at top, apex at bottom
                a.move(to: NSPoint(x: cx - 3, y: cy + 2)); a.line(to: NSPoint(x: cx + 3, y: cy + 2))
                a.line(to: NSPoint(x: cx, y: cy - 3))
            }
            a.close(); a.fill()
        }
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        let p = convert(e.locationInWindow, from: nil)
        if upRect.contains(p) { value = min(range.upperBound, value + 1) }
        else if downRect.contains(p) { value = max(range.lowerBound, value - 1) }
        else { return }
        sendAction(action, to: target)
    }
}

/// Tab strip: raised tabs, active tab pops forward. Content area below is caller's.
public final class W95TabStrip: NSControl {
    public var tabs: [String] = [] { didSet { needsDisplay = true } }
    public var selected = 0 { didSet { needsDisplay = true } }

    public init(tabs: [String]) {
        self.tabs = tabs
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    private func tabRect(_ i: Int) -> NSRect {
        var x: CGFloat = 4
        for j in 0..<i {
            x += tabs[j].size(withAttributes: [.font: W95.font(11)]).width + 18
        }
        let w = tabs[i].size(withAttributes: [.font: W95.font(11)]).width + 18
        let h: CGFloat = i == selected ? 22 : 19
        return NSRect(x: x, y: 0, width: w, height: h)
    }

    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        // page outline below tabs
        let page = NSRect(x: 0, y: 20, width: bounds.width, height: bounds.height - 20)
        W95.highlight.setStroke()
        let pp = NSBezierPath(); pp.lineWidth = 1
        pp.move(to: NSPoint(x: page.minX + 0.5, y: page.minY + 0.5))
        pp.line(to: NSPoint(x: page.minX + 0.5, y: page.maxY - 0.5))
        pp.line(to: NSPoint(x: page.maxX - 0.5, y: page.maxY - 0.5))
        pp.line(to: NSPoint(x: page.maxX - 0.5, y: page.minY + 0.5))
        pp.stroke()
        W95.shadow.setStroke()
        let sp = NSBezierPath(); sp.lineWidth = 1
        sp.move(to: NSPoint(x: page.minX + 1.5, y: page.maxY - 1.5))
        sp.line(to: NSPoint(x: page.maxX - 1.5, y: page.maxY - 1.5))
        sp.line(to: NSPoint(x: page.maxX - 1.5, y: page.minY + 1.5))
        sp.stroke()

        // inactive tabs first, then active on top so it overdraws its neighbors
        if tabs.indices.contains(selected) {
            for i in tabs.indices where i != selected { drawTab(i) }
            drawTab(selected)
        } else {
            for i in tabs.indices { drawTab(i) }
        }
    }

    private func drawTab(_ i: Int) {
        let r = tabRect(i)
        let active = i == selected
        W95.face.setFill(); r.fill()
        // raised border, open bottom on active
        W95.highlight.setStroke()
        let p = NSBezierPath(); p.lineWidth = 1
        p.move(to: NSPoint(x: r.minX + 0.5, y: r.maxY))
        p.line(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5))
        p.line(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
        p.stroke()
        W95.shadow.setStroke()
        let s = NSBezierPath(); s.lineWidth = 1
        s.move(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
        s.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY))
        s.stroke()
        if !active {
            W95.shadow.setStroke()
            let b = NSBezierPath(); b.lineWidth = 1
            b.move(to: NSPoint(x: r.minX, y: r.maxY - 0.5)); b.line(to: NSPoint(x: r.maxX, y: r.maxY - 0.5))
            b.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        tabs[i].draw(at: NSPoint(x: r.minX + 9, y: r.minY + 3), withAttributes: attrs)
    }

    public override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        for i in tabs.indices where tabRect(i).contains(p) {
            selected = i
            sendAction(action, to: target)
            return
        }
    }
}

/// A W95 button that draws a pixel-art icon (e.g. Chicago95 PNGs).
/// Icons are loaded from the caller's bundle by name.
public final class W95IconButton: NSControl {
    public let icon: NSImage?
    private var pressed = false { didSet { needsDisplay = true } }

    /// Load an icon from a bundle. `bundle` defaults to `.main` — pass
    /// `Bundle.module` if the icon lives in a SwiftPM resource bundle.
    public init(iconName: String, bundle: Bundle = .main) {
        self.icon = bundle.url(forResource: iconName, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        super.init(frame: .zero)
    }

    /// Load one of the shared Chicago95 nav icons (go-home, go-next,
    /// go-previous, view-refresh) vendored into win95ui itself.
    public init(win95Icon name: String) {
        self.icon = Bundle.module.url(forResource: name, withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirty: NSRect) {
        let b = bounds
        W95.face.setFill(); b.fill()
        NSBezierPath.w95Raised(b.insetBy(dx: 0.5, dy: 0.5), pressed: pressed)
        guard let icon else { return }
        let o: CGFloat = pressed ? 1 : 0
        let size: CGFloat = min(b.width, b.height) - 4
        let r = NSRect(x: (b.width - size) / 2 + o, y: (b.height - size) / 2 + o,
                       width: size, height: size)
        icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        var inside = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp],
                            timeout: Date.distantFuture.timeIntervalSinceNow,
                            mode: .eventTracking) { ev, stop in
            guard let ev else { stop.pointee = true; return }
            inside = self.bounds.contains(self.convert(ev.locationInWindow, from: nil))
            self.pressed = inside
            if ev.type == .leftMouseUp { stop.pointee = true }
        }
        pressed = false
        if inside { sendAction(action, to: target) }
    }
}

/// In-window menu bar: File Edit View Help style. Items pop NSMenus.
public final class W95MenuBar: NSView {
    public var menus: [(title: String, items: [String])] = [] { didSet { needsDisplay = true } }
    public var onSelect: ((_ menu: Int, _ item: Int) -> Void)?
    private var openMenu = -1

    public override var isFlipped: Bool { true }

    private func itemRect(_ i: Int) -> NSRect {
        var x: CGFloat = 4
        for j in 0..<i {
            x += menus[j].title.size(withAttributes: [.font: W95.font(11)]).width + 16
        }
        return NSRect(x: x, y: 1, width: menus[i].title.size(withAttributes: [.font: W95.font(11)]).width + 16,
                      height: bounds.height - 2)
    }

    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        W95.shadow.setStroke()
        let b = NSBezierPath(); b.lineWidth = 1
        b.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5)); b.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        b.stroke()
        for i in menus.indices {
            let r = itemRect(i)
            if i == openMenu {
                W95.selection.setFill(); r.fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: W95.font(11),
                .foregroundColor: i == openMenu ? NSColor.white : NSColor.black]
            menus[i].title.draw(at: NSPoint(x: r.minX + 8, y: r.minY + 2), withAttributes: attrs)
        }
    }

    public override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        for i in menus.indices where itemRect(i).contains(p) {
            openMenu = i; needsDisplay = true
            let menu = NSMenu()
            menu.font = W95.font(11)
            for (j, item) in menus[i].items.enumerated() {
                if item == "-" { menu.addItem(.separator()); continue }
                let mi = NSMenuItem(title: item, action: #selector(pick(_:)), keyEquivalent: "")
                mi.target = self; mi.tag = i * 1000 + j
                menu.addItem(mi)
            }
            let r = itemRect(i)
            menu.popUp(positioning: nil, at: NSPoint(x: r.minX, y: r.maxY), in: self)
            openMenu = -1; needsDisplay = true
            return
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        onSelect?(sender.tag / 1000, sender.tag % 1000)
    }
}
