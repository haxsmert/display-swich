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

        // ——— 全黑救援的两个触发源,缺一不可 ———
        //
        // 没有触发源,救援逻辑永远不会被执行:本 app 其余的状态对账全都挂在「菜单被打开」上,
        // 而全黑时用户根本点不开菜单栏。
        //
        // ① 拔线:全黑**发生**的那一刻。
        // 为什么不是 `CGDisplayRegisterReconfigurationCallback`——实测(2026-09-07 拔拓展坞现场):
        // 拔线与插回全程该回调**一次都没派发**(它只对配置变更如改分辨率派发);
        // 同一刻 `CGGetActiveDisplayList` 还报着拔线前的 3 块屏。v1.0.6 曾建在它上面,实为死代码。
        service.observeDisplayDisconnect { [weak self] in
            self?.attemptRescue(trigger: "拔线通知抵达")
        }
        // ② 开盖 / 唤醒:全黑**能被解除**的那一刻。
        // 只挂 ① 是不够的:真实动线是「拔坞 → 合盖 → 走人 → 到新地点开盖」,拔线那一刻盖子
        // 往往已经合上,内建屏物理不可用、救援注定失败;而开盖时不会再有任何拔线事件,
        // 救援就永远没有第二次机会。2026-09-18 事故正是如此——重试用尽后到新地点开盖,
        // 屏仍是黑的,只能强制重启。
        service.observeBuiltInMayBecomeAvailable { [weak self] in
            self?.attemptRescue(trigger: "开盖 / 唤醒")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAll()
    }

    /// 全黑救援 + 有界重试。两个触发源共用,`trigger` 只用于日志区分。
    ///
    /// 重试的意义:全黑那一刻 WindowServer 正在收拾残局,配置调用可能被拒。
    /// 但重试**不再是最后一道防线**——用尽之后,开盖 / 唤醒会重新触发全新的一轮。
    /// 这正是 2026-09-18 事故缺的那一环:当时重试用尽即永久放弃。
    ///
    /// 幂等性:两个事件源都会重复派发(一次拔线实测来 6 条,电源事件更频繁),
    /// 重复进入是常态——`needsBlackoutRescue()` 在无需救援时直接静默返回。
    private func attemptRescue(trigger: String, attemptsLeft: Int = 5) {
        // 必须先问「需不需要」再写日志:开盖 / 唤醒这个事件源很频繁,
        // 无需救援时若也记一行,日志会被刷爆,真正的事故现场反而淹没在噪声里。
        guard controller.needsBlackoutRescue() else { return }
        RescueLog.write("\(trigger) | \(controller.blackoutDiagnostics())")

        guard controller.rescueFromBlackout() else {
            RescueLog.write("  → 全黑,但盖子合着:内建屏此刻物理不可用,不做注定失败的尝试,等开盖")
            return
        }
        RescueLog.write("  → 已下恢复指令(剩余重试 \(attemptsLeft) 次),当前活跃屏 \(service.activeDisplays().count) 块")
        guard attemptsLeft > 0 else {
            RescueLog.write("  ⚠️ 重试用尽;若仍黑着,开盖 / 唤醒会重新触发一轮")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.attemptRescue(trigger: trigger, attemptsLeft: attemptsLeft - 1)
        }
    }
}

/// 救援路径的诊断日志。
///
/// 为什么非要有:全黑时用户看不到任何界面,菜单栏也点不开——救援若失败,现场随强制重启一起消失,
/// 事后无从判断「通知到底到没到、判据是多少、恢复调用成没成」。日志是这条路径唯一的黑匣子。
/// 2026-09-18 的事故能在几分钟内定位到确切环节,全靠它。只在救援相关事件发生时写,平时不产生一个字节。
enum RescueLog {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DisplaySwitch.log")

    /// 与**上一条**完全相同的消息不重复写。
    /// 事件源天然会重复派发(一次拔线实测来 6 条终止通知),状态没变时消息也一字不差——
    /// 重复记录只会把真正的现场淹没。只比上一条,所以状态变过又变回来仍会重新记录。
    private static var lastMessage: String?

    static func write(_ message: String) {
        guard message != lastMessage else { return }
        lastMessage = message
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "[\(stamp)] \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
