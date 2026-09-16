import AppKit

/// C ABI surface so other languages (Rust, etc.) can drive the Win95 widgets.
/// All handles are opaque pointers. Callbacks are C function pointers.
///
/// Threading: every function here MUST be called on the main thread, EXCEPT
/// w95_dispatch_main, which is safe from any thread (it hops to main before
/// running the callback). C callbacks installed via *_new always fire on the
/// main thread. The `ud` user-data pointer is passed through untouched — its
/// lifetime and any synchronization stay the caller's responsibility.

public typealias W95CellCB = @convention(c) (UnsafeMutableRawPointer?, Int32, Int32, Int32) -> Void
public typealias W95ActionCB = @convention(c) (UnsafeMutableRawPointer?) -> Void

@_cdecl("w95_init")
public func w95_init() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    W95ThemeManager.shared.startIfNeeded()
}

@_cdecl("w95_theme_reload")
public func w95_theme_reload() {
    W95ThemeManager.shared.reload()
}

@_cdecl("w95_theme_reset")
public func w95_theme_reset() {
    W95ThemeManager.shared.resetToDefault()
}

@_cdecl("w95_theme_path")
public func w95_theme_path() -> UnsafeMutablePointer<CChar> {
    strdup(W95ThemeManager.themeFileURL.path)
}

@_cdecl("w95_run")
public func w95_run() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.run()
}

@_cdecl("w95_window_new")
public func w95_window_new(_ title: UnsafePointer<CChar>, _ x: Double, _ y: Double,
                           _ w: Double, _ h: Double) -> UnsafeMutableRawPointer {
    let win = W95Window(title: String(cString: title),
                        contentRect: NSRect(x: x, y: y, width: w, height: h))
    win.makeKeyAndOrderFront(nil)
    return Unmanaged.passRetained(win).toOpaque()
}

@_cdecl("w95_window_client_size")
public func w95_window_client_size(_ win: UnsafeMutableRawPointer, _ outW: UnsafeMutablePointer<Double>,
                                   _ outH: UnsafeMutablePointer<Double>) {
    let w = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    w.contentView!.layoutSubtreeIfNeeded()
    outW.pointee = Double(w.clientArea.bounds.width)
    outH.pointee = Double(w.clientArea.bounds.height)
}

@_cdecl("w95_window_set_status")
public func w95_window_set_status(_ win: UnsafeMutableRawPointer, _ text: UnsafePointer<CChar>) {
    let w = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    w.frameView.statusText = String(cString: text)
}

@_cdecl("w95_button_new")
public func w95_button_new(_ win: UnsafeMutableRawPointer, _ title: UnsafePointer<CChar>,
                           _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                           _ isDefault: Bool, _ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let btn = W95Button(title: String(cString: title), isDefault: isDefault)
    btn.frame = NSRect(x: x, y: y, width: w, height: h)
    if let cb {
        // Stored as the associated object below (RETAIN): the box dies with
        // the control, so the action can never hit a dangling pointer.
        let box = CallbackBox(cb, ud)
        btn.target = CallbackTarget.shared
        btn.action = #selector(CallbackTarget.fire(_:))
        objc_setAssociatedObject(btn, cbKey, box, .OBJC_ASSOCIATION_RETAIN)
    }
    window.clientArea.addSubview(btn)
    return Unmanaged.passRetained(btn).toOpaque()
}

@_cdecl("w95_board_new")
public func w95_board_new(_ win: UnsafeMutableRawPointer, _ cols: Int32, _ rows: Int32,
                          _ cellCB: W95CellCB?, _ faceCB: W95ActionCB?,
                          _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    window.contentView!.layoutSubtreeIfNeeded()
    let board = W95BoardView()
    board.configure(cols: Int(cols), rows: Int(rows))
    board.frame = window.clientArea.bounds
    board.autoresizingMask = [.width, .height]
    if let cellCB {
        // The closure captures `box` strongly and the board retains the
        // closure, so the box lives exactly as long as the board: no leak,
        // and no dangling takeUnretainedValue if the view outlives the call.
        let box = CallbackBox(cellCB, ud)
        board.onCell = { [box] x, y, b in
            box.cell?(box.ud, Int32(x), Int32(y), Int32(b))
        }
    }
    if let faceCB {
        let box = CallbackBox(faceCB, ud)
        board.onFace = { [box] in
            box.action?(box.ud)
        }
    }
    window.clientArea.addSubview(board)
    return Unmanaged.passRetained(board).toOpaque()
}

@_cdecl("w95_board_set_cell")
public func w95_board_set_cell(_ board: UnsafeMutableRawPointer, _ x: Int32, _ y: Int32, _ state: Int32) {
    let b = Unmanaged<W95BoardView>.fromOpaque(board).takeUnretainedValue()
    b.setCell(Int(x), Int(y), Int(state))
}

@_cdecl("w95_board_set_number")
public func w95_board_set_number(_ board: UnsafeMutableRawPointer, _ x: Int32, _ y: Int32, _ n: Int32) {
    let b = Unmanaged<W95BoardView>.fromOpaque(board).takeUnretainedValue()
    b.setNumber(Int(x), Int(y), Int(n))
}

