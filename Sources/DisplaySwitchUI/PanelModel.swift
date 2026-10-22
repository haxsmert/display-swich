import AppKit
import Combine
import DisplaySwitchCore


/// 面板的数据源。所有文字都由 Core 算好(可单测),这里只负责「什么时候重新读一遍」和转发点击。
public final class PanelModel: ObservableObject {
    @Published public private(set) var items: [DisplayMenuItem] = []
    /// 顶部提示区的话,见 `panelHint`。
    @Published public private(set) var hint: String?
    /// 点了被锁住那一行的次数。每多一次,界面就让锁形图标与顶部提示抖一下:
    /// 锁住后再点要有反应(他的要求),否则看上去像点了没反应。
    @Published public private(set) var lockedTaps = 0
    @Published public private(set) var supported = true
    @Published public private(set) var lastRescue: Date?

    private let controller: DisplayController
    private let lastRescueProvider: () -> Date?
    private let bundleVersion: String?
    private var screenObserver: NSObjectProtocol?

    /// `lastRescueProvider` 与 `version` 默认读真实日志与 app 版本;截图工具传固定值,画面才可复现。
    public init(controller: DisplayController,
                lastRescueProvider: @escaping () -> Date? = RescueLog.lastRescueDate,
                version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) {
        self.controller = controller
        self.lastRescueProvider = lastRescueProvider
        self.bundleVersion = version
        // 屏幕增减、开关、改分辨率时系统都会发这条通知;面板开着时据此刷新,不轮询。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reload() }
        reload()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    public func reload() {
        items = controller.menuItems()
        hint = panelHint(items)
        supported = controller.isSupported
        lastRescue = lastRescueProvider()
    }

    /// 切换一块屏:开着就关、关着就开。**方向不由界面给**——由 Core 按系统真实状态当场决定。
    /// 曾用系统开关控件把「目标值」传进来,实测它自己记的状态会落后一步,打开面板后第一下
    /// 传回的总是当前值,于是第一下没反应(2026-10-22)。界面不保存任何开关状态,就不会再错位。
    public func toggle(_ id: CGDirectDisplayID) {
        let done = controller.toggle(id: id)
        reload()
        guard done else {
            // 没切成、而这块屏正被锁住:是点了被锁住的那一行(切不切由 Core 定,这里只认结果)。
            if items.first(where: { $0.id == id })?.lockReason != nil { lockedTaps += 1 }
            return
        }
        // 系统应用配置要一点时间(实测 0.1–0.5 秒),晚一点再读一次,让说明行和顶部提示对上真实状态。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.reload() }
    }

    /// 菜单底部显示的版本,取自 app bundle 的 Info.plist。
    /// 直接 `swift run` 起的开发构建没有 bundle 版本号,显示「开发构建」而不是编个假版本。
    public var versionText: String {
        guard let v = bundleVersion, !v.isEmpty else { return "开发构建" }
        return "版本 \(v)"
    }

    public func openRepository() {
        if let url = URL(string: "https://github.com/haxsmert/display-swich") { NSWorkspace.shared.open(url) }
    }

    public func openRescueLog() { NSWorkspace.shared.open(RescueLog.url) }

    public func quit() { NSApp.terminate(nil) }
}
