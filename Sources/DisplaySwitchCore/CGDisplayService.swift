import CoreGraphics
import ColorSync
import AppKit

/// SystemDisplayService 的真实实现。封装 CoreGraphics 枚举、私有断开符号、内建屏检测。
public final class CGDisplayService: SystemDisplayService {
    private typealias ConfigEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let cgsConfigureDisplayEnabled: ConfigEnabledFn?

    public init() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        let sym = dlsym(handle, "CGSConfigureDisplayEnabled")
        cgsConfigureDisplayEnabled = sym.map { unsafeBitCast($0, to: ConfigEnabledFn.self) }
    }

    /// 私有断开符号是否可用;不可用时应禁用开关功能。
    public var isSupported: Bool { cgsConfigureDisplayEnabled != nil }

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
}
