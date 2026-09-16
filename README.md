# win95ui

Windows 95 UI kit for macOS. Native AppKit, no web views. Use it from Swift, or from C / Rust / anything that can call C (see [`include/win95.h`](include/win95.h)).

Requires macOS 14+ and Swift 6.

## Build

```sh
swift build
swift run Win95Demo
```

Want real apps instead of command line builds:

```sh
swift run bundle-apps
```

That drops Win95 Demo, Gemini 95, ControlTheme, WebKitty and Minesweeper into `Apps/` as double-clickable `.app` bundles. It matches its own build config: plain `swift run bundle-apps` stays in debug (fast), `swift run -c release bundle-apps` ships release. Pass `--debug` / `--release` to force it, `--only ControlTheme` for just one app, or a different output dir as the last arg.

## Demos

- `Sources/Win95Demo` — control showcase. Pass `--render /tmp/win95.png` to snapshot it offscreen.
- [`Demos/Gemini95Demo`](Demos/Gemini95Demo) — Gemini browser. Tabs with per-tab history, gemtext rendering in R95 Sans Serif with BigBlueTerm437 for pre blocks and Unifont fallback for CJK/emoji, Chicago95 toolbar icons, dialogs for input prompts, font smoothing off. Headless: `--fetch gemini://url` prints the response, `--render out.png` snapshots a page.
- [`Demos/ControlTheme`](Demos/ControlTheme) — the theme editor, see below. `swift run bundle-apps --only ControlTheme` packages just that one.
- [`Demos/WebKitty`](Demos/WebKitty) — Hacker News in Win95 chrome. A WebKit view (`W95WebView`) dressed up with a W95 toolbar, address field, progress bar and status bar. `swift run WebKitty`, because the small web deserves the teal desktop.
- [`Demos/minesweeper`](Demos/minesweeper) — Rust Minesweeper over the C ABI. Needs `swift build` first (it links the dylib), then `cargo run` in its dir.

## Theming

Every app using win95ui reads its colors from one file:

```
~/.config/win95ui/theme.json
```

(`$XDG_CONFIG_HOME` is respected if set.) It gets created with stock 95 colors the first time any app launches. Edit it by hand or use the editor:

```sh
swift run ControlTheme
```

Saving there updates all running Win95 apps on the spot. The editor also does presets from the command line:

```sh
ControlTheme --list-presets
ControlTheme --apply-preset "Hot Dog Stand"
```

## Theming in your own app

Swift: nothing to do if you use `W95Window`, it starts the listener on init. All the `W95` colors are live reads from the current theme, so anything you draw with them follows the dotfile. If you roll your own windows, call this once at launch:

```swift
W95ThemeManager.shared.startIfNeeded()
```

To react to changes (refresh a cached color, rebuild a menu), observe `.w95ThemeChanged` on the default NotificationCenter. One gotcha: layer background colors you set once (like `layer?.backgroundColor = W95.face.cgColor`) will not refresh until relaunch, so prefer drawing with the theme colors in `draw()` where you can. Presets live in `W95Theme.presets`, and `W95ThemeManager.shared.save(theme)` writes the file and tells every other app.

C / Rust: `w95_init()` starts the listener, so you already get it. The header has three extra calls:

```c
w95_theme_reload();  /* re-read the dotfile now */
w95_theme_reset();   /* back to stock 95 colors */
char *p = w95_theme_path(); /* where the file lives, free it after */
```

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

Has the usual stuff: bevels, caption buttons, status bar, checkboxes, radios, list boxes, combo boxes, sliders, spinners, progress bars, tabs, menus, a taskbar, and a Minesweeper board.

`clientArea` is flipped: `y = 0` is the top.

## C FFI

`swift build` makes `libWin95.dylib`. Link it and include the C header:

```c
#include "win95.h"

w95_init();
w95_handle win = w95_window_new("Hello", 200, 200, 320, 180);
w95_run();
```

Everything except `w95_dispatch_main` has to run on the main thread. Callbacks come back on main.
