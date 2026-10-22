import AppKit
import SwiftUI
import DisplaySwitchCore
import DisplaySwitchUI


/// 菜单栏图标 + 弹出面板。点图标开 / 关面板,点面板外任意处自动收起。
final class StatusPanelController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: PanelModel

    init(controller: DisplayController) {
        model = PanelModel(controller: controller)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "显示器开关")
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func togglePanel(_ sender: Any?) {
        popover.isShown ? popover.performClose(sender) : showPanel()
    }

    /// 启动参数 `--show-panel` 用:刚启动时菜单栏图标的窗口虽已建好,尺寸还是 0(实测 40×0),
    /// 这时弹面板没有锚点、会落空。每 0.2 秒看一次图标是否有了真实尺寸,有了就弹,最多等 5 秒。
    func showPanelWhenReady(attemptsLeft: Int = 25) {
        if let frame = statusItem.button?.window?.frame, frame.height > 0 { showPanel(); return }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPanelWhenReady(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// 打开面板。
    func showPanel() {
        guard let button = statusItem.button else { return }
        // 每次打开都重新读系统真相(面板开着时另由屏幕参数变化通知刷新)。
        model.reload()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
