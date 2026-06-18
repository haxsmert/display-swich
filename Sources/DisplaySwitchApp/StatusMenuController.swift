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
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = controller.menuItems()

        if items.isEmpty {
            let empty = NSMenuItem(title: "未检测到外接显示器", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in items {
                let mi = NSMenuItem(title: item.label,
                                    action: #selector(toggleItem(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.state = item.isOn ? .on : .off
                mi.representedObject = item.id
                // 开着但不允许关(无内建屏的最后一块)→ 禁用该项,避免误关。
                mi.isEnabled = !(item.isOn && !item.canToggleOff)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
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
