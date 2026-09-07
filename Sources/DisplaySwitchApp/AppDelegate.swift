import AppKit
import CoreGraphics
import DisplaySwitchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = CGDisplayService()
    private lazy var controller = DisplayController(service: service)
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 只在菜单栏,不进 Dock

        // 启动兜底:若上次以 .forSession 关屏后异常退出,残留的断开屏在此恢复。
        // .forAppOnly 模式下本调用无副作用(配置已随上次进程退出回滚)。
        CGRestorePermanentDisplayConfiguration()

        menuController = StatusMenuController(controller: controller)

        // 全黑救援的触发源:拔线的**内核事件**。
        //
        // 没有它,救援逻辑永远不会被执行:本 app 其余的状态对账全都挂在「菜单被打开」上,
        // 而全黑时用户根本点不开菜单栏。
        //
        // 为什么不是 `CGDisplayRegisterReconfigurationCallback`——实测(2026-09-07 拔拓展坞现场):
        // 拔线与插回全程该回调**一次都没派发**(它只对配置变更如改分辨率派发);
        // 同一刻 `CGGetActiveDisplayList` 还报着拔线前的 3 块屏。v1.0.6 曾建在它上面,实为死代码。
        service.observeDisplayDisconnect { [weak self] in
            guard let self else { return }
            RescueLog.write("拔线通知抵达 | \(self.controller.blackoutDiagnostics())")
            self.rescueFromBlackout(attemptsLeft: 5)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAll()
    }

    /// 全黑救援 + 有界重试。
    ///
    /// 为什么要重试:拔线那一刻 WindowServer 正在收拾残局,配置调用可能被拒。
    /// 而一旦拒了就没有第二次机会——屏已经全黑,不会再有拔线事件来触发本回调,
    /// 用户也点不开菜单栏,只能强制重启。
    /// 为什么可以直接重试:`restoreAll()` 只清恢复成功的记录,失败的还留着,
    /// 所以再调一次就是自然的重试;一旦真的亮起来,下一轮即返回 false 自行收手。
    ///
    /// 幂等性:一次拔线内核会连着派发多条终止通知(实测一次拔线来了 6 条),
    /// 重复进入是常态——`rescueFromBlackout()` 在无需救援时返回 false,自行收手。
    private func rescueFromBlackout(attemptsLeft: Int) {
        guard controller.rescueFromBlackout() else {            // 无需救援(或已恢复)→ 收手
            RescueLog.write("判定无需救援,不动手")
            return
        }
        RescueLog.write("已执行救援(剩余重试 \(attemptsLeft) 次),当前活跃屏 \(service.activeDisplays().count) 块")
        guard attemptsLeft > 0 else {
            RescueLog.write("⚠️ 重试用尽,仍未恢复")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.rescueFromBlackout(attemptsLeft: attemptsLeft - 1)
        }
    }
}

/// 救援路径的诊断日志。
///
/// 为什么非要有:全黑时用户看不到任何界面,菜单栏也点不开——救援若失败,现场随强制重启一起消失,
/// 事后无从判断「通知到底到没到、判据是多少、恢复调用成没成」。日志是这条路径唯一的黑匣子。
/// 只在救援相关事件发生时写,平时一个字节都不产生。
enum RescueLog {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DisplaySwitch.log")

    static func write(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "[\(stamp)] \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
