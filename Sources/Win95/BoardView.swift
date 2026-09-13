import AppKit

/// A Minesweeper-style board: sunken header with 7-segment counters and a
/// face button, over a grid of beveled tiles. Pure drawing + hit-testing;
/// all game state lives in the caller (e.g. Rust) via callbacks.
public final class W95BoardView: NSView {
    public enum Cell: Int { case hidden = 0, revealed, flag, mine, exploded, wrongFlag }
    public enum Face: Int { case smile = 0, dead, cool }

    public var cols = 9 { didSet { needsDisplay = true } }
    public var rows = 9 { didSet { needsDisplay = true } }
    public var onCell: ((_ x: Int, _ y: Int, _ button: Int) -> Void)?
    public var onFace: (() -> Void)?

    private var cells: [Cell] = []
    private var face: Face = .smile
    private var facePressed = false
    /// Set while a press that began on the face is being tracked.
    private var faceTracking = false
    private var pressedCell: (Int, Int)?
    /// Cell under the cursor during a tracked press; nil when off the grid.
    /// Cleared on release alongside pressedCell.
    private var dragHover: (Int, Int)?
    private var leftCounter = 0
    private var rightCounter = 0

    private let tile: CGFloat = 16
    private let pad: CGFloat = 6
    private let headerH: CGFloat = 34

    public override var isFlipped: Bool { true }

    public var boardSize: NSSize {
        NSSize(width: CGFloat(cols) * tile + pad * 2 + 4,
               height: headerH + CGFloat(rows) * tile + pad * 2 + 8)
    }

    public func configure(cols: Int, rows: Int) {
        // Clamp: a zero/negative size would trap in Array(repeating:count:)
        // and poison every cells[y * cols + x] index below.
        self.cols = max(1, cols); self.rows = max(1, rows)
        cells = Array(repeating: .hidden, count: self.cols * self.rows)
        numbers = Array(repeating: 0, count: self.cols * self.rows)
        pressedCell = nil; dragHover = nil
        facePressed = false; faceTracking = false
        needsDisplay = true
    }

    /// Classified cell state, or .hidden when the indices are out of range or
    /// the storage hasn't been configured yet. Drawing and right-click gating
    /// use this so a mismatched cells array can never trap.
    private func cellState(_ x: Int, _ y: Int) -> Cell {
        let i = y * cols + x
        guard x >= 0, y >= 0, x < cols, y < rows, cells.indices.contains(i) else { return .hidden }
        return cells[i]
    }

    public func setCell(_ x: Int, _ y: Int, _ state: Int) {
        guard x >= 0, y >= 0, x < cols, y < rows,
              cells.count == cols * rows,
              let c = Cell(rawValue: state) else { return }
        cells[y * cols + x] = c
        needsDisplay = true
    }

    public func setFace(_ f: Int) {
        face = Face(rawValue: f) ?? .smile
        needsDisplay = true
    }

    public func setCounters(left: Int, right: Int) {
        leftCounter = left; rightCounter = right
        needsDisplay = true
    }

    private var gridOrigin: NSPoint {
        NSPoint(x: (bounds.width - CGFloat(cols) * tile) / 2,
                y: headerH + pad)
    }

    private var faceRect: NSRect {
        NSRect(x: bounds.midX - 13, y: pad + 3, width: 26, height: 26)
    }

    private func counterRect(left: Bool) -> NSRect {
        let w: CGFloat = 50, h: CGFloat = 24
        return left
            ? NSRect(x: pad + 6, y: pad + 4, width: w, height: h)
            : NSRect(x: bounds.maxX - pad - 6 - w, y: pad + 4, width: w, height: h)
    }

    public override func draw(_ dirty: NSRect) {
        W95.face.setFill(); bounds.fill()

        // header panel — sunken
        let header = NSRect(x: pad, y: pad, width: bounds.width - pad * 2, height: headerH - 4)
        NSBezierPath.w95Sunken(header.insetBy(dx: 0.5, dy: 0.5))

        drawCounter(counterRect(left: true), value: leftCounter)
        drawCounter(counterRect(left: false), value: rightCounter)
        drawFace(faceRect)

        // board field — sunken
        let go = gridOrigin
        let field = NSRect(x: go.x - 3, y: go.y - 3,
                           width: CGFloat(cols) * tile + 6, height: CGFloat(rows) * tile + 6)
        NSBezierPath.w95Sunken(field.insetBy(dx: 0.5, dy: 0.5))

        for y in 0..<rows {
            for x in 0..<cols {
                drawTile(x, y, at: NSRect(x: go.x + CGFloat(x) * tile,
                                          y: go.y + CGFloat(y) * tile,
                                          width: tile, height: tile))
            }
        }
        drawNumbers()
    }

