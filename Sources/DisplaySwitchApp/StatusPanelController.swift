import AppKit
import Combine
import SwiftUI
import DisplaySwitchCore
import DisplaySwitchUI

/// 菜单栏图标 + 自管的面板窗口。点图标开 / 关;点面板外、按 Esc、切到别的 app 时收起。
///
/// 为什么不用系统的 NSPopover(v1.0.17 用的就是它):它挂在菜单栏图标上,而开关**主屏**时
/// macOS 会把菜单栏连同图标搬到新的主屏,NSPopover 随之被系统收起,收起动画还按旧坐标播放——
/// 实测:开关内建屏(主屏)后面板每次都收起,开关非主屏的外接屏则留着(2026-10-22)。
/// 自己管窗口,何时收起由我们决定,图标挪到哪块屏,面板就跟到哪里。
final class StatusPanelController: NSObject {
    private let statusItem: NSStatusItem
    private let model: PanelModel
    private let panel: PanelWindow
    private let hosting: NSHostingView<AnyView>
    private let arrow: PanelArrow
    private var observers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []
    private var modelChange: AnyCancellable?
    /// 逻辑上开着没有。渐隐的 0.1 秒里窗口仍「可见」,开关判断不能看窗口可见与否。
    private var isOpen = false

    init(controller: DisplayController) {
        let model = PanelModel(controller: controller)
        let arrow = PanelArrow()
        self.model = model
        self.arrow = arrow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingView(rootView: AnyView(
            PanelChrome(arrow: arrow) { PanelView(model: model) }
        ))
        // 不激活本 app 的面板:打开时不抢走当前 app 的焦点,面板照样能点、能收 Esc(菜单栏面板的通行做法)。
        panel = PanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "显示器开关")
            button.target = self
            button.action = #selector(togglePanel(_:))
        }

        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear      // 圆角与箭头之外透明;面板本身是实底(见 PanelChrome)
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        // 何时收起全由我们决定:系统默认会在 app 退到后台时悄悄藏起面板,我们的收起逻辑就跑不到、
        // 点击监听留着不清(实测:面板被藏、日志里却没有收起记录)。
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let center = NotificationCenter.default
        // 图标被挪到别的屏(主屏变了,菜单栏跟着搬)时,它所在的窗口会移动 / 换屏;
        // 那个窗口对象也可能被系统换掉,所以不绑定具体对象,到达时再比对是不是图标的窗口。
        for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, self.isOpen,
                      let window = note.object as? NSWindow, window === self.statusItem.button?.window else { return }
                self.placePanel()
            })
        }
        // 屏幕增减、主屏变化:兜一次重新定位(图标窗口若被换掉、上面那条没对上,这里补上)。
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isOpen else { return }
            self.placePanelWhenIconReady()
        })
        // 别的 app 被激活(⌘Tab 或点了它)时收起,与系统菜单的习惯一致。
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.closePanel()
        })
        // 内容变了(多了一行锁住原因、屏数变化)就按新尺寸重新摆放。
        modelChange = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { if self?.isOpen == true { self?.placePanel() } }
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        isOpen ? closePanel() : showPanel()
    }

    /// 启动参数 `--show-panel` 用:刚启动时菜单栏图标的窗口虽已建好,尺寸还是 0(实测 40×0),
    /// 这时没有位置可贴。每 0.2 秒看一次图标是否有了真实尺寸,有了就弹,最多等 5 秒。
    func showPanelWhenReady(attemptsLeft: Int = 25) {
        if iconFrame() != nil { showPanel(); return }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPanelWhenReady(attemptsLeft: attemptsLeft - 1)
        }
    }

    func showPanel() {
        // 每次打开都重新读系统真相(面板开着时另由屏幕参数变化通知刷新)。
        model.reload()
        isOpen = true
        placePanel(animated: false)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        // 渐显,节奏与系统菜单一致;正在渐隐时再打开,就从当前透明度直接回到不透明。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        installEventMonitors()
    }

    private func closePanel() {
        guard isOpen else { return }
        isOpen = false
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // 渐隐期间又被打开了,就别收。
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
        })
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        // 点到别的 app 或桌面:收起。全局监听只收得到本 app 以外的点击,点面板本身不会触发。
        // 但菜单栏图标由系统的菜单栏进程托管,点图标对我们来说也是「外面」的点击:若在这里收起,
        // 图标自己的点击动作紧接着又把面板打开,看上去就是「再点图标收不起来」(他实测)。
        // 所以点在图标上的不算外面,交给图标的点击动作去开关。
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            if let icon = self.iconFrame(), icon.contains(NSEvent.mouseLocation) { return }
            self.closePanel()
        }) {
            eventMonitors.append(m)
        }
        // Esc 收起。
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.closePanel()
            return nil
        }) {
            eventMonitors.append(m)
        }
    }

    /// 菜单栏图标在屏幕上的位置;图标还没摆好(尺寸为 0)时返回 nil。
    private func iconFrame() -> NSRect? {
        guard let frame = statusItem.button?.window?.frame, frame.height > 0 else { return nil }
        return frame
    }

    /// 把面板贴在图标正下方,水平居中对齐图标,超出屏幕边缘时往里收。
    /// `animated`:同一块屏上挪位置时平滑跟过去;换屏、尺寸变化、刚打开时直接就位。
    private func placePanel(animated: Bool = true) {
        guard let icon = iconFrame() else { return }
        let size = hosting.fittingSize
        let screen = statusItem.button?.window?.screen ?? NSScreen.screens.first { $0.frame.contains(icon.origin) }
        var x = icon.midX - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        // 箭尖贴近图标下沿;箭头对准图标中线(面板被屏幕边缘往里推时也一样)。
        let frame = NSRect(x: x, y: icon.minY - size.height - 2, width: size.width, height: size.height)
        arrow.x = icon.midX - x
        guard frame != panel.frame else { return }
        let sameScreen = panel.screen != nil && panel.screen == screen
        if animated, isOpen, sameScreen, frame.size == panel.frame.size {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// 主屏刚变时图标正在搬家,位置可能一时还是 0 或旧值;等它就位再摆,最多等 2 秒。
    private func placePanelWhenIconReady(attemptsLeft: Int = 10) {
        placePanel()
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.placePanelWhenIconReady(attemptsLeft: attemptsLeft - 1)
        }
    }
}

/// 无边框窗口默认当不了当前窗口;面板里要能点、要能收 Esc,所以放开。
private final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
