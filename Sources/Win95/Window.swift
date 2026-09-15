import AppKit

/// A Cocoa window wearing full Windows 95 chrome: raised border, gradient
/// title bar, caption buttons, status bar, and a resize grip.
public final class W95Window: NSWindow {
    public let frameView = W95FrameView()

    public init(title: String, contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
        self.title = title
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        // Borderless windows crash in _NSWindowTransformAnimation dealloc if
        // released while the close animation is still running. Keep it alive.
        isReleasedWhenClosed = false
        contentView = frameView
        frameView.windowTitle = title
        minSize = NSSize(width: 160, height: 80)

        // repaint chrome when key status flips so the title bar follows focus
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: self, queue: .main) { [weak self] _ in
            self?.frameView.needsDisplay = true
        }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            self?.frameView.needsDisplay = true
        }
    }

    /// The view you put your controls in. Laid out inside the chrome.
    /// Flipped: y=0 is the top, like a sane coordinate system.
    public var clientArea: W95FlippedView { frameView.clientArea }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}

/// Top-left-origin container view.
public final class W95FlippedView: NSView {
    public override var isFlipped: Bool { true }
}


/// Draws the chrome and routes mouse events for drag/resize/caption buttons.
public final class W95FrameView: NSView {
    public var windowTitle = "Untitled" { didSet { needsDisplay = true } }
    public var showsStatusBar = true { didSet { needsLayout = true; layout() } }
    public var statusText: String {
        get { statusBar.text }
        set { statusBar.text = newValue }
    }

    public let clientArea = W95FlippedView()
    private let statusBar = W95StatusBar()
    private let border: CGFloat = 4
    private let titleH: CGFloat = 20
    private let statusH: CGFloat = 20
    private let capSize: CGFloat = 16
    private let grip: CGFloat = 18

    private enum Caption { case close, max, min }
    private var restoreFrame: NSRect?
    private var pressedCaption: Caption?

    public override init(frame f: NSRect) {
        super.init(frame: f)
        addSubview(clientArea)
        addSubview(statusBar)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let inner = NSRect(x: border, y: border + titleH,
                           width: bounds.width - border * 2,
                           height: bounds.height - border * 2 - titleH - (showsStatusBar ? statusH : 0))
        clientArea.frame = inner
        statusBar.frame = NSRect(x: border, y: inner.maxY,
                                 width: inner.width, height: statusH)
        statusBar.isHidden = !showsStatusBar
    }

    private func captionRect(_ c: Caption) -> NSRect {
        // Chicago95: min+max adjacent, close separated by a 2px gap.
        let top = border + 2, h = capSize
        switch c {
        case .close: return NSRect(x: bounds.maxX - border - 2 - h, y: top, width: h, height: h)
        case .max:   return NSRect(x: bounds.maxX - border - 4 - h * 2, y: top, width: h, height: h)
        case .min:   return NSRect(x: bounds.maxX - border - 4 - h * 3, y: top, width: h, height: h)
        }
    }

    private func captionAt(_ p: NSPoint) -> Caption? {
        for c in [Caption.close, .max, .min] where captionRect(c).contains(p) { return c }
        return nil
    }

    public override func draw(_ dirty: NSRect) {
        let b = bounds
        // outer raised border
        W95.face.setFill(); b.fill()
        NSBezierPath.w95Raised(b.insetBy(dx: 0.5, dy: 0.5))
        // title bar — flat color, per Chicago95 (gradient is a Win98 affectation)
        let tb = NSRect(x: border, y: border, width: b.width - border * 2, height: titleH)
        let active = window?.isKeyWindow ?? true
        (active ? W95.titleActive : W95.titleInactive).setFill()
        tb.fill()

        // title text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: W95.font(11, bold: true),
            .foregroundColor: active ? W95.titleTextActive : W95.titleTextInactive,
        ]
        let titleRect = NSRect(x: tb.minX + 4, y: tb.minY + 2, width: tb.width - 80, height: titleH - 3)
        windowTitle.draw(in: titleRect, withAttributes: attrs)

        // caption buttons
        for c in [Caption.min, .max, .close] {
            let r = captionRect(c)
            let pressed = pressedCaption == c
            W95.face.setFill(); r.fill()
            NSBezierPath.w95Raised(r, pressed: pressed)
            drawCaptionGlyph(c, in: r.insetBy(dx: pressed ? 0 : 0, dy: 0), pressed: pressed)
        }

        // client area sunken edge
        let ca = clientArea.frame
        NSBezierPath.w95Sunken(ca.insetBy(dx: -1, dy: -1))

