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
    /// 每块实际连着的屏一个,拔线时内核当场销毁,与终止通知同步。
    public func liveExternalCount() -> Int? {
        var iter: io_iterator_t = 0
        // 查不到返回 nil 而不是 0:绝不让「查询失败」被当成「屏拔光了」。
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOPortTransportState"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var count = 0
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            if Self.properties(of: svc)["EDID"] != nil { count += 1 }
            IOObjectRelease(svc)
            svc = IOIteratorNext(iter)
        }
        return count
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
    private var disconnectHandler: (() -> Void)?

    /// 挂到 `IOPortTransportState`(基类,一并覆盖 DisplayPort 与 HDMI 等传输类型)的终止通知上。
    /// 拔线时该类下「每块实际连着的屏一个」的节点会被内核销毁,通知随即到达——零轮询。
    /// 实测:未接屏时该类下带 EDID 的节点为 0 个,接两块外接屏后为 2 个,各带该屏的 EDID。
    public func observeDisplayDisconnect(_ handler: @escaping () -> Void) {
        disconnectHandler = handler
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        // 回调派发到主队列:救援要动显示配置,必须在主线程,也便于与菜单逻辑共用同一串行上下文。
        IONotificationPortSetDispatchQueue(port, .main)

        let callback: IOServiceMatchingCallback = { context, iterator in
            // 迭代器**必须排空**,否则内核不再派发后续通知(IOKit 的硬性约定)。
            var found = false
            var svc = IOIteratorNext(iterator)
            while svc != 0 { found = true; IOObjectRelease(svc); svc = IOIteratorNext(iterator) }
            guard found, let context else { return }
            Unmanaged<CGDisplayService>.fromOpaque(context).takeUnretainedValue().disconnectHandler?()
        }
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                         IOServiceMatching("IOPortTransportState"),
                                         callback,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &terminationIterator)
        // 注册后先排空一次:这是 IOKit 要求的「武装」动作,不做则一条通知都收不到。
        var svc = IOIteratorNext(terminationIterator)
        while svc != 0 { IOObjectRelease(svc); svc = IOIteratorNext(terminationIterator) }
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
