import AppKit
import Win95

/// Thin wrapper around W95.font() — now backed by real R95 (MS Sans Serif)
/// bitmap fonts vendored into win95ui. The `mono` variant is the same font;
/// MS Sans Serif was proportional but reads as retro-terminal at small sizes.
enum W95Font {
    static func font(_ size: CGFloat = 10, bold: Bool = false) -> NSFont {
        W95.font(size, bold: bold)
    }
    static func mono(_ size: CGFloat = 10) -> NSFont { W95.monoFont(size) }
}

/// An NSTextView that disables font smoothing so TX-02 renders crisp,
/// and forwards link clicks to a handler instead of relying on .link attrs.
final class W95TextView: NSTextView {
    /// Called with the character index when the user clicks. Return true if handled.
    var onClick: ((Int) -> Bool)?

    override func draw(_ dirty: NSRect) {
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setShouldSmoothFonts(false)
            ctx.setAllowsFontSmoothing(false)
            ctx.setShouldAntialias(true)   // keep shape AA, kill font smoothing
        }
        super.draw(dirty)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let idx = characterIndexForInsertion(at: p)
        if let onClick, onClick(idx) { return }
        super.mouseDown(with: event)
    }
}
