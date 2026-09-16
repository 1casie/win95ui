// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Win95",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Win95", type: .dynamic, targets: ["Win95"]),
        .executable(name: "Win95Demo", targets: ["Win95Demo"]),
        .executable(name: "bundle-apps", targets: ["BundleApps"]),
    ],
    targets: [
        .target(name: "Win95", resources: [.process("Resources")]),
        .executableTarget(name: "Win95Demo", dependencies: ["Win95"]),
        .executableTarget(name: "Gemini95Demo", dependencies: ["Win95"],
                         path: "Demos/Gemini95Demo",
                         resources: [.process("Resources")]),
        .executableTarget(name: "ControlTheme", dependencies: ["Win95"],
                         path: "Demos/ControlTheme"),
        .executableTarget(name: "BundleApps", path: "Tools/BundleApps"),
    ]
)
