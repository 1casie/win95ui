import AppKit
import CoreText

/// The Windows 95 color scheme, cross-checked against Chicago95's gtkrc.
/// Colors come from the live W95ThemeManager so every linked app follows
/// the dotfile edited by ControlTheme. Fonts stay static.
public enum W95 {
    public static var face: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.face) }
    public static var highlight: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.highlight) }
    public static var light: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.light) }
    public static var shadow: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.shadow) }
    public static var darkShadow: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.darkShadow) }
    // Chicago95: title bars are FLAT — the navy→blue gradient is a Win98 invention.
    public static var titleActive: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.titleActive) }
    public static var titleInactive: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.titleInactive) }
    public static var titleTextActive: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.titleTextActive) }
    public static var titleTextInactive: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.titleTextInactive) }
    public static var desktopTeal: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.desktopTeal) }
    public static var selection: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.selection) }
    public static var tooltipBG: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.tooltipBG) }
    public static var link: NSColor { NSColor(w95Hex: W95ThemeManager.shared.current.link) }

    /// The real MS Sans Serif look, via R95 bitmap-to-TTF conversions.
    /// Cascades to GNU Unifont for glyphs R95 doesn't cover (CJK, emoji, etc).
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
        let r95Name = "R95 Sans Serif \(r95Size)pt"
        if let base = NSFont(name: r95Name, size: size) {
            // Cascade to Unifont for missing glyphs — keeps the bitmap look.
            if let uni = NSFont(name: "Unifont", size: size) {
                let desc = base.fontDescriptor.addingAttributes([
                    .cascadeList: [uni.fontDescriptor]
                ])
                if let cascaded = NSFont(descriptor: desc, size: size) { return cascaded }
            }
            return base
        }
        if let f = NSFont(name: "Tahoma" + (bold ? "-Bold" : ""), size: size) { return f }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }

    /// BigBlueTerm437 for preformatted text — the classic terminal bitmap.
    /// Cascades to Unifont for missing glyphs.
    public static func monoFont(_ size: CGFloat = 12) -> NSFont {
        registerFonts()
        let base = NSFont(name: "BigBlueTerm437 Nerd Font Mono", size: size)
            ?? NSFont(name: "BigBlueTerm437NFM", size: size)
            ?? NSFont(name: "Fixedsys", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if let uni = NSFont(name: "Unifont", size: size) {
            let desc = base.fontDescriptor.addingAttributes([
                .cascadeList: [uni.fontDescriptor]
            ])
            if let cascaded = NSFont(descriptor: desc, size: size) { return cascaded }
        }
        return base
    }

    private static func registerFonts() {
        // CTFontManagerRegisterFontsForURL is idempotent; just call it every time.
        for size in [8, 10, 12, 14, 18, 24] {
            let name = "r95-sans-\(size)pt"
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        if let url = Bundle.module.url(forResource: "FSEX300", withExtension: "ttf") {
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
