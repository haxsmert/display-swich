// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplaySwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DisplaySwitchCore"),
        .executableTarget(
            name: "DisplaySwitchApp",
            dependencies: ["DisplaySwitchCore"]
        ),
        .testTarget(
            name: "DisplaySwitchCoreTests",
            dependencies: ["DisplaySwitchCore"]
        ),
    ]
)
