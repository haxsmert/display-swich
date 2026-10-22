import CoreGraphics
import ColorSync
import AppKit
import IOKit
import IOKit.ps

/// SystemDisplayService 的真实实现。封装 CoreGraphics 枚举、私有断开符号、内建屏检测。
public final class CGDisplayService: SystemDisplayService {
    private typealias ConfigEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    /// `CGSGetDisplayList(maxCount, outIDs, outCount)` —— 列出所有显示器,**包含被禁用的**。
    private typealias GetDisplayListFn =
        @convention(c) (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private let cgsConfigureDisplayEnabled: ConfigEnabledFn?
    private let cgsGetDisplayList: GetDisplayListFn?

    public init() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        let sym = dlsym(handle, "CGSConfigureDisplayEnabled")
        cgsConfigureDisplayEnabled = sym.map { unsafeBitCast($0, to: ConfigEnabledFn.self) }
        let listSym = dlsym(handle, "CGSGetDisplayList")
        cgsGetDisplayList = listSym.map { unsafeBitCast($0, to: GetDisplayListFn.self) }
    }

    /// 见协议注释:直接问系统要「存在但未点亮」的屏,不依赖任何记账。
    public func inactiveDisplayIDs() -> [CGDirectDisplayID]? {
        guard let fn = cgsGetDisplayList else { return nil }
        var count: UInt32 = 0
        guard fn(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard fn(count, &ids, &count) == .success else { return nil }
        // 合盖时内建屏本来就不活跃,那是正常状态而非「被关着」;
        // 且此刻对它调点亮会阻塞约 20 秒(实测),必须排除。
        let lidClosed = (isClamshellClosed() == true)
        return ids.prefix(Int(count)).filter { id in
            guard CGDisplayIsActive(id) == 0 else { return false }
            return !(lidClosed && CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// 是否支持显示器开关:私有符号可用 **且** 运行在 Apple Silicon 硬件上。
    /// 「真·断开」仅在 Apple Silicon 验证过;Intel 上该路径未验证、可能不可逆,故一律判不支持 → 只读不动屏。
    public var isSupported: Bool { cgsConfigureDisplayEnabled != nil && Self.isAppleSilicon() }

    /// 是否运行在 Apple Silicon 硬件上(`hw.optional.arm64 == 1`;Intel 上为 0 或查询失败)。
    /// 注:本 app 实为 arm64-only,Intel 上根本无法启动;此自检是显式契约 + 防未来打成 universal。
    private static func isAppleSilicon() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return ok == 0 && value == 1
    }

    public func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let mainID = CGMainDisplayID()
        return ids.map { id in
            DisplayInfo(
                id: id,
                uuid: Self.uuid(for: id),
                name: Self.name(for: id),
                bounds: CGDisplayBounds(id),
                isMain: id == mainID,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isActive: true
            )
        }
    }

    public func hasBuiltInDisplay() -> Bool {
        // 1) 在线列表里有内建屏 → 有。
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        if count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetOnlineDisplayList(count, &ids, &count)
            if ids.contains(where: { CGDisplayIsBuiltin($0) != 0 }) { return true }
        }
        // 2) 便携机(有内建电池)→ 有内建屏(合盖时内建屏不在在线列表)。
        // 3) 都不满足 → 保守判定为「无内建屏」(宁可禁止全关,不冒险)。
        return Self.hasInternalBattery()
    }

    /// 见协议注释:本 app 唯一的物理连接真相(带 EDID 的传输节点)。
    /// 数 `IOPortTransportState`(基类,涵盖 DisplayPort / HDMI 等)下**带 EDID** 的节点——
    /// 每块实际连着的屏一个。拔线时:经拓展坞的屏,节点被内核当场销毁,与终止通知同步;
    /// 机身 HDMI 口的节点常驻,拔线只去掉它的 EDID(2026-09-29 实测),计数照样归零,但不产生终止通知。
    public func liveExternalCount() -> Int? { liveExternalPorts()?.count }

    /// 见协议注释。与 `liveExternalCount` 同源——计数就是这份列表的长度,两者不可能对不上。
    public func liveExternalPorts() -> [String]? {
        var iter: io_iterator_t = 0
        // 查不到返回 nil 而不是空列表:绝不让「查询失败」被当成「屏拔光了」。
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOPortTransportState"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var ports: [String] = []
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            let props = Self.properties(of: svc)
            if props["EDID"] != nil { ports.append(props["TransportDescription"] as? String ?? "未知接口") }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return ports.sorted()
    }

    private static func properties(of service: io_object_t) -> [String: Any] {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dict
    }

    // MARK: - 拔线的内核事件监听

    private var notificationPort: IONotificationPortRef?
    private var terminationIterator: io_iterator_t = 0
    private var reregistrationIterator: io_iterator_t = 0
    private var disconnectHandler: ((DisplayDisconnectSignal) -> Void)?

    /// 在 `IOPortTransportState`(基类)上挂**两种**内核通知,零轮询,共用同一个回调:
    ///   ① **终止**:经拓展坞(USB-C / 雷雳)接的屏,拔线时它的传输节点被内核销毁,终止通知会来。
    ///      实测:未接屏时该类下带 EDID 的节点为 0 个,接两块外接屏后为 2 个,各带该屏的 EDID。
    ///   ② **重新登记**(`kIOMatchedNotification`):机身 HDMI 口的节点**常驻**,拔线不销毁它,
    ///      ① 永远不会发;驱动只是把它改为未激活、去掉 EDID,然后重新登记这个节点,于是匹配通知再来一次。
    ///      实测(2026-09-29,两轮拔 HDMI):每轮拔出各来一次,排在这一串事件的最后,
    ///      到达时 EDID 已去掉、计数已归零——判据当场就准。
    ///   拓展坞拔线时 ② 也会来,而且可能先于 ①(2026-10-22 实测:最先到、且判据已归零的是 ②)。
    /// 两种谁先到都不影响救援:判据看的是到达那一刻的物理计数,不看是哪种通知。
    /// ② 在插线、以及其他端口(充电、SD 卡等)状态变化时也会来;回调只负责「叫醒」,
    /// 判断交给救援判据,无需救援时完全静默,所以多来几次无害。
    public func observeDisplayDisconnect(_ handler: @escaping (DisplayDisconnectSignal) -> Void) {
        disconnectHandler = handler
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        // 回调派发到主队列:救援要动显示配置,必须在主线程,也便于与菜单逻辑共用同一串行上下文。
        IONotificationPortSetDispatchQueue(port, .main)

        // 两种通知各用一个回调,只为让日志记下是哪一种触发的;C 函数指针不能捕获变量,所以写成两个。
        let onTerminated: IOServiceMatchingCallback = { context, iterator in
            CGDisplayService.drainAndNotify(context, iterator, .nodeTerminated)
        }
        let onReregistered: IOServiceMatchingCallback = { context, iterator in
            CGDisplayService.drainAndNotify(context, iterator, .nodeReregistered)
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // 每次注册都要一份新的匹配字典:IOServiceAddMatchingNotification 会消耗掉它。
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                         IOServiceMatching("IOPortTransportState"),
                                         onTerminated, context, &terminationIterator)
        IOServiceAddMatchingNotification(port, kIOMatchedNotification,
                                         IOServiceMatching("IOPortTransportState"),
                                         onReregistered, context, &reregistrationIterator)
        // 注册后先排空一次:这是 IOKit 要求的「武装」动作,不做则一条通知都收不到。
        // 匹配通知的迭代器此刻装着所有现存节点,排空时**不**调回调——那不是任何变化。
        for iterator in [terminationIterator, reregistrationIterator] {
            var svc = IOIteratorNext(iterator)
            while svc != 0 { IOObjectRelease(svc); svc = IOIteratorNext(iterator) }
        }
    }

    private static func drainAndNotify(_ context: UnsafeMutableRawPointer?, _ iterator: io_iterator_t,
                                       _ signal: DisplayDisconnectSignal) {
        // 迭代器**必须排空**,否则内核不再派发后续通知(IOKit 的硬性约定)。
        var found = false
        var svc = IOIteratorNext(iterator)
        while svc != 0 { found = true; IOObjectRelease(svc); svc = IOIteratorNext(iterator) }
        guard found, let context else { return }
        Unmanaged<CGDisplayService>.fromOpaque(context).takeUnretainedValue().disconnectHandler?(signal)
    }

    // MARK: - 盖子:开盖是内建屏重新可用的唯一时刻

    private var lidPort: IONotificationPortRef?
    private var lidIterator: io_object_t = 0
    private var builtInAvailableHandler: (() -> Void)?
    private var lidEdge = LidEdgeDetector(initiallyClosed: false)

    /// 见协议注释。读 `IOPMrootDomain` 的 `AppleClamshellState`。
    public func isClamshellClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                          kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool else { return nil }
        return value
    }

