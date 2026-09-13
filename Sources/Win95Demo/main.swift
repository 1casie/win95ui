import AppKit
import Win95

let app = NSApplication.shared
app.setActivationPolicy(.regular)
W95Menus.installMainMenu(appName: "Win95 Demo")

// --- Taskbar: thin window pinned to the bottom of the screen ---------------
let screen = NSScreen.main!.frame
let tbWin = NSWindow(contentRect: NSRect(x: screen.minX, y: screen.minY,
                                         width: screen.width, height: 30),
                     styleMask: [.borderless], backing: .buffered, defer: false)
tbWin.isOpaque = true
tbWin.backgroundColor = W95.face
tbWin.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
tbWin.collectionBehavior = [.canJoinAllSpaces, .stationary]
tbWin.isMovable = false
let taskbar = W95Taskbar(frame: NSRect(x: 0, y: 0, width: screen.width, height: 30))
tbWin.contentView!.addSubview(taskbar)
tbWin.orderFront(nil)

// --- Control Panel showcase ------------------------------------------------
let props = W95Window(title: "Control Panel",
                      contentRect: NSRect(x: screen.midX - 400, y: screen.midY - 100, width: 380, height: 380))
let ca = props.clientArea
ca.wantsLayer = true
ca.layer?.backgroundColor = W95.face.cgColor

// menu bar inside the window
let menubar = W95MenuBar(frame: NSRect(x: 0, y: 0, width: 372, height: 20))
menubar.menus = [("File", ["New", "Open...", "-", "Exit"]),
                 ("Edit", ["Cut", "Copy", "Paste"]),
                 ("Help", ["About"])]
menubar.onSelect = { m, i in
    if m == 0 && i == 3 { NSApp.terminate(nil) }
}
ca.addSubview(menubar)

// tabs
let tabs = W95TabStrip(tabs: ["General", "Advanced", "About"])
tabs.frame = NSRect(x: 8, y: 26, width: 364, height: 340)
ca.addSubview(tabs)

// page content container (inside tab page area)
let page = W95FlippedView(frame: NSRect(x: 10, y: 50, width: 340, height: 300))
ca.addSubview(page)

let group = W95GroupBox(title: "Options")
group.frame = NSRect(x: 0, y: 0, width: 340, height: 118)
page.addSubview(group)

let chk1 = W95CheckBox(title: "Show desktop teal of regret", checked: true)
chk1.frame = NSRect(x: 8, y: 10, width: 260, height: 16)
group.content.addSubview(chk1)
let chk2 = W95CheckBox(title: "Enable Clippy (do not)")
chk2.frame = NSRect(x: 8, y: 34, width: 260, height: 16)
group.content.addSubview(chk2)

let r1 = W95Radio(title: "Dingboard", selected: true)
r1.frame = NSRect(x: 8, y: 58, width: 120, height: 16)
let r2 = W95Radio(title: "Dingcad")
r2.frame = NSRect(x: 140, y: 58, width: 120, height: 16)
let r3 = W95Radio(title: "Both (correct)")
r3.frame = NSRect(x: 8, y: 80, width: 160, height: 16)
r1.group = [r2, r3]; r2.group = [r1, r3]; r3.group = [r1, r2]
group.content.addSubview(r1); group.content.addSubview(r2); group.content.addSubview(r3)

// combo + spinner row
let combo = W95ComboBox(items: ["640×480", "800×600", "1024×768", "1600×1200 (luxury)"])
combo.frame = NSRect(x: 0, y: 122, width: 200, height: 22)
page.addSubview(combo)

let spinner = W95Spinner()
spinner.range = 1...31; spinner.value = 95
spinner.frame = NSRect(x: 220, y: 122, width: 80, height: 22)
page.addSubview(spinner)

// list box
let list = W95ListBox(items: ["AUTOEXEC.BAT", "CONFIG.SYS", "WIN.INI", "SYSTEM.INI",
                              "PROTOCOL.INI", "MSDOS.SYS", "BOOTLOG.TXT"])
list.frame = NSRect(x: 0, y: 154, width: 200, height: 92)
page.addSubview(list)

// slider + progress
let slider = W95Slider()
slider.frame = NSRect(x: 210, y: 160, width: 130, height: 24)
page.addSubview(slider)

let progress = W95ProgressBar(frame: NSRect(x: 210, y: 195, width: 130, height: 18))
progress.value = 0.65
page.addSubview(progress)

// text field + buttons
let field = W95TextField(frame: NSRect(x: 0, y: 256, width: 200, height: 22))
field.stringValue = "C:\\WINDOWS\\SYSTEM"
page.addSubview(field)

let okBtn = W95Button(title: "OK", isDefault: true)
okBtn.frame = NSRect(x: 252, y: 254, width: 88, height: 23)
page.addSubview(okBtn)
let applyBtn = W95Button(title: "Apply")
applyBtn.frame = NSRect(x: 252, y: 224, width: 88, height: 23)
applyBtn.isEnabled = false
page.addSubview(applyBtn)

// --- Notepad-ish window ----------------------------------------------------
let notepad = W95Window(title: "Untitled - Notepad",
                        contentRect: NSRect(x: screen.midX + 60, y: screen.midY - 40, width: 300, height: 220))
notepad.contentView!.layoutSubtreeIfNeeded()
let scroll = NSScrollView(frame: notepad.clientArea.bounds.insetBy(dx: 4, dy: 4))
scroll.autoresizingMask = [.width, .height]
scroll.hasVerticalScroller = true
scroll.borderType = .noBorder
let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
tv.autoresizingMask = [.width]
tv.isVerticallyResizable = true
tv.textContainer?.widthTracksTextView = true
tv.textContainerInset = NSSize(width: 4, height: 4)
tv.font = W95.font(12)
tv.string = "it is 1995.\nthe bevels are crisp.\nthe teal is eternal.\n\nclick the X. it actually closes."
tv.backgroundColor = .white
scroll.documentView = tv
notepad.clientArea.addSubview(scroll)
notepad.clientArea.wantsLayer = true
notepad.clientArea.layer?.backgroundColor = W95.face.cgColor

taskbar.setTasks(["Control Panel", "Untitled - Notepad"])
taskbar.onStart = {
    let alert = NSAlert()
    alert.messageText = "Windows 95"
    alert.informativeText = "It is now safe to turn off your computer."
    alert.runModal()
}

// --- Render mode: draw everything offscreen to a PNG -----------------------
if CommandLine.arguments.contains("--render") {
    let out = CommandLine.arguments.last == "--render" ? "/tmp/win95.png"
        : CommandLine.arguments[CommandLine.arguments.firstIndex(of: "--render")! + 1]
    let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
    canvas.wantsLayer = true
    canvas.layer?.backgroundColor = W95.desktopTeal.cgColor

    func snapshot(_ win: NSWindow, at origin: NSPoint) {
        win.contentView!.frame = NSRect(origin: origin, size: win.contentView!.frame.size)
        canvas.addSubview(win.contentView!)
    }
    for w in [props, notepad] { w.contentView!.layoutSubtreeIfNeeded() }
    snapshot(props, at: NSPoint(x: 40, y: 200))
    snapshot(notepad, at: NSPoint(x: 480, y: 80))
    let tb = W95Taskbar(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
    tb.setTasks(["Control Panel", "Untitled - Notepad"])
    canvas.addSubview(tb)

    canvas.layoutSubtreeIfNeeded()
    let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
    rep.size = canvas.bounds.size
    canvas.cacheDisplay(in: canvas.bounds, to: rep)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

props.makeKeyAndOrderFront(nil)
notepad.orderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
