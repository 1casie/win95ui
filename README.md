# win95ui

A macOS Swift UI library for creating Windows 95-like applications natively.

Widgets, chrome, and the classic teal desktop — drawn with AppKit, not a web view. Use it from Swift, or drive it from C / Rust / anything else that can call a C ABI via the header in [`include/win95.h`](include/win95.h).

Requires macOS 14+ and Swift 6.

## Build

```sh
swift build
swift run Win95Demo
```

Pass `--render /tmp/win95.png` to snapshot the demo offscreen.

## Swift

```swift
import Win95

let win = W95Window(title: "Welcome",
                    contentRect: NSRect(x: 200, y: 200, width: 320, height: 180))
let ok = W95Button(title: "OK", isDefault: true)
ok.frame = NSRect(x: 220, y: 140, width: 88, height: 23)
win.clientArea.addSubview(ok)
win.makeKeyAndOrderFront(nil)
```

The library ships raised/sunken bevels, caption buttons, a status bar, checkboxes, radios, list boxes, combo boxes, sliders, spinners, progress bars, tabs, menus, a taskbar, and a Minesweeper board.

`clientArea` is flipped: `y = 0` is the top.

## C FFI

`swift build` produces `libWin95.dylib`. Other languages link that and include the C header:

```c
#include "win95.h"

w95_init();
w95_handle win = w95_window_new("Hello", 200, 200, 320, 180);
w95_run();
```

Every call except `w95_dispatch_main` must happen on the main thread. Callbacks fire on main.

A Rust Minesweeper that talks to the same ABI lives in [`Demos/minesweeper`](Demos/minesweeper).

```sh
swift build
cd Demos/minesweeper && cargo run
```
