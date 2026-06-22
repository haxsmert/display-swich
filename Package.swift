// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplaySwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DisplaySwitchCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "DisplaySwitchApp",
            dependencies: ["DisplaySwitchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DisplaySwitchCoreTests",
            dependencies: ["DisplaySwitchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
