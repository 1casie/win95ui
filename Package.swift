// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Win95",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Win95", type: .dynamic, targets: ["Win95"]),
        .executable(name: "Win95Demo", targets: ["Win95Demo"]),
    ],
    targets: [
        .target(name: "Win95", resources: [.process("Resources")]),
        .executableTarget(name: "Win95Demo", dependencies: ["Win95"]),
    ]
)
