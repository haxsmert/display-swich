import AppKit
import CoreGraphics
import DisplaySwitchCore

/// 管理菜单栏图标与下拉菜单。每次菜单打开时重建,反映最新显示器状态。
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: DisplayController

    init(controller: DisplayController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2",
                                   accessibilityDescription: "显示器开关")
        }
        let menu = NSMenu()
        menu.delegate = self
        // 关掉自动启用:否则 AppKit 见 target 响应 action 就强制可点,
        // 覆盖我们手动算的 isEnabled(最后一块活跃屏该灰显不可点)。
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let supported = controller.isSupported
        let items = controller.menuItems()

        // 不支持(非 Apple Silicon,或私有接口在未来 macOS 缺失):顶部提示,下方各屏只读不可切换。
        if !supported {
            let warn = NSMenuItem(title: "⚠️ 此设备不支持显示器开关(需 Apple Silicon + 受支持的 macOS)",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        if items.isEmpty {
            let empty = NSMenuItem(title: "未检测到显示器", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in items {
                let mi = NSMenuItem(title: item.label,
                                    action: supported ? #selector(toggleItem(_:)) : nil,
                                    keyEquivalent: "")
                mi.target = self
                mi.state = item.isOn ? .on : .off
                mi.representedObject = item.id
                // 不支持 → 全部只读;支持时:开着但不允许关(最后一块活跃屏)→ 禁用,避免误关。
                mi.isEnabled = supported && !(item.isOn && !item.canToggleOff)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID else { return }
        controller.toggle(id: id)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