    private func drawCounter(_ r: NSRect, value: Int) {
        NSColor.black.setFill(); r.fill()
        NSBezierPath.w95ThinSunken(r.insetBy(dx: 0.5, dy: 0.5))
        let clamped = max(-99, min(999, value))
        let str = clamped < 0 ? String(format: "-%02d", -clamped) : String(format: "%03d", clamped)
        var x = r.minX + 4
        for ch in str {
            drawDigit(ch, at: NSRect(x: x, y: r.minY + 3, width: 13, height: r.height - 6))
            x += 14
        }
    }

    // 7-segment digit, LED red on black
    private func drawDigit(_ ch: Character, at r: NSRect) {
        let segs: [Character: [Int]] = [
            "0": [0,1,2,3,4,5], "1": [1,2], "2": [0,1,6,4,3], "3": [0,1,6,2,3],
            "4": [5,6,1,2], "5": [0,5,6,2,3], "6": [0,5,6,4,2,3], "7": [0,1,2],
            "8": [0,1,2,3,4,5,6], "9": [0,1,2,3,5,6], "-": [6], " ": []
        ]
        let on = NSColor(calibratedRed: 1, green: 0.1, blue: 0.1, alpha: 1)
        let off = NSColor(calibratedRed: 0.25, green: 0.05, blue: 0.05, alpha: 1)
        let active = segs[ch] ?? []
        // segment rects: 0=top 1=topRight 2=botRight 3=bottom 4=botLeft 5=topLeft 6=mid
        let w = r.width, h = r.height, t: CGFloat = 2
        let rects: [NSRect] = [
            NSRect(x: r.minX + t, y: r.minY, width: w - 2*t, height: t),                       // top
            NSRect(x: r.maxX - t, y: r.minY + t, width: t, height: h/2 - t),                   // topRight
            NSRect(x: r.maxX - t, y: r.midY, width: t, height: h/2 - t),                       // botRight
            NSRect(x: r.minX + t, y: r.maxY - t, width: w - 2*t, height: t),                   // bottom
            NSRect(x: r.minX, y: r.midY, width: t, height: h/2 - t),                           // botLeft
            NSRect(x: r.minX, y: r.minY + t, width: t, height: h/2 - t),                       // topLeft
            NSRect(x: r.minX + t, y: r.midY - t/2, width: w - 2*t, height: t),                 // mid
        ]
        for i in 0..<7 {
            (active.contains(i) ? on : off).setFill()
            rects[i].fill()
        }
    }

    private func drawFace(_ r: NSRect) {
        W95.face.setFill(); r.fill()
        NSBezierPath.w95Raised(r.insetBy(dx: 0.5, dy: 0.5), pressed: facePressed)
        let g = r.insetBy(dx: 5, dy: 5).offsetBy(dx: facePressed ? 1 : 0, dy: facePressed ? 1 : 0)
        // yellow head
        NSColor(calibratedRed: 1, green: 0.85, blue: 0.1, alpha: 1).setFill()
        NSBezierPath(ovalIn: g).fill()
        NSColor.black.setStroke()
        NSBezierPath(ovalIn: g).stroke()
        switch face {
        case .smile, .cool:
            if face == .cool {
                // sunglasses
                NSColor.black.setFill()
                NSRect(x: g.minX + 2, y: g.minY + 4, width: 5, height: 3).fill()
                NSRect(x: g.maxX - 7, y: g.minY + 4, width: 5, height: 3).fill()
                NSRect(x: g.minX + 7, y: g.minY + 5, width: g.width - 14, height: 1).fill()
            } else {
                NSColor.black.setFill()
                NSRect(x: g.minX + 3.5, y: g.minY + 4, width: 2, height: 2.5).fill()
                NSRect(x: g.maxX - 5.5, y: g.minY + 4, width: 2, height: 2.5).fill()
            }
            let smile = NSBezierPath()
            smile.appendArc(withCenter: NSPoint(x: g.midX, y: g.midY - 1), radius: g.width/3,
                            startAngle: 200, endAngle: 340)
            smile.lineWidth = 1.2; smile.stroke()
        case .dead:
            // X eyes + flat mouth
            NSColor.black.setStroke()
            for cx in [g.minX + 4.5, g.maxX - 4.5] {
                let p = NSBezierPath(); p.lineWidth = 1.2
                p.move(to: NSPoint(x: cx - 1.5, y: g.minY + 3.5)); p.line(to: NSPoint(x: cx + 1.5, y: g.minY + 6.5))
                p.move(to: NSPoint(x: cx + 1.5, y: g.minY + 3.5)); p.line(to: NSPoint(x: cx - 1.5, y: g.minY + 6.5))
                p.stroke()
            }
            let m = NSBezierPath(); m.lineWidth = 1.2
            m.move(to: NSPoint(x: g.minX + 4, y: g.maxY - 4)); m.line(to: NSPoint(x: g.maxX - 4, y: g.maxY - 4))
            m.stroke()
        }
    }