@_cdecl("w95_board_set_face")
public func w95_board_set_face(_ board: UnsafeMutableRawPointer, _ face: Int32) {
    let b = Unmanaged<W95BoardView>.fromOpaque(board).takeUnretainedValue()
    b.setFace(Int(face))
}

@_cdecl("w95_board_set_counters")
public func w95_board_set_counters(_ board: UnsafeMutableRawPointer, _ left: Int32, _ right: Int32) {
    let b = Unmanaged<W95BoardView>.fromOpaque(board).takeUnretainedValue()
    b.setCounters(left: Int(left), right: Int(right))
}

/// Post a closure to the main thread — safe to call from any thread.

// MARK: - chat-app surface

@_cdecl("w95_textfield_new")
public func w95_textfield_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double,
                              _ w: Double, _ h: Double) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let f = W95TextField(frame: NSRect(x: x, y: y, width: w, height: h))
    window.clientArea.addSubview(f)
    return Unmanaged.passRetained(f).toOpaque()
}

@_cdecl("w95_textfield_get")
public func w95_textfield_get(_ f: UnsafeMutableRawPointer) -> UnsafeMutablePointer<CChar> {
    let field = Unmanaged<W95TextField>.fromOpaque(f).takeUnretainedValue()
    return strdup(field.stringValue)
}

@_cdecl("w95_textfield_set")
public func w95_textfield_set(_ f: UnsafeMutableRawPointer, _ s: UnsafePointer<CChar>) {
    Unmanaged<W95TextField>.fromOpaque(f).takeUnretainedValue().stringValue = String(cString: s)
}

/// Scrollable read-only transcript view. Caller appends lines.
@_cdecl("w95_chatview_new")
public func w95_chatview_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double,
                             _ w: Double, _ h: Double) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let scroll = NSScrollView(frame: NSRect(x: x, y: y, width: w, height: h))
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.autoresizingMask = [.width, .height]
    let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: w, height: h))
    tv.isEditable = false
    tv.font = W95.font(11)
    tv.backgroundColor = .white
    tv.textContainerInset = NSSize(width: 4, height: 4)
    tv.autoresizingMask = [.width]
    tv.isVerticallyResizable = true
    tv.textContainer?.widthTracksTextView = true
    scroll.documentView = tv
    window.clientArea.addSubview(scroll)
    // return the text view; the scroll view is just chrome
    return Unmanaged.passRetained(tv).toOpaque()
}

@_cdecl("w95_chatview_append")
public func w95_chatview_append(_ tv: UnsafeMutableRawPointer, _ line: UnsafePointer<CChar>) {
    let v = Unmanaged<NSTextView>.fromOpaque(tv).takeUnretainedValue()
    let s = String(cString: line)
    v.textStorage?.append(NSAttributedString(string: s + "\n",
        attributes: [.font: W95.font(11), .foregroundColor: NSColor.black]))
    v.scrollToEndOfDocument(nil)
}

@_cdecl("w95_open_url")
public func w95_open_url(_ url: UnsafePointer<CChar>) {
    if let u = URL(string: String(cString: url)) { NSWorkspace.shared.open(u) }
}

@_cdecl("w95_window_set_title")
public func w95_window_set_title(_ win: UnsafeMutableRawPointer, _ title: UnsafePointer<CChar>) {
    let w = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    w.frameView.windowTitle = String(cString: title)
}
/// The passRetained/takeRetainedValue pair is balanced: the main-queue block
/// runs exactly once and releases the box, so this neither leaks nor dangles.
@_cdecl("w95_dispatch_main")
public func w95_dispatch_main(_ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) {
    let box = Unmanaged.passRetained(CallbackBox(cb, ud)).toOpaque()
    DispatchQueue.main.async {
        let b = Unmanaged<CallbackBox>.fromOpaque(box).takeRetainedValue()
        b.action?(b.ud)
    }
}

// MARK: - extended controls

@_cdecl("w95_checkbox_new")
public func w95_checkbox_new(_ win: UnsafeMutableRawPointer, _ title: UnsafePointer<CChar>,
                             _ x: Double, _ y: Double, _ checked: Bool,
                             _ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let w = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let c = W95CheckBox(title: String(cString: title), checked: checked)
    c.frame = NSRect(x: x, y: y, width: c.intrinsicContentSize.width, height: 16)
    if let cb {
        let box = CallbackBox(cb, ud)
        c.target = CallbackTarget.shared
        c.action = #selector(CallbackTarget.fireCheck(_:))
        objc_setAssociatedObject(c, cbKey, box, .OBJC_ASSOCIATION_RETAIN)
    }
    w.clientArea.addSubview(c)
    return Unmanaged.passRetained(c).toOpaque()
}