    /// 见协议注释。问 WindowServer 自己:在线的屏**全部**报睡眠才算睡眠,列表为空则判断不了。
    ///
    /// 为什么是「全部」:两种误判代价不对称。误判成睡眠,会把拔线那一刻的救援推迟到
    /// 一次可能永远不来的唤醒;误判成醒着,只是退回旧行为(空等约 10 秒后失败)。
    /// 为什么看在线列表:被本 app 关掉的屏不在其中,在列表里的正是此刻由 WindowServer 驱动的屏。
    public func isDisplaySystemAsleep() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success, count > 0 else { return nil }
        return ids.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }

    /// 见协议注释。**两条路都挂上**,因为开盖会走哪一条取决于系统当时睡没睡:
    ///   ① `NSWorkspace` 的唤醒通知——合盖导致睡眠(实测本机 `AppleClamshellCausesSleep = Yes`)后,
    ///      开盖是「唤醒」,走这条;
    ///   ② `IOPMrootDomain` 的属性变化——系统没睡(如仍接着电源)时开盖只是属性变了,走这条。
    /// 两条都可能空炮或重复触发,故 handler 必须幂等、且在无需救援时完全静默。
    public func observeBuiltInMayBecomeAvailable(_ handler: @escaping () -> Void) {
        builtInAvailableHandler = handler

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        }

        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        lidPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        // 注册那一刻的盖子状态作为比较基线。
        lidEdge = LidEdgeDetector(initiallyClosed: isClamshellClosed() ?? false)
        let callback: IOServiceInterestCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<CGDisplayService>.fromOpaque(context).takeUnretainedValue().lidStateMayHaveChanged()
        }
        IOServiceAddInterestNotification(port, root, kIOGeneralInterest, callback,
                                         Unmanaged.passUnretained(self).toOpaque(), &lidIterator)
    }

    /// `IOPMrootDomain` 的电源通知抵达。**只有盖子刚刚打开才往上报**。
    ///
    /// 这个过滤必须做在这一层:该通知是「电源状态变了」而不是「盖子开了」,合盖期间会持续派发,
    /// 而合盖期间的结论恒定不变(内建屏不可用)。若每条都往上抛,上层就要反复查 IOKit、
    /// 反复算判据、反复写日志,答案却从头到尾一样——那是纯粹的浪费,实测一分半钟就抛了二十多条。
    private func lidStateMayHaveChanged() {
        guard lidEdge.didOpen(nowClosed: isClamshellClosed() ?? false) else { return }
        builtInAvailableHandler?()
    }

    public func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        guard let fn = cgsConfigureDisplayEnabled else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        let e = fn(cfg, id, on)
        guard e == .success else {
            CGCancelDisplayConfiguration(cfg)
            return false
        }
        // 首选 .forAppOnly:进程退出由系统自动回滚,天然防死锁。
        // 若 Step 2 实测断开不全局生效,改成 .forSession(见 Step 3 兜底)。
        return CGCompleteDisplayConfiguration(cfg, .forAppOnly) == .success
    }

    private static func uuid(for id: CGDirectDisplayID) -> String {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, ref) as String? ?? ""
    }

    private static func name(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? CGDirectDisplayID, num == id {
                return screen.localizedName
            }
        }
        return ""
    }

    /// 是否有内建电池 → 便携机的代理判定(笔记本必有内建屏;iMac 无电池但内建屏恒亮,
    /// 由「至少留一块活跃屏」自然覆盖,故按无内建屏处理也安全)。
    private static func hasInternalBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
               let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }
}