    private func drawTile(_ x: Int, _ y: Int, at r: NSRect) {
        let c = cellState(x, y)
        let armed = pressedCell?.0 == x && pressedCell?.1 == y
        let hovered = dragHover?.0 == x && dragHover?.1 == y
        let isPressed = armed && hovered && c == .hidden
        switch c {
        case .hidden, .flag:
            W95.face.setFill(); r.fill()
            if !isPressed { NSBezierPath.w95Raised(r.insetBy(dx: 0.5, dy: 0.5)) }
            else { W95.shadow.setStroke(); NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke() }
            if c == .flag {
                // red flag on a pole
                let fx = r.midX, fy = r.minY + 3
                NSColor.black.setFill()
                NSRect(x: fx - 0.5, y: fy + 3, width: 1, height: 7).fill()
                NSRect(x: fx - 3, y: fy + 9, width: 7, height: 1.5).fill()
                NSColor.red.setFill()
                let f = NSBezierPath()
                f.move(to: NSPoint(x: fx + 0.5, y: fy)); f.line(to: NSPoint(x: fx - 4.5, y: fy + 2.5))
                f.line(to: NSPoint(x: fx + 0.5, y: fy + 5)); f.close()
                f.fill()
            }
        case .revealed:
            W95.face.setFill(); r.fill()
            W95.shadow.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        case .mine, .exploded, .wrongFlag:
            (c == .exploded ? NSColor.red : W95.face).setFill(); r.fill()
            W95.shadow.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            // mine: black circle + spikes
            let g = r.insetBy(dx: 4, dy: 4)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: g.insetBy(dx: 1.5, dy: 1.5)).fill()
            let s = NSBezierPath(); s.lineWidth = 1
            s.move(to: NSPoint(x: g.midX, y: g.minY - 1)); s.line(to: NSPoint(x: g.midX, y: g.maxY + 1))
            s.move(to: NSPoint(x: g.minX - 1, y: g.midY)); s.line(to: NSPoint(x: g.maxX + 1, y: g.midY))
            s.stroke()
            if c == .wrongFlag {
                NSColor.red.setStroke()
                let x = NSBezierPath(); x.lineWidth = 1.4
                x.move(to: r.origin); x.line(to: NSPoint(x: r.maxX, y: r.maxY))
                x.move(to: NSPoint(x: r.maxX, y: r.minY)); x.line(to: NSPoint(x: r.minX, y: r.maxY))
                x.stroke()
            }
        }
    }

    /// Number overlay drawn by the caller? No — numbers need state. We draw them here
    /// via a separate layer: setCell only stores Cell; numbers come through `numbers`.
    private var numbers: [Int] = []
    public func setNumber(_ x: Int, _ y: Int, _ n: Int) {
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        if numbers.count != cols * rows { numbers = Array(repeating: 0, count: cols * rows) }
        numbers[y * cols + x] = n
        needsDisplay = true
    }


    private func cellAt(_ p: NSPoint) -> (Int, Int)? {
        let go = gridOrigin
        let x = Int((p.x - go.x) / tile), y = Int((p.y - go.y) / tile)
        guard x >= 0, y >= 0, x < cols, y < rows else { return nil }
        return (x, y)
    }

    public override func mouseDown(with e: NSEvent) {
        guard let win = window else { return }
        var p = convert(e.locationInWindow, from: nil)
        if faceRect.contains(p) {
            faceTracking = true; facePressed = true; needsDisplay = true
        } else if let c = cellAt(p) {
            pressedCell = c; dragHover = c; needsDisplay = true
        } else {
            return
        }
        // Modal track: a bare mouseUp override never fires when the release
        // happens outside the view, which used to leave pressedCell /
        // facePressed stuck on. Consuming drag/up here guarantees the press
        // always resolves, and lets the highlight follow the cursor.
        while true {
            guard let ev = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            p = convert(ev.locationInWindow, from: nil)
            switch ev.type {
            case .leftMouseDragged:
                if faceTracking {
                    let h = faceRect.contains(p)
                    if h != facePressed { facePressed = h; needsDisplay = true }
                } else if pressedCell != nil {
                    let h = cellAt(p)
                    // NB: (Int, Int)? has no Equatable conformance — compare lanes.
                    if h?.0 != dragHover?.0 || h?.1 != dragHover?.1 { dragHover = h; needsDisplay = true }
                }
            case .leftMouseUp:
                finishLeftPress(at: p)
                return
            default:
                break
            }
        }
        // nextEvent returned nil mid-press (shouldn't happen while tracking);
        // drop any highlight so a stale press can't linger. A matching
        // mouseUp arriving later hits the cleared state and is a no-op.
        faceTracking = false; facePressed = false
        pressedCell = nil; dragHover = nil
        needsDisplay = true
    }

    private func finishLeftPress(at p: NSPoint) {
        if faceTracking {
            faceTracking = false; facePressed = false; needsDisplay = true
            if faceRect.contains(p) { onFace?() }
            return
        }
        if let c = pressedCell {
            pressedCell = nil; dragHover = nil; needsDisplay = true
            if let hit = cellAt(p), hit == c { onCell?(c.0, c.1, 0) }
        }
    }

    public override func mouseUp(with e: NSEvent) {
        // Safety net: mouseDown's tracking loop normally consumes the release,
        // but resolve defensively in case an up arrives unmatched.
        finishLeftPress(at: convert(e.locationInWindow, from: nil))
    }

    public override func rightMouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard let c = cellAt(p) else { return }
        // Flagging only applies to unrevealed tiles; right-clicks on revealed,
        // mined, or decided cells are swallowed (real Minesweeper ignores them).
        switch cellState(c.0, c.1) {
        case .hidden, .flag: onCell?(c.0, c.1, 1)
        default: break
        }
    }
}