@_cdecl("w95_progress_new")
public func w95_progress_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double,
                             _ w: Double, _ h: Double) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let p = W95ProgressBar(frame: NSRect(x: x, y: y, width: w, height: h))
    window.clientArea.addSubview(p)
    return Unmanaged.passRetained(p).toOpaque()
}

@_cdecl("w95_progress_set")
public func w95_progress_set(_ bar: UnsafeMutableRawPointer, _ value: Double) {
    Unmanaged<W95ProgressBar>.fromOpaque(bar).takeUnretainedValue().value = value
}

@_cdecl("w95_listbox_new")
public func w95_listbox_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double,
                            _ w: Double, _ h: Double,
                            _ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let l = W95ListBox(items: [])
    l.frame = NSRect(x: x, y: y, width: w, height: h)
    if let cb {
        let box = CallbackBox(cb, ud)
        l.target = CallbackTarget.shared
        l.action = #selector(CallbackTarget.fireList(_:))
        objc_setAssociatedObject(l, cbKey, box, .OBJC_ASSOCIATION_RETAIN)
    }
    window.clientArea.addSubview(l)
    return Unmanaged.passRetained(l).toOpaque()
}

@_cdecl("w95_listbox_add")
public func w95_listbox_add(_ list: UnsafeMutableRawPointer, _ item: UnsafePointer<CChar>) {
    let l = Unmanaged<W95ListBox>.fromOpaque(list).takeUnretainedValue()
    l.items.append(String(cString: item))
}

@_cdecl("w95_listbox_selected")
public func w95_listbox_selected(_ list: UnsafeMutableRawPointer) -> Int32 {
    Int32(Unmanaged<W95ListBox>.fromOpaque(list).takeUnretainedValue().selectedIndex ?? -1)
}

@_cdecl("w95_slider_new")
public func w95_slider_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double, _ w: Double,
                           _ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let s = W95Slider()
    s.frame = NSRect(x: x, y: y, width: w, height: 24)
    if let cb {
        let box = CallbackBox(cb, ud)
        s.target = CallbackTarget.shared
        s.action = #selector(CallbackTarget.fireSlider(_:))
        objc_setAssociatedObject(s, cbKey, box, .OBJC_ASSOCIATION_RETAIN)
    }
    window.clientArea.addSubview(s)
    return Unmanaged.passRetained(s).toOpaque()
}

@_cdecl("w95_slider_get")
public func w95_slider_get(_ s: UnsafeMutableRawPointer) -> Double {
    Unmanaged<W95Slider>.fromOpaque(s).takeUnretainedValue().value
}

@_cdecl("w95_spinner_new")
public func w95_spinner_new(_ win: UnsafeMutableRawPointer, _ x: Double, _ y: Double, _ w: Double,
                            _ min: Int32, _ max: Int32, _ initial: Int32,
                            _ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
    let window = Unmanaged<W95Window>.fromOpaque(win).takeUnretainedValue()
    let s = W95Spinner()
    s.range = Int(min)...Int(max)
    s.value = Int(initial)
    s.frame = NSRect(x: x, y: y, width: w, height: 22)
    if let cb {
        let box = CallbackBox(cb, ud)
        s.target = CallbackTarget.shared
        s.action = #selector(CallbackTarget.fireSpinner(_:))
        objc_setAssociatedObject(s, cbKey, box, .OBJC_ASSOCIATION_RETAIN)
    }
    window.clientArea.addSubview(s)
    return Unmanaged.passRetained(s).toOpaque()
}

@_cdecl("w95_spinner_get")
public func w95_spinner_get(_ s: UnsafeMutableRawPointer) -> Int32 {
    Int32(Unmanaged<W95Spinner>.fromOpaque(s).takeUnretainedValue().value)
}

// MARK: - callback plumbing

nonisolated(unsafe) private let cbKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

final class CallbackBox: NSObject, @unchecked Sendable {
    let action: W95ActionCB?
    let cell: W95CellCB?
    let ud: UnsafeMutableRawPointer?
    init(_ cb: W95ActionCB?, _ ud: UnsafeMutableRawPointer?) { action = cb; cell = nil; self.ud = ud; super.init() }
    init(_ cb: W95CellCB?, _ ud: UnsafeMutableRawPointer?) { action = nil; cell = cb; self.ud = ud; super.init() }
}

final class CallbackTarget: NSObject, @unchecked Sendable {
    static let shared = CallbackTarget()
    private func fireBox(_ sender: NSControl) {
        // The box was stored as the associated object itself (RETAIN), so it
        // is alive whenever the control is — a direct cast, no Unmanaged.
        guard let b = objc_getAssociatedObject(sender, cbKey) as? CallbackBox else { return }
        b.action?(b.ud)
    }
    @objc func fire(_ sender: W95Button) { fireBox(sender) }
    @objc func fireCheck(_ sender: W95CheckBox) { fireBox(sender) }
    @objc func fireList(_ sender: W95ListBox) { fireBox(sender) }
    @objc func fireSlider(_ sender: W95Slider) { fireBox(sender) }
    @objc func fireSpinner(_ sender: W95Spinner) { fireBox(sender) }
}
