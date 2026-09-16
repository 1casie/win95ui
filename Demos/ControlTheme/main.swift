import AppKit
import Win95

// MARK: - helpers (defined before use)

/// W95Button is final in the library, so clicks route through this bridge
/// instead of a subclass. One shared instance lives for the app lifetime.
final class ButtonBridge: NSObject, @unchecked Sendable {
    static let shared = ButtonBridge()
    private var handlers: [ObjectIdentifier: @MainActor () -> Void] = [:]
    func attach(_ btn: W95Button, _ fn: @MainActor @escaping () -> Void) {
        handlers[ObjectIdentifier(btn)] = fn
        btn.target = self
        btn.action = #selector(fire(_:))
    }
    // AppKit mouse tracking always fires on the main thread.
    @objc private func fire(_ sender: W95Button) {
        MainActor.assumeIsolated {
            handlers[ObjectIdentifier(sender)]?()
        }
    }
}
func makeButton(title: String, isDefault: Bool = false, fn: @MainActor @escaping () -> Void) -> W95Button {
    let b = W95Button(title: title, isDefault: isDefault)
    ButtonBridge.shared.attach(b, fn)
    return b
}

final class WellHook: NSObject {
    var onChange: (@MainActor (NSColorWell) -> Void)?
    @objc func changed(_ sender: NSColorWell) {
        let fn = onChange
        MainActor.assumeIsolated { fn?(sender) }
    }
}

