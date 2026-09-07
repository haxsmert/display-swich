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

        // 全黑兜底的触发源。没有它,救援逻辑永远不会被执行:本 app 其余的状态对账
        // 全都挂在「菜单被打开」上,而全黑时用户根本点不开菜单栏。
        CGDisplayRegisterReconfigurationCallback(displayDidReconfigure,
                                                 Unmanaged.passUnretained(self).toOpaque())
    }

    func applicationWillTerminate(_ notification: Notification) {
        CGDisplayRemoveReconfigurationCallback(displayDidReconfigure,
                                               Unmanaged.passUnretained(self).toOpaque())
        controller.restoreAll()
    }

    /// 显示器配置发生变化后的处理(已在主线程)。
    fileprivate func displayConfigurationDidChange() {
        rescueFromBlackout(attemptsLeft: 5)
    }

    /// 全黑救援 + 有界重试。
    ///
    /// 为什么要重试:全黑那一刻 WindowServer 正在收拾拔线残局,配置调用可能被拒。
    /// 而一旦拒了就没有第二次机会——屏已经全黑,不会再有任何显示配置变更来触发本回调,
    /// 用户也点不开菜单栏,只能强制重启。
    /// 为什么可以直接重试:`restoreAll()` 只清恢复成功的记录,失败的还留着,
    /// 所以再调一次就是自然的重试;一旦真的亮起来,下一轮即返回 false 自行收手。
    private func rescueFromBlackout(attemptsLeft: Int) {
        guard controller.rescueFromBlackout() else { return }   // 无需救援(或已恢复)→ 收手
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.rescueFromBlackout(attemptsLeft: attemptsLeft - 1)
        }
    }
}

/// 显示配置变更回调。C 回调不能捕获上下文,故 AppDelegate 经 userInfo 指针传入。
///
/// 为什么只认「配置变更事件」、绝不改成定时轮询——两条都是实测(M 系列 · macOS 26):
///   1. 息屏时 `CGGetActiveDisplayList` **确实归零**(active=0 / online=1 / isAsleep=true)。
///      这不是意外:头文件对 active 的定义就是 "connected, **awake**, and available for drawing"。
///      故「活跃屏为 0」这个判据本身分不清「息屏」与「全黑」。
///   2. 但息屏与唤醒**全程不产生本回调**(实测 12 秒采样,回调 0 次)。
/// 所以由事件驱动天然免疫息屏误救援;换成轮询则每次息屏都会擅自把用户关掉的屏开回来。
/// 而拔线一定伴随一次显示重配置,正是需要救援的那一刻。
private func displayDidReconfigure(_ display: CGDirectDisplayID,
                                   _ flags: CGDisplayChangeSummaryFlags,
                                   _ userInfo: UnsafeMutableRawPointer?) {
    // 配置**开始前**也会回调一次,此时系统状态还没变,查了也是旧值,直接跳过。
    guard !flags.contains(.beginConfigurationFlag) else { return }
    guard let userInfo else { return }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
    // 不在回调里直接发起新的显示配置(重入风险),推到主队列;
    // 顺带让系统把这轮重配置收尾完,拿到的活跃屏列表才是最终状态。
    DispatchQueue.main.async { delegate.displayConfigurationDidChange() }
}
