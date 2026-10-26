// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplaySwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DisplaySwitchCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        // 面板界面单独成库:app 与截图工具共用同一份视图,README 截图画的就是真实界面。
        .target(
            name: "DisplaySwitchUI",
            dependencies: ["DisplaySwitchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DisplaySwitchApp",
            dependencies: ["DisplaySwitchCore", "DisplaySwitchUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 用演示数据(通用屏名,不碰真实显示器)渲染面板,生成 README 截图:swift run PanelSnapshots
        .executableTarget(
            name: "PanelSnapshots",
            dependencies: ["DisplaySwitchCore", "DisplaySwitchUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 雷雳显示驱动卡死的菜单栏监视器:不依赖上面任何一个库,只读系统日志(见 scripts/wedge-watch.sh)。
        .executableTarget(
            name: "WedgeWatch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DisplaySwitchCoreTests",
            dependencies: ["DisplaySwitchCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
