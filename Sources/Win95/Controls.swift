import AppKit

/// Chunky beveled button. Default buttons get the extra black outline.
public final class W95Button: NSControl {
    public var title = "Button" { didSet { needsDisplay = true } }
    public var isDefault = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    public init(title: String, isDefault: Bool = false) {
        self.title = title
        self.isDefault = isDefault
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        let w = title.size(withAttributes: [.font: W95.font(11)]).width
        return NSSize(width: max(64, w + 24), height: 23)
    }

    public override func draw(_ dirty: NSRect) {
        let b = bounds
        if isDefault {
            NSColor.black.setFill(); b.fill()
        }
        let face = isDefault ? b.insetBy(dx: 1, dy: 1) : b
        W95.face.setFill(); face.fill()
        NSBezierPath.w95Raised(face.insetBy(dx: 0.5, dy: 0.5), pressed: pressed)
        let s = title.size(withAttributes: [.font: W95.font(11)])
        let o: CGFloat = pressed ? 1 : 0
        let textRect = NSRect(x: (b.width - s.width) / 2 + o, y: (b.height - s.height) / 2 + o,
                              width: s.width, height: s.height)
        if isEnabled {
            title.draw(in: textRect, withAttributes: [.font: W95.font(11), .foregroundColor: NSColor.black])
        } else {
            // engraved disabled text, per Chicago95
            NSAttributedString.w95DrawDisabled(title, in: textRect)
        }
        if isDefault && !pressed {
            // focus dotted rect
            let fr = face.insetBy(dx: 4, dy: 4)
            let p = NSBezierPath(); p.lineWidth = 1
            p.setLineDash([1, 1], count: 2, phase: 0)
            NSColor.black.setStroke(); p.appendRect(fr); p.stroke()
        }
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        var inside = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: Date.distantFuture.timeIntervalSinceNow,
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

/// Square checkbox with an X mark — the real 95 style, not a checkmark.
public final class W95CheckBox: NSControl {
    public var title = "" { didSet { needsDisplay = true } }
    public var checked = false { didSet { needsDisplay = true } }

    public init(title: String, checked: Bool = false) {
        self.title = title; self.checked = checked
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        let w = title.size(withAttributes: [.font: W95.font(11)]).width
        return NSSize(width: 20 + w, height: 16)
    }

    public override func draw(_ dirty: NSRect) {
        let box = NSRect(x: 0, y: (bounds.height - 13) / 2, width: 13, height: 13)
        NSColor.white.setFill(); box.fill()
        NSBezierPath.w95Sunken(box.insetBy(dx: 0.5, dy: 0.5))
        if checked {
            let p = NSBezierPath(); p.lineWidth = 1.6
            NSColor.black.setStroke()
            let g = box.insetBy(dx: 3, dy: 3)
            p.move(to: g.origin); p.line(to: NSPoint(x: g.maxX, y: g.maxY))
            p.move(to: NSPoint(x: g.maxX, y: g.minY)); p.line(to: NSPoint(x: g.minX, y: g.maxY))
            p.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        title.draw(at: NSPoint(x: 19, y: (bounds.height - 14) / 2), withAttributes: attrs)
    }

    public override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        checked.toggle()
        sendAction(action, to: target)
    }
}

/// Sunken single-line text field.
public final class W95TextField: NSTextField {
    public override init(frame f: NSRect) {
        super.init(frame: f)
        isBezeled = false; drawsBackground = true
        backgroundColor = .white
        font = W95.font(11)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirty: NSRect) {
        super.draw(dirty)
        NSBezierPath.w95Sunken(bounds.insetBy(dx: 0.5, dy: 0.5))
    }
}

/// Etched group box with an embedded label.
public final class W95GroupBox: NSView {
    public var title = "" { didSet { needsDisplay = true } }
    public let content = W95FlippedView()

    public init(title: String) {
        self.title = title
        super.init(frame: .zero)
        addSubview(content)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        content.frame = bounds.insetBy(dx: 10, dy: 18)
    }

    public override func draw(_ dirty: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11), .foregroundColor: NSColor.black]
        let ts = title.size(withAttributes: attrs)
        // etched frame: shadow rect offset by light rect
        let f = NSRect(x: 0.5, y: 7.5, width: bounds.width - 1, height: bounds.height - 8)
        W95.highlight.setStroke(); NSBezierPath(rect: f.offsetBy(dx: 1, dy: 1)).stroke()
        W95.shadow.setStroke(); NSBezierPath(rect: f).stroke()
        // label on face-colored patch
        W95.face.setFill()
        NSRect(x: 8, y: 0, width: ts.width + 8, height: 15).fill()
        title.draw(at: NSPoint(x: 12, y: 1), withAttributes: attrs)
    }
}

