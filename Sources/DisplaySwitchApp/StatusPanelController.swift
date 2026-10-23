import AppKit
import Combine
import SwiftUI
import DisplaySwitchCore
import DisplaySwitchUI

/// 菜单栏图标 + 自管的面板窗口。点图标开 / 关;点面板外、切到别的 app 时收起,本 app 收得到按键时按 Esc 也收起。
///
/// 为什么不用系统的 NSPopover(v1.0.17 用的就是它):它挂在菜单栏图标上,而开关**主屏**时
/// macOS 会把菜单栏连同图标搬到新的主屏,NSPopover 随之被系统收起,收起动画还按旧坐标播放——
/// 实测:开关内建屏(主屏)后面板每次都收起,开关非主屏的外接屏则留着(2026-10-22)。
/// 自己管窗口,何时收起由我们决定,图标挪到哪块屏,面板就跟到哪里。
///
/// **macOS 27 起,开 / 关走系统的「展开界面」会话**(`expandedInterfaceDelegate`),不再自己接图标的点击:
/// 系统为不用 NSMenu、自己摆窗口的菜单栏图标提供的正式做法(见 SDK 头文件 `NSStatusItem.h` 的说明)。
/// 会话开着时,系统给图标画上与 Wi-Fi 等系统菜单相同的高亮底——自己调 `highlight(true)` 在 macOS 27 上
/// 画不出来(实测:同步、异步、改按钮类型都试过);图标也随之参与菜单栏的键盘导航与菜单跟踪。
/// 我们自己收起面板时(点外面、按 Esc、切 app)要取消会话,系统随后回调「会话结束」,在那里真正收起。
/// 更早的系统没有这套接口,照旧接图标的点击。
final class StatusPanelController: NSObject {
    private let statusItem: NSStatusItem
    private let model: PanelModel
    private let panel: PanelWindow
    private let hosting: NSHostingView<PanelView>
    private var observers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []
    private var modelChange: AnyCancellable?
    /// 逻辑上开着没有。渐隐的 0.1 秒里窗口仍「可见」,开关判断不能看窗口可见与否。
    private var isOpen = false
    /// 开着时是否已显示出来。开着却没显示 = 图标正在搬家、还没落进菜单栏,见 `placePanel()`。
    private var revealed = false
    /// 面板此刻贴着的图标位置(最近一次落在菜单栏里的位置)。
    private var anchor: NSRect?
    /// 这次「展开界面」会话开始的时刻(开机以来的秒数,与事件时间戳同一基准);没有会话为 nil。
    private var sessionBeganAt: TimeInterval?