        // resize grip (bottom-right diagonal hatch)
        if showsStatusBar {
            let g = NSRect(x: b.maxX - border - grip, y: b.maxY - border - grip, width: grip, height: grip)
            W95.shadow.setStroke()
            for i in stride(from: 4, through: Int(grip - 2), by: 4) {
                let p = NSBezierPath(); p.lineWidth = 1
                p.move(to: NSPoint(x: g.maxX - CGFloat(i), y: g.maxY - 0.5))
                p.line(to: NSPoint(x: g.maxX - 0.5, y: g.maxY - CGFloat(i)))
                p.stroke()
            }
        }
    }

    private func drawCaptionGlyph(_ c: Caption, in r: NSRect, pressed: Bool) {
        let o: CGFloat = pressed ? 1 : 0
        let g = r.insetBy(dx: 4, dy: 4).offsetBy(dx: o, dy: o)
        let p = NSBezierPath(); p.lineWidth = 1.4
        NSColor.black.setStroke()
        switch c {
        case .min:
            p.move(to: NSPoint(x: g.minX, y: g.maxY - 1)); p.line(to: NSPoint(x: g.maxX, y: g.maxY - 1))
        case .max:
            p.appendRect(g)
            p.move(to: NSPoint(x: g.minX, y: g.minY + 1.5)); p.line(to: NSPoint(x: g.maxX, y: g.minY + 1.5))
        case .close:
            p.move(to: g.origin); p.line(to: NSPoint(x: g.maxX, y: g.maxY))
            p.move(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.minX, y: g.maxY))
        }
        p.stroke()
    }

    // MARK: mouse

    public override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if let c = captionAt(p) {
            pressedCaption = c; needsDisplay = true
            trackCaption(c, e)
            return
        }
        // resize grip
        let gripRect = NSRect(x: bounds.maxX - border - grip, y: bounds.maxY - border - grip, width: grip, height: grip)
        if showsStatusBar, gripRect.contains(p) { trackResize(e); return }
        // title bar drag
        let tb = NSRect(x: border, y: border, width: bounds.width - border * 2, height: titleH)
        if tb.contains(p) { restoreFrame = nil; window?.performDrag(with: e); return }
        super.mouseDown(with: e)
    }

    private func trackCaption(_ c: Caption, _ e: NSEvent) {
        guard let w = window else { pressedCaption = nil; needsDisplay = true; return }
        var inside = true
        w.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: Date.distantFuture.timeIntervalSinceNow,
                      mode: .eventTracking) { ev, stop in
            guard let ev else { stop.pointee = true; return }
            let p = self.convert(ev.locationInWindow, from: nil)
            let nowInside = self.captionRect(c).contains(p)
            if nowInside != inside {
                inside = nowInside
                self.pressedCaption = nowInside ? c : nil
                self.needsDisplay = true
            }
            if ev.type == .leftMouseUp { stop.pointee = true }
        }
        pressedCaption = nil; needsDisplay = true
        // Window may have been closed mid-drag (e.g. ⌘W); never act on a closed window.
        guard inside, w.isVisible else { return }
        switch c {
        case .close: w.close()
        case .min:   w.miniaturize(nil)
        case .max:   toggleZoom(w)
        }
    }

    /// Windows-style maximize/restore. NSWindow.zoom has no sane standard frame
    /// for a borderless window, so toggle against the screen's visible frame.
    private func toggleZoom(_ w: NSWindow) {
        if let r = restoreFrame {
            restoreFrame = nil
            w.setFrame(r, display: true)
        } else if let s = w.screen ?? NSScreen.main {
            restoreFrame = w.frame
            w.setFrame(s.visibleFrame, display: true)
        }
    }

    private func trackResize(_ e: NSEvent) {
        guard let w = window else { return }
        // A manual resize un-maximizes: drop the stale restore frame.
        restoreFrame = nil
        let start = w.frame
        let startMouse = NSEvent.mouseLocation
        w.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: Date.distantFuture.timeIntervalSinceNow,
                      mode: .eventTracking) { ev, stop in
            guard let ev, w.isVisible else { stop.pointee = true; return }
            if ev.type == .leftMouseUp { stop.pointee = true; return }
            let m = NSEvent.mouseLocation
            var f = start
            f.size.width = max(w.minSize.width, start.width + (m.x - startMouse.x))
            let newHeight = max(w.minSize.height, start.height - (m.y - startMouse.y))
            f.origin.y = start.origin.y + (start.height - newHeight)
            f.size.height = newHeight
            w.setFrame(f, display: true)
        }
    }
}

/// Sunken status bar with a couple of panels, like the bottom of a real 95 app.
public final class W95StatusBar: NSView {
    public var text = "Ready" { didSet { needsDisplay = true } }
    public override var isFlipped: Bool { true }
    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        let p1 = NSRect(x: 2, y: 2, width: bounds.width * 0.6, height: bounds.height - 4)
        let p2 = NSRect(x: p1.maxX + 3, y: 2, width: bounds.width - p1.maxX - 5, height: bounds.height - 4)
        NSBezierPath.w95ThinSunken(p1); NSBezierPath.w95ThinSunken(p2)
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(10), .foregroundColor: NSColor.black]
        text.draw(in: p1.insetBy(dx: 5, dy: 2), withAttributes: attrs)
        "NUM".draw(in: p2.insetBy(dx: 5, dy: 2), withAttributes: attrs)
    }
}