extension W95BoardView {
    /// Called from draw to overlay neighbor counts on revealed cells.
    func drawNumbers() {
        guard numbers.count == cols * rows, cells.count == cols * rows else { return }
        let colors: [NSColor] = [.clear,
            NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1),      // 1 blue
            NSColor(calibratedRed: 0, green: 0.5, blue: 0, alpha: 1),    // 2 green
            NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),      // 3 red
            NSColor(calibratedRed: 0, green: 0, blue: 0.5, alpha: 1),    // 4 navy
            NSColor(calibratedRed: 0.5, green: 0, blue: 0, alpha: 1),    // 5 maroon
            NSColor(calibratedRed: 0, green: 0.5, blue: 0.5, alpha: 1),  // 6 teal
            NSColor.black,                                              // 7 black
            NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 1) // 8 gray
        ]
        let go = gridOrigin
        for y in 0..<rows {
            for x in 0..<cols {
                let n = numbers[y * cols + x]
                // n arrives over FFI untrusted: colors covers 0...8, so clamp the
                // index instead of trapping on bogus counts.
                guard n > 0, n < colors.count, cells[y * cols + x] == .revealed else { continue }
                let r = NSRect(x: go.x + CGFloat(x) * tile, y: go.y + CGFloat(y) * tile,
                               width: tile, height: tile)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: W95.font(11, bold: true), .foregroundColor: colors[n]]
                let s = String(n).size(withAttributes: attrs)
                String(n).draw(at: NSPoint(x: r.midX - s.width/2, y: r.midY - s.height/2),
                               withAttributes: attrs)
            }
        }
    }
}
