import AppKit
import Win95

/// One line of a gemtext document, classified per the spec.
enum GemLine {
    case link(url: String, label: String?)
    case pre(String)          // raw text inside a ``` block
    case heading(level: Int, text: String)
    case listItem(String)
    case quote(String)
    case text(String)
}

enum Gemtext {
    /// Parse text/gemini source into lines. ``` toggles preformatted mode;
    /// everything else is only special outside pre blocks.
    static func parse(_ source: String) -> [GemLine] {
        var lines: [GemLine] = []
        var inPre = false
        for raw in source.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.hasPrefix("```") {
                inPre.toggle()
                continue
            }
            if inPre {
                lines.append(.pre(line))
                continue
            }
            if line.hasPrefix("=>") {
                var rest = line.dropFirst(2)
                rest = rest.drop(while: { $0 == " " || $0 == "\t" })
                // split on first run of whitespace: url [label]
                if let idx = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) {
                    let url = String(rest[..<idx])
                    let label = rest[idx...].drop(while: { $0 == " " || $0 == "\t" })
                    lines.append(.link(url: url, label: label.isEmpty ? nil : String(label)))
                } else {
                    lines.append(.link(url: String(rest), label: nil))
                }
            } else if line.hasPrefix("###") {
                lines.append(.heading(level: 3, text: String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("##") {
                lines.append(.heading(level: 2, text: String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("#") {
                lines.append(.heading(level: 1, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("*") {
                var rest = line.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
                lines.append(.listItem(String(rest)))
            } else if line.hasPrefix(">") {
                var rest = line.dropFirst()
                if rest.first == " " { rest = rest.dropFirst() }
                lines.append(.quote(String(rest)))
            } else {
                lines.append(.text(line))
            }
        }
        return lines
    }

    /// First level-1 heading, used for the window title.
    static func title(of lines: [GemLine]) -> String? {
        for l in lines {
            if case .heading(1, let t) = l, !t.isEmpty { return t }
        }
        return nil
    }

    /// A rendered link's character range and resolved URL, for hit-testing.
    struct LinkRegion {
        let range: NSRange
        let url: URL
    }

    /// Render parsed lines to an attributed string. `base` resolves relative
    /// link targets. Returns the string plus link regions for click handling.
    static func render(_ lines: [GemLine], base: URL,
                       mono: NSFont, proportional: NSFont,
                       headingFont: (CGFloat) -> NSFont) -> (NSAttributedString, [LinkRegion]) {
        let out = NSMutableAttributedString()
        var links: [LinkRegion] = []
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2

        func append(_ s: String, attrs: [NSAttributedString.Key: Any]) {
            out.append(NSAttributedString(string: s, attributes: attrs))
        }

        for line in lines {
            switch line {
            case .text(let t):
                append(t + "\n", attrs: [.font: proportional,
                                         .foregroundColor: NSColor.black,
                                         .paragraphStyle: para])
            case .pre(let t):
                append(t + "\n", attrs: [.font: mono,
                                         .foregroundColor: NSColor.black])
            case .heading(let level, let t):
                let size: CGFloat = level == 1 ? 18 : level == 2 ? 14 : 12
                let hp = NSMutableParagraphStyle()
                hp.paragraphSpacingBefore = level == 1 ? 8 : 6
                hp.paragraphSpacing = 4
                append(t + "\n", attrs: [.font: headingFont(size),
                                         .foregroundColor: NSColor.black,
                                         .paragraphStyle: hp])
            case .listItem(let t):
                append("  • " + t + "\n", attrs: [.font: proportional,
                                                 .foregroundColor: NSColor.black,
                                                 .paragraphStyle: para])
            case .quote(let t):
                let qp = NSMutableParagraphStyle()
                qp.headIndent = 16; qp.firstLineHeadIndent = 16
                qp.lineSpacing = 2
                append(t + "\n", attrs: [.font: proportional,
                                         .foregroundColor: W95.shadow,
                                         .paragraphStyle: qp])
            case .link(let target, let label):
                let resolved = URL(string: target, relativeTo: base)?.absoluteURL ?? base
                let display = label ?? target
                let lp = NSMutableParagraphStyle()
                lp.lineSpacing = 2
                append("=> ", attrs: [.font: proportional, .foregroundColor: NSColor.black,
                                      .paragraphStyle: lp])
                let start = out.length
                append(display + "\n", attrs: [.font: proportional,
                                               .foregroundColor: W95.link,
                                               .underlineStyle: NSUnderlineStyle.single.rawValue,
                                               .underlineColor: W95.link,
                                               .paragraphStyle: lp])
                links.append(LinkRegion(range: NSRange(location: start, length: display.count),
                                        url: resolved))
            }
        }
        return (out, links)
    }
}
