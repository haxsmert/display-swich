import AppKit
import SwiftUI
import DisplaySwitchCore
import DisplaySwitchUI

// 用演示数据渲染真实的面板视图,生成 README 截图:
//     bash scripts/snapshots.sh           → 写到 docs/screenshots/
//
// 为什么不用真机截图:真机上屏名是显示器的真实型号,公开仓库里不该出现(对外脱敏)。
// 这里的屏名与单测夹具一致(External Display),开关只改内存里的状态,**不调用任何真实的显示器接口**。

/// 演示用的系统服务:三块屏(内建 + 两块经雷雳接的外接屏),开关只翻内存状态。
final class DemoDisplayService: SystemDisplayService {
    private var all: [DisplayInfo] = [
        DisplayInfo(id: 1, uuid: "demo-1", name: "Built-in Retina Display",
                    bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isMain: true, isBuiltin: true, isActive: true),
        DisplayInfo(id: 2, uuid: "demo-2", name: "External Display",
                    bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080), isMain: false, isBuiltin: false, isActive: true),
        DisplayInfo(id: 3, uuid: "demo-3", name: "External Display",
                    bounds: CGRect(x: 3432, y: 0, width: 1920, height: 1080), isMain: false, isBuiltin: false, isActive: true),
    ]
    private var off: Set<CGDirectDisplayID> = []

    var isSupported: Bool { true }
    func activeDisplays() -> [DisplayInfo] {
        let mainID = all.first { !off.contains($0.id) }?.id
        return all.filter { !off.contains($0.id) }.map {
            DisplayInfo(id: $0.id, uuid: $0.uuid, name: $0.name, bounds: $0.bounds,
                        isMain: $0.id == mainID, isBuiltin: $0.isBuiltin, isActive: true)
        }
    }
    func hasBuiltInDisplay() -> Bool { true }
    func liveExternalCount() -> Int? { 2 }
    func liveExternalPorts() -> [String]? { ["Port-USB-C@1/CIO/DisplayPort@0", "Port-USB-C@1/CIO/DisplayPort@1"] }
    func currentMode(_ id: CGDirectDisplayID) -> DisplayMode? {
        guard !off.contains(id) else { return nil }
        return id == 1 ? DisplayMode(pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
                       : DisplayMode(pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60)
    }
    func observeDisplayDisconnect(_ handler: @escaping (DisplayDisconnectSignal) -> Void) {}
    func inactiveDisplayIDs() -> [CGDirectDisplayID]? { off.sorted() }
    func isClamshellClosed() -> Bool? { false }
    func isDisplaySystemAsleep() -> Bool? { false }
    func observeBuiltInMayBecomeAvailable(_ handler: @escaping () -> Void) {}
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        if on { off.remove(id) } else { off.insert(id) }
        return true
    }
}

/// 原生开关只有在「当前 app 的当前窗口」里才画成强调色,否则是灰色(实测)。
/// 命令行进程当不了当前 app,所以要经 `scripts/snapshots.sh` 包成 .app、由 `open` 启动——
/// 系统会激活新启动的 app。无边框窗口默认又当不了当前窗口,这里放开。
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 把视图放进离屏窗口,按实际排版尺寸渲染成 PNG(含系统原生开关控件)。
func render(_ model: PanelModel, to url: URL) throws {
    // app 里面板的底是系统玻璃(PanelBackground),离屏渲染取不到玻璃背后的内容,截图用同圆角的实底示意。
    // 实底用系统的控件底色(浅色模式下是纯净的浅底):窗口底色偏灰,与强调色混出浑浊的灰紫(实测)。
    let shape = RoundedRectangle(cornerRadius: PanelBackground.cornerRadius, style: .continuous)
    let host = NSHostingView(rootView: PanelView(model: model)
        .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)))
    host.appearance = NSAppearance(named: .aqua)   // 截图固定浅色,与 README 预期一致
    host.layoutSubtreeIfNeeded()
    let size = host.fittingSize
    host.frame = CGRect(origin: .zero, size: size)
    let window = KeyableWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
    // open 启动的新 app 一般会被系统激活,但不是每次都成(实测偶发);再主动请求一次。
    if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    window.makeKeyAndOrderFront(nil)
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // 让 SwiftUI 完成布局与首帧绘制
    // 没成为当前 app 时开关会是灰的,截出来与真机不符;宁可失败,也不生成误导的图。
    guard NSApp.isActive, window.isKeyWindow else {
        print("❌ 截图窗口不是当前窗口(请用 scripts/snapshots.sh 启动),未生成 \(url.lastPathComponent)")
        exit(1)
    }
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
    window.orderOut(nil)
    print("已生成 \(url.path)(\(rep.pixelsWide)×\(rep.pixelsHigh))")
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // 要能成为当前 app,不能是 accessory
app.finishLaunching()
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/screenshots", isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let service = DemoDisplayService()
let controller = DisplayController(service: service)
let model = PanelModel(controller: controller, lastRescueProvider: { nil }, version: "1.0.18", driverHealth: .normal)

// ① 全部亮着
model.reload()
try render(model, to: outDir.appendingPathComponent("panel-overview.png"))

// ② 关掉内建屏和一块外接屏:最后一块被锁住,并写出原因
controller.toggle(id: 1)
controller.toggle(id: 2)
model.reload()
try render(model, to: outDir.appendingPathComponent("panel-locked.png"))
