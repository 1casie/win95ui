import Foundation

// bundle-apps: assemble every demo as a double-clickable macOS .app.
// Run it with `swift run bundle-apps [--debug|--release] [--only Name] [output-dir]`.
// Defaults to whatever configuration this tool itself was built with, so
// `swift run bundle-apps` stays in debug (fast) and
// `swift run -c release bundle-apps` ships release. Pure Swift, no shell scripts.

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

@MainActor
@discardableResult
func run(_ exe: String, _ args: [String], cwd: URL? = nil) throws -> String {
    // Inherit stdio instead of piping: a full build's output exceeds the
    // pipe buffer, and waitUntilExit would deadlock waiting on ourselves.
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = [exe] + args
    if let cwd { p.currentDirectoryURL = cwd }
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    try p.run()
    p.waitUntilExit()
    if p.terminationStatus != 0 {
        throw NSError(domain: "bundle-apps", code: Int(p.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(exe) \(args.joined(separator: " ")) failed"])
    }
    return ""
}

@MainActor
func shell(_ exe: String, _ args: [String], cwd: URL? = nil) {
    do { _ = try run(exe, args, cwd: cwd) }
    catch { print("warning: \(error.localizedDescription), continuing") }
}

var args = CommandLine.arguments.dropFirst()
// Match our own build configuration unless told otherwise: that way a plain
// `swift run bundle-apps` does one debug build total instead of debug
// for the tool plus a redundant release world-build.
let selfIsRelease = CommandLine.arguments[0].lowercased().contains("release")
var debug = !selfIsRelease
if args.contains("--debug") { debug = true }
if args.contains("--release") { debug = false }
args.removeAll(where: { $0 == "--debug" || $0 == "--release" })
var only: String?
if let i = args.firstIndex(of: "--only"), args.count > args.distance(from: args.startIndex, to: i) + 1 {
    only = args[args.index(after: i)]
    args.remove(at: args.index(after: i))
    args.remove(at: i)
}
let config = debug ? "debug" : "release"
let outDir = args.first.map { URL(fileURLWithPath: $0) } ?? cwd.appendingPathComponent("Apps")
let swiftBuild = cwd.appendingPathComponent(".build/\(config)")
let cargoBuild = cwd.appendingPathComponent("Demos/minesweeper/target/\(config)")

@MainActor
func wanted(_ name: String) -> Bool { only == nil || only == name }

print("==> swift build (\(config))")
try run("swift", ["build", "-c", config])

if wanted("Minesweeper") {
    print("==> cargo build (\(config))")
    var cargoArgs = ["build"]
    if !debug { cargoArgs.append("--release") }
    try run("cargo", cargoArgs, cwd: cwd.appendingPathComponent("Demos/minesweeper"))
}

try? fm.removeItem(at: outDir)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

@MainActor
func mkapp(name: String, binary: URL, plist: URL, extraBundles: [String] = []) throws {
    let app = outDir.appendingPathComponent("\(name).app")
    try? fm.removeItem(at: app)
    let macOS = app.appendingPathComponent("Contents/MacOS")
    let resources = app.appendingPathComponent("Contents/Resources")
    try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
    try fm.createDirectory(at: resources, withIntermediateDirectories: true)
    try fm.copyItem(at: binary, to: macOS.appendingPathComponent(binary.lastPathComponent))
    try fm.copyItem(at: plist, to: app.appendingPathComponent("Contents/Info.plist"))
    // Win95 fonts live here; Bundle.module checks the main bundle first,
    // so every app finds them in Resources.
    try fm.copyItem(at: swiftBuild.appendingPathComponent("Win95_Win95.bundle"),
                    to: resources.appendingPathComponent("Win95_Win95.bundle"))
    for b in extraBundles {
        try fm.copyItem(at: swiftBuild.appendingPathComponent(b),
                        to: resources.appendingPathComponent(b))
    }
    print("wrote \(app.path)")
}

if wanted("Win95Demo") {
    try mkapp(name: "Win95Demo",
              binary: swiftBuild.appendingPathComponent("Win95Demo"),
              plist: cwd.appendingPathComponent("Sources/Win95Demo/Info.plist"))
}
if wanted("Gemini95Demo") {
    try mkapp(name: "Gemini95Demo",
              binary: swiftBuild.appendingPathComponent("Gemini95Demo"),
              plist: cwd.appendingPathComponent("Demos/Gemini95Demo/Info.plist"),
              extraBundles: ["Win95_Gemini95Demo.bundle"])
}
if wanted("ControlTheme") {
    try mkapp(name: "ControlTheme",
              binary: swiftBuild.appendingPathComponent("ControlTheme"),
              plist: cwd.appendingPathComponent("Demos/ControlTheme/Info.plist"))
}
if wanted("WebKitty") {
    try mkapp(name: "WebKitty",
              binary: swiftBuild.appendingPathComponent("WebKitty"),
              plist: cwd.appendingPathComponent("Demos/WebKitty/Info.plist"))
}
if wanted("Minesweeper") {
    // Rust over the C ABI: it needs the dylib next to it.
    let app = outDir.appendingPathComponent("Minesweeper.app")
    try? fm.removeItem(at: app)
    let macOS = app.appendingPathComponent("Contents/MacOS")
    let resources = app.appendingPathComponent("Contents/Resources")
    let frameworks = app.appendingPathComponent("Contents/Frameworks")
    for d in [macOS, resources, frameworks] {
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
    }
    try fm.copyItem(at: cargoBuild.appendingPathComponent("minesweeper95"),
                    to: macOS.appendingPathComponent("minesweeper"))
    try fm.copyItem(at: cwd.appendingPathComponent("Demos/minesweeper/Info.plist"),
                    to: app.appendingPathComponent("Contents/Info.plist"))
    try fm.copyItem(at: swiftBuild.appendingPathComponent("libWin95.dylib"),
                    to: frameworks.appendingPathComponent("libWin95.dylib"))
    try fm.copyItem(at: swiftBuild.appendingPathComponent("Win95_Win95.bundle"),
                    to: resources.appendingPathComponent("Win95_Win95.bundle"))
    let exe = macOS.appendingPathComponent("minesweeper").path
    shell("install_name_tool", ["-add_rpath", "@executable_path/../Frameworks", exe])
    shell("codesign", ["-f", "-s", "-", exe])
    print("wrote \(app.path)")
}

print("done. try: open \(outDir.appendingPathComponent("ControlTheme.app").path)")