enum ControlThemeIcon {
    static func make() -> NSImage {
        let s: CGFloat = 128
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        NSColor(calibratedRed: 0.753, green: 0.753, blue: 0.753, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSBezierPath.w95Raised(NSRect(x: 4.5, y: 4.5, width: s - 9, height: s - 9))
        NSColor(calibratedRed: 0, green: 0, blue: 0.502, alpha: 1).setFill()
        NSRect(x: 12, y: 12, width: s - 24, height: 22).fill()
        NSColor.white.setFill()
        NSRect(x: 16, y: 26, width: 60, height: 6).fill()
        let colors: [NSColor] = [
            NSColor(calibratedRed: 0, green: 0.502, blue: 0.502, alpha: 1),
            NSColor(calibratedRed: 0, green: 0, blue: 0.502, alpha: 1),
            NSColor.red, NSColor.yellow,
        ]
        let sw = (s - 48) / 2
        for (i, c) in colors.enumerated() {
            let rx = 16 + CGFloat(i % 2) * (sw + 8)
            let ry = 48 + CGFloat(i / 2) * (sw + 8)
            c.setFill()
            NSRect(x: rx, y: ry, width: sw, height: sw).fill()
            NSBezierPath.w95Sunken(NSRect(x: rx, y: ry, width: sw, height: sw))
        }
        img.unlockFocus()
        return img
    }
}

// MARK: - app

W95ThemeManager.shared.startIfNeeded()

// Headless: list or apply a preset without opening the GUI.
// Same save() path as the Apply button, so running apps update live.
if CommandLine.arguments.contains("--list-presets") {
    for p in W95Theme.presets { print(p.name) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--apply-preset"),
   CommandLine.arguments.count > i + 1 {
    let want = CommandLine.arguments[i + 1].lowercased()
    if let p = W95Theme.presets.first(where: { $0.name.lowercased() == want }) {
        print(W95ThemeManager.shared.save(p) ? "applied \(p.name)" : "save failed")
        exit(0)
    } else {
        print("unknown preset: \(CommandLine.arguments[i + 1])")
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
W95Menus.installMainMenu(appName: "Control Theme")
app.applicationIconImage = ControlThemeIcon.make()

struct ThemeField {
    let label: String
    let key: WritableKeyPath<W95Theme, String>
}
let fields: [ThemeField] = [
    ThemeField(label: "Button face", key: \.face),
    ThemeField(label: "Button highlight", key: \.highlight),
    ThemeField(label: "Button light", key: \.light),
    ThemeField(label: "Button shadow", key: \.shadow),
    ThemeField(label: "Button dark shadow", key: \.darkShadow),
    ThemeField(label: "Title bar (active)", key: \.titleActive),
    ThemeField(label: "Title bar (inactive)", key: \.titleInactive),
    ThemeField(label: "Title text (active)", key: \.titleTextActive),
    ThemeField(label: "Title text (inactive)", key: \.titleTextInactive),
    ThemeField(label: "Desktop", key: \.desktopTeal),
    ThemeField(label: "Selection", key: \.selection),
    ThemeField(label: "Tooltip", key: \.tooltipBG),
    ThemeField(label: "Link", key: \.link),
]

let screen = NSScreen.main!.frame
let win = W95Window(title: "Control Theme",
                    contentRect: NSRect(x: screen.midX - 260, y: screen.midY - 100,
                                        width: 500, height: 620))
let ca = win.clientArea
ca.wantsLayer = true
ca.layer?.backgroundColor = W95.face.cgColor

var wells: [NSColorWell] = []
var hexLabels: [NSTextField] = []
let status = NSTextField(labelWithString: "Pick a color, hit Apply.")
let pathLabel = NSTextField(labelWithString: "")

@MainActor func collect() -> W95Theme {
    var t = W95ThemeManager.shared.current
    for (i, f) in fields.enumerated() {
        t[keyPath: f.key] = wells[i].color.w95Hex
    }
    return t
}
@MainActor func refresh() {
    let cur = W95ThemeManager.shared.current
    for (i, f) in fields.enumerated() {
        wells[i].color = NSColor(w95Hex: cur[keyPath: f.key])
        hexLabels[i].stringValue = cur[keyPath: f.key].uppercased()
    }
}
@MainActor func preview() {
    // Local preview only. Other apps update on Apply.
    W95ThemeManager.shared.current = collect()
    let t = W95ThemeManager.shared.current
    for (i, f) in fields.enumerated() {
        hexLabels[i].stringValue = t[keyPath: f.key].uppercased()
    }
    status.stringValue = "Previewing. Hit Apply to save for all apps."
}
@MainActor func doApply() {
    let t = collect()
    if W95ThemeManager.shared.save(t) {
        refresh()
        status.stringValue = "Saved. Other Win95 apps pick it up live."
    } else {
        status.stringValue = "Save failed. Check the dotfile path."
    }
}
@MainActor func doRevert() {
    W95ThemeManager.shared.reload()
    // reload debounces rapid double-calls; force a refresh from disk state.
    refresh()
    status.stringValue = "Reverted to the file on disk."
}
@MainActor func doReset() {
    W95ThemeManager.shared.current = .windows95
    refresh()
    status.stringValue = "Previewing stock 95. Hit Apply to keep it."
}

var y: CGFloat = 8
let schemeLabel = NSTextField(labelWithString: "Scheme:")
schemeLabel.font = W95.font(11)
schemeLabel.frame = NSRect(x: 12, y: y, width: 60, height: 16)
ca.addSubview(schemeLabel)

y += 22
var x: CGFloat = 12
for preset in W95Theme.presets {
    let short = preset.name.replacingOccurrences(of: "Windows ", with: "")
    let p = preset
    let btn = makeButton(title: short) {
        W95ThemeManager.shared.current = p
        refresh()
        status.stringValue = "Previewing \(p.name). Hit Apply to keep it."
    }
    btn.frame = NSRect(x: x, y: y, width: 88, height: 23)
    ca.addSubview(btn)
    x += 94
}

y += 32
for f in fields {
    let label = NSTextField(labelWithString: f.label)
    label.font = W95.font(11)
    label.frame = NSRect(x: 12, y: y + 3, width: 190, height: 16)
    ca.addSubview(label)

    let well = NSColorWell(frame: NSRect(x: 210, y: y, width: 60, height: 23))
    ca.addSubview(well)
    wells.append(well)

    let hex = NSTextField(labelWithString: "#------")
    hex.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    hex.frame = NSRect(x: 280, y: y + 3, width: 90, height: 16)
    ca.addSubview(hex)
    hexLabels.append(hex)

    y += 29
}

y += 6
pathLabel.font = W95.font(10)
pathLabel.frame = NSRect(x: 12, y: y, width: 476, height: 28)
pathLabel.stringValue = "Saves to " + W95ThemeManager.shared.themeFilePath
ca.addSubview(pathLabel)

y += 34
let applyBtn = makeButton(title: "Apply", isDefault: true) { doApply() }
applyBtn.frame = NSRect(x: 12, y: y, width: 88, height: 23)
ca.addSubview(applyBtn)
let revertBtn = makeButton(title: "Revert") { doRevert() }
revertBtn.frame = NSRect(x: 108, y: y, width: 88, height: 23)
ca.addSubview(revertBtn)
let resetBtn = makeButton(title: "95 Default") { doReset() }
resetBtn.frame = NSRect(x: 204, y: y, width: 88, height: 23)
ca.addSubview(resetBtn)

y += 30
status.font = W95.font(10)
status.frame = NSRect(x: 12, y: y, width: 476, height: 16)
ca.addSubview(status)

let wellHook = WellHook()
wellHook.onChange = { _ in preview() }
for w in wells {
    w.target = wellHook
    w.action = #selector(WellHook.changed(_:))
}

// Hand-edited dotfile changed under us: refresh the wells.
NotificationCenter.default.addObserver(
    forName: .w95ThemeChanged, object: nil, queue: .main) { _ in
    refresh()
}

refresh()
win.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
