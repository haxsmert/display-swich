import AppKit
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAll()
    }
}