/// The taskbar: Start button, sunken task buttons, clock. Pin to a window bottom.
public final class W95Taskbar: NSView {
    public var onStart: (() -> Void)?
    private var tasks: [String] = []
    private var pressedStart = false
    private var clockTimer: Timer?
    public override init(frame f: NSRect) {
        super.init(frame: f)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clockTimer?.invalidate(); clockTimer = nil }
    }

    public func setTasks(_ t: [String]) { tasks = t; needsDisplay = true }

    private var startRect: NSRect { NSRect(x: 3, y: 3, width: 54, height: bounds.height - 6) }
    private var clockRect: NSRect { NSRect(x: bounds.maxX - 66, y: 3, width: 62, height: bounds.height - 6) }

    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()
        // top edge highlight
        W95.highlight.setStroke()
        let top = NSBezierPath(); top.lineWidth = 1
        top.move(to: NSPoint(x: 0, y: bounds.maxY - 0.5)); top.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 0.5))
        top.stroke()

        // Start button
        let sr = startRect
        W95.face.setFill(); sr.fill()
        NSBezierPath.w95Raised(sr.insetBy(dx: 0.5, dy: 0.5), pressed: pressedStart)
        let attrs: [NSAttributedString.Key: Any] = [.font: W95.font(11, bold: true), .foregroundColor: NSColor.black]
        let o: CGFloat = pressedStart ? 1 : 0
        "⊞ Start".draw(at: NSPoint(x: sr.minX + 8 + o, y: sr.minY + 3 + o), withAttributes: attrs)

        // task buttons
        var x = sr.maxX + 6
        for t in tasks {
            let r = NSRect(x: x, y: 3, width: 140, height: bounds.height - 6)
            if r.maxX > clockRect.minX - 6 { break }
            W95.face.setFill(); r.fill()
            NSBezierPath.w95ThinRaised(r.insetBy(dx: 0.5, dy: 0.5))
            let ta: [NSAttributedString.Key: Any] = [.font: W95.font(10), .foregroundColor: NSColor.black]
            t.draw(in: r.insetBy(dx: 6, dy: 4), withAttributes: ta)
            x += 144
        }

        // clock
        let cr = clockRect
        NSBezierPath.w95ThinSunken(cr.insetBy(dx: 0.5, dy: 0.5))
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        let ca: [NSAttributedString.Key: Any] = [.font: W95.font(10), .foregroundColor: NSColor.black]
        fmt.string(from: Date()).draw(in: cr.insetBy(dx: 6, dy: 4), withAttributes: ca)
    }
    public override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard startRect.contains(p) else { return }
        var inside = true
        pressedStart = true; needsDisplay = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: Date.distantFuture.timeIntervalSinceNow, mode: .eventTracking) { ev, stop in
            guard let ev else { stop.pointee = true; return }
            inside = self.startRect.contains(self.convert(ev.locationInWindow, from: nil))
            self.pressedStart = inside; self.needsDisplay = true
            if ev.type == .leftMouseUp { stop.pointee = true }
        }
        pressedStart = false; needsDisplay = true
        if inside { onStart?() }
    }
}