    init(controller: DisplayController) {
        let model = PanelModel(controller: controller)
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hosting = NSHostingView(rootView: PanelView(model: model))
        // 不激活本 app 的面板:打开时不抢走当前 app 的焦点,面板照样能点、能收 Esc(菜单栏面板的通行做法)。
        panel = PanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "显示器开关")
            if #available(macOS 27.0, *) {
                statusItem.expandedInterfaceDelegate = self
            } else {
                button.target = self
                button.action = #selector(togglePanel(_:))
            }
        }

        panel.contentView = PanelBackground.wrapping(hosting)
        panel.isOpaque = false
        panel.backgroundColor = .clear      // 圆角之外透明;面板的底是系统材质(见 PanelBackground)
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
            self?.dismiss()
        })
        // 内容变了(屏数增减)就按新尺寸重新摆放。
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
        if let icon = iconFrame(), menuBarScreen(of: icon) != nil { showPanel(); return }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showPanelWhenReady(attemptsLeft: attemptsLeft - 1)
        }
    }

    func showPanel() {
        // 每次打开都重新读系统真相(面板开着时另由屏幕参数变化通知刷新)。
        model.reload()
        model.refreshDriverHealth()
        isOpen = true
        if !panel.isVisible { panel.alphaValue = 0 }
        placePanel()        // 贴到图标下并显示
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }

    /// 立刻完整显示,不渐显:Wi-Fi 菜单打开时前一帧还没有、下一帧就是完整的(60 帧录屏逐帧看,2026-10-23)。
    /// 曾渐显 0.12 秒。用一次 0 秒的动画来设,正在渐隐时再打开,能把那段渐隐一并替掉。
    private func reveal() {
        guard !revealed else { return }
        revealed = true
        panel.ignoresMouseEvents = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    /// 立刻藏起(逻辑上仍开着):面板此刻在错的位置,不能让它在那里多停一帧。
    private func conceal() {
        revealed = false
        anchor = nil
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
    }

    /// 我们这边要收起面板(点外面、按 Esc、切到别的 app、图标一直没落进菜单栏)。
    /// 有会话时先取消它,系统随即回调 `statusItemDidEndExpandedInterfaceSession`,在那里收起;
    /// 没有会话(更早的系统,或用 `--show-panel` 启动时弹的那一次)就直接收起。
    private func dismiss() {
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
            return
        }
        closePanel()
    }

    /// 收起:渐隐约 0.12 秒、匀速,同 Wi-Fi 菜单(录屏逐帧:每帧透明度降得差不多,约 7 帧降到 0)。
    /// 曾是 0.1 秒、先慢后快。`animated` 为假(系统要求立即收起)时直接藏起。
    private func closePanel(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        revealed = false
        sessionBeganAt = nil
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        guard animated else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().alphaValue = 0
            }
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .linear)
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
        // 菜单栏图标由系统的菜单栏进程托管,点图标对我们来说也是「外面」的点击,要单独看:
        // - 没有会话(更早的系统):交给图标的点击动作去开关。若在这里收起,点击动作紧接着又把面板打开,
        //   看上去就是「再点图标收不起来」(他实测)。
        // - 有会话:会话开着时再点图标,系统什么都不做——不结束会话,也不回调(实测),由我们收起。
        //   打开面板的那一下点击,系统处理完(开了会话)才转到这里;它按下的时刻早于会话开始,不算。
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return }
            if let icon = self.iconFrame(), icon.contains(NSEvent.mouseLocation) {
                if let began = self.sessionBeganAt, event.timestamp > began { self.dismiss() }
                return
            }
            self.dismiss()
        }) {
            eventMonitors.append(m)
        }
        // Esc 收起。只在本 app 收得到按键时有效:面板不激活本 app,别的 app 在前台时,
        // 系统把 Esc 交给那个 app,这里收不到(实测,有没有会话都一样)。
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }) {
            eventMonitors.append(m)
        }
    }

    /// 菜单栏图标所在窗口的位置;刚启动时尺寸还是 0(实测 40×0),返回 nil。
    private func iconFrame() -> NSRect? {
        guard let frame = statusItem.button?.window?.frame, frame.height > 0 else { return nil }
        return frame
    }

    /// 图标正处在哪块屏的菜单栏里:中心落在该屏顶端、与图标等高的那一条里(图标窗口与菜单栏等高)。
    /// 不在任何菜单栏里返回 nil——那是图标搬家途中的过渡位置,没有东西画在那里。
    private func menuBarScreen(of icon: NSRect) -> NSScreen? {
        NSScreen.screens.first { s in
            icon.midX >= s.frame.minX && icon.midX < s.frame.maxX
                && icon.midY >= s.frame.maxY - icon.height && icon.midY <= s.frame.maxY
        }
    }

    /// 把面板贴在图标下方,位置照菜单栏 Wi-Fi 菜单(macOS 27 实测,2026-10-23):左缘对齐图标的高亮底
    /// (即图标窗口的左缘),上缘贴着菜单栏下沿;超出屏幕边缘时往里收。
    /// 曾照 AppKit 系统菜单(弹一个临时状态栏菜单实测)左偏 5pt、比图标下沿再低 2pt——Wi-Fi 等控制中心那一套
    /// 不是这样,面板因此比 Wi-Fi 菜单低了 4pt。
    ///
    /// **面板只跟着真正落在菜单栏里的图标走,且直接就位、不做跟随动画**:图标在菜单栏里挪一次
    /// (菜单栏重排时会连挪几次,实测 1559→1376),面板同一时刻挪到同一处,看上去与图标是一体的。
    /// 曾给同屏挪动加过 0.16 秒的平滑,面板总是慢半拍、从上一个位置滑过去(2026-10-22)。
    ///
    /// 图标窗口报出的位置不全是图标真在的地方(录屏 + 日志逐帧核对,2026-10-22):
    /// - 关掉一块非主屏时,它会报一个低 30pt 的位置,约 1 毫秒后回原处;图标本身没动。
    ///   这时上次贴的位置仍在菜单栏里,面板原地不动——照着贴就是整块面板往下闪一帧。
    /// - 主屏切换时系统按新主屏重算全局坐标,面板与图标的数值不变、实际却落到了新主屏的
    ///   左中部;约 0.5 秒后图标才经新屏左上角外的占位点 `(0, 1080)` 落进新菜单栏。
    ///   这时上次贴的位置已不在任何菜单栏里,面板立刻藏起,等图标落定再在它下面显示——
    ///   照着贴或原地不动,都是先停在别处、再跳(或飘)到图标下(他看到的「从左上角飘过去」)。
    private func placePanel() {
        guard isOpen, let icon = iconFrame() else { return }
        guard let screen = menuBarScreen(of: icon) else {
            if let anchor, menuBarScreen(of: anchor) != nil { return }
            conceal()
            return
        }
        let size = hosting.fittingSize
        var x = icon.minX
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let frame = NSRect(x: x, y: menuBarBottom(of: screen, icon: icon) - size.height, width: size.width, height: size.height)
        anchor = icon
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        reveal()
    }

    /// 菜单栏下沿:这块屏可见区域的上缘(实测 30pt 高的菜单栏,正是 Wi-Fi 菜单上缘所在)。
    /// 图标窗口上下各比菜单栏多出 1~2pt(实测 33pt 高),按钮下沿又比菜单栏下沿高 0.5pt,都不能直接拿来当下沿。
    /// 菜单栏设为自动隐藏时可见区域顶到屏幕上缘,退回按图标窗口的下沿。
    private func menuBarBottom(of screen: NSScreen, icon: NSRect) -> CGFloat {
        let top = screen.visibleFrame.maxY
        return top < screen.frame.maxY ? top : icon.minY
    }

    /// 主屏刚变时图标正在搬家,通知不一定每一步都有;隔一会儿再对一次位置,最多 2 秒。
    private func placePanelWhenIconReady(attemptsLeft: Int = 10) {
        placePanel()
        guard attemptsLeft > 0 else {
            // 2 秒后图标仍没落进菜单栏(如菜单栏被设为自动隐藏):不能一直隐身开着,收起。
            if isOpen, !revealed { dismiss() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.placePanelWhenIconReady(attemptsLeft: attemptsLeft - 1)
        }
    }
}

/// 系统的「展开界面」会话:用户点图标时系统开会话,我们弹面板;会话结束(再点图标、点了别的菜单栏图标,
/// 或我们自己取消)时收起。
@available(macOS 27.0, *)
extension StatusPanelController: NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        sessionBeganAt = ProcessInfo.processInfo.systemUptime
        showPanel()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        closePanel(animated: animated)
    }
}

/// 无边框窗口默认当不了当前窗口;面板里要能点、要能收 Esc,所以放开。
private final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
