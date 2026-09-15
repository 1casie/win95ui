import AppKit
import CoreText

/// The Windows 95 color scheme, cross-checked against Chicago95's gtkrc.
public enum W95 {
    public static let face       = NSColor(calibratedRed: 0.753, green: 0.753, blue: 0.753, alpha: 1) // C0C0C0 buttonface
    public static let highlight  = NSColor.white                                                     // buttonhilight
    public static let light      = NSColor(calibratedRed: 0.875, green: 0.875, blue: 0.875, alpha: 1) // DFDFDF buttonlight
    public static let shadow     = NSColor(calibratedRed: 0.502, green: 0.502, blue: 0.502, alpha: 1) // 808080 buttonshadow
    public static let darkShadow = NSColor.black                                                     // buttondkshadow
    // Chicago95: title bars are FLAT — the navy→blue gradient is a Win98 invention.
    public static let titleActive       = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.502, alpha: 1)     // 000080
    public static let titleInactive     = NSColor(calibratedRed: 0.502, green: 0.502, blue: 0.502, alpha: 1) // 808080
    public static let titleTextActive   = NSColor.white
    public static let titleTextInactive = NSColor(calibratedRed: 0.753, green: 0.753, blue: 0.753, alpha: 1)
    public static let desktopTeal = NSColor(calibratedRed: 0.0, green: 0.502, blue: 0.502, alpha: 1) // 008080
    public static let selection   = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.502, alpha: 1)
    public static let tooltipBG   = NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.882, alpha: 1)   // FFFFE1
    public static let link        = NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.502, alpha: 1)

    /// The real MS Sans Serif look, via R95 bitmap-to-TTF conversions.
    /// Falls back to Tahoma/system if the bundled fonts aren't available.
    public static func font(_ size: CGFloat = 11, bold: Bool = false) -> NSFont {
        registerFonts()
        // R95 ships per-size bitmaps; pick the closest native size.
        let r95Size: Int = switch size {
        case ..<9: 8
        case 9..<11: 10
        case 11..<13: 12
        case 13..<16: 14
        case 16..<21: 18
        default: 24
        }
        if let f = NSFont(name: "R95 Sans Serif \(r95Size)pt", size: size) { return f }
        if let f = NSFont(name: "Tahoma" + (bold ? "-Bold" : ""), size: size) { return f }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }

    private static func registerFonts() {
        // CTFontManagerRegisterFontsForURL is idempotent; just call it every time.
        for size in [8, 10, 12, 14, 18, 24] {
            let name = "r95-sans-\(size)pt"
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

public extension NSBezierPath {
    /// Raised bevel per Chicago95: 1px outer border (bright TL / dark BR)
    /// over a 1px inner inset (light TL / shadow BR).
    static func w95Raised(_ r: NSRect, pressed: Bool = false) {
        if pressed { w95Pressed(r); return }
        W95.highlight.setStroke();  strokeEdge(r, [.minY, .minX])
        W95.darkShadow.setStroke(); strokeEdge(r, [.maxY, .maxX])
        let i = r.insetBy(dx: 1, dy: 1)
        W95.light.setStroke();   strokeEdge(i, [.minY, .minX])
        W95.shadow.setStroke();  strokeEdge(i, [.maxY, .maxX])
    }

    /// Pressed button: outer border inverts to dark TL / bright BR,
    /// single inner shadow line TL.
    static func w95Pressed(_ r: NSRect) {
        W95.darkShadow.setStroke(); strokeEdge(r, [.minY, .minX])
        W95.highlight.setStroke();  strokeEdge(r, [.maxY, .maxX])
        let i = r.insetBy(dx: 1, dy: 1)
        W95.shadow.setStroke(); strokeEdge(i, [.minY, .minX])
    }

    /// Classic 2px sunken bevel (text fields, status panels, wells).
    static func w95Sunken(_ r: NSRect) {
        W95.shadow.setStroke();     strokeEdge(r, [.minY, .minX])
        W95.darkShadow.setStroke(); strokeEdge(r.insetBy(dx: 1, dy: 1), [.minY, .minX])
        W95.highlight.setStroke();  strokeEdge(r, [.maxY, .maxX])
        W95.light.setStroke();      strokeEdge(r.insetBy(dx: 1, dy: 1), [.maxY, .maxX])
    }

    /// Thin 1px raised edge used for menu bars and toolbars.
    static func w95ThinRaised(_ r: NSRect) {
        W95.highlight.setStroke(); strokeEdge(r, [.minY, .minX])
        W95.shadow.setStroke();    strokeEdge(r, [.maxY, .maxX])
    }

    /// Thin 1px sunken edge (status bar panels, clock well).
    static func w95ThinSunken(_ r: NSRect) {
        W95.shadow.setStroke();    strokeEdge(r, [.minY, .minX])
        W95.highlight.setStroke(); strokeEdge(r, [.maxY, .maxX])
    }

    private static func strokeEdge(_ r: NSRect, _ edges: [NSRectEdge]) {
        for edge in edges {
            let p = NSBezierPath()
            p.lineWidth = 1
            switch edge {
            case .minY: p.move(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5)); p.line(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
            case .maxY: p.move(to: NSPoint(x: r.minX + 0.5, y: r.maxY - 0.5)); p.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
            case .minX: p.move(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5)); p.line(to: NSPoint(x: r.minX + 0.5, y: r.maxY - 0.5))
            case .maxX: p.move(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5)); p.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY - 0.5))
            default: break
            }
            p.stroke()
        }
    }
}

public extension NSAttributedString {
    /// Engraved disabled text: shadow-colored glyphs over a 1px white offset.
    static func w95DrawDisabled(_ text: String, in rect: NSRect, font: NSFont = W95.font(11)) {
        let base: [NSAttributedString.Key: Any] = [.font: font]
        var hi = base; hi[.foregroundColor] = W95.highlight
        var fg = base; fg[.foregroundColor] = W95.shadow
        text.draw(in: rect.offsetBy(dx: 1, dy: 1), withAttributes: hi)
        text.draw(in: rect, withAttributes: fg)
    }
}
