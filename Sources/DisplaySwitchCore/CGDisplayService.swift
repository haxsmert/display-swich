import CoreGraphics
import ColorSync
import AppKit
import IOKit
import IOKit.ps

/// SystemDisplayService 的真实实现。封装 CoreGraphics 枚举、私有断开符号、内建屏检测。
public final class CGDisplayService: SystemDisplayService {
    private typealias ConfigEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let cgsConfigureDisplayEnabled: ConfigEnabledFn?

    public init() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        let sym = dlsym(handle, "CGSConfigureDisplayEnabled")
        cgsConfigureDisplayEnabled = sym.map { unsafeBitCast($0, to: ConfigEnabledFn.self) }
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

    /// 物理连接着的外接屏数量。取自 IOKit 的 framebuffer 节点:`external` + 已建立 `Transport`
    /// + 带 `DisplayWidth`(链路那头确实挂着屏)。
    ///
    /// 实测依据(M 系列 · macOS 26):同一块外接屏,软件关掉后 IOKit 仍报 1 条连接、
    /// 物理拔线后报 0 条;而 CoreGraphics 在这两种情况下的表现完全一致,无从区分。
    public func physicalExternalCount() -> Int? {
        var iter: io_iterator_t = 0
        // 查询失败一律返回 nil(不是 0):0 会被对账当成「屏全拔了」而清空记录,
        // 把用户还连着、只是被软件关掉的屏误删——查不到时宁可什么都不做。
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOMobileFramebufferShim"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var count = 0
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            let props = Self.properties(of: svc)
            // 三个条件缺一不可:
            //   external     —— 是外接口,不是内建屏;
            //   Transport    —— 这个口已经建立链路(空闲口没有这个键);
            //   DisplayWidth —— 链路那头确实挂着一块屏(拔线后此键消失)。
            //
            // ⚠️ 不能按 IOMFBUUID 去重:实测它是显示协处理器实例的 UUID,
            // **多块外接屏共享同一个值**,去重会把 N 块屏数成 1 块,
            // 于是对账把用户线还连着的屏当成拔线残留删掉(v1.0.2 的回归就是这么来的)。
            if (props["external"] as? Bool) ?? false,
               props["Transport"] != nil,
               props["DisplayWidth"] != nil {
                count += 1
            }
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
