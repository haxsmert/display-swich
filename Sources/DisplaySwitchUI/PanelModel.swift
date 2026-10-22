import AppKit
import Combine
import DisplaySwitchCore

/// 面板的数据源。所有文字都由 Core 算好(可单测),这里只负责「什么时候重新读一遍」和转发点击。
public final class PanelModel: ObservableObject {
    @Published public private(set) var items: [DisplayMenuItem] = []
    @Published public private(set) var summary = ""
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
        summary = panelSummary(items)
        supported = controller.isSupported
        lastRescue = lastRescueProvider()
    }

    public func setOn(_ on: Bool, for id: CGDirectDisplayID) {
        guard items.first(where: { $0.id == id })?.isOn != on else { return }
        controller.toggle(id: id)
        reload()
        // 系统应用配置要一点时间(实测 0.1–0.5 秒),晚一点再读一次,让说明行和摘要对上真实状态。
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
