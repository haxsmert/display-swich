// 第 1 步:只读探测。绝不改动任何显示器配置。
// 目的:1) 可靠枚举显示器并分清主/副屏  2) 确认私有符号是否可解析
import CoreGraphics
import ColorSync
import Foundation

// 用 RTLD_DEFAULT 在已加载的框架里查符号是否存在
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
func symbolExists(_ name: String) -> Bool {
    return dlsym(RTLD_DEFAULT, name) != nil
}

print("===== 显示器枚举（公开 API，只读） =====")
var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
print("活跃显示器数量: \(count)")

let mainID = CGMainDisplayID()
for did in ids {
    let isMain = (did == mainID)
    let isBuiltin = CGDisplayIsBuiltin(did) != 0
    let isOnline = CGDisplayIsOnline(did) != 0
    let isActive = CGDisplayIsActive(did) != 0
    let w = CGDisplayPixelsWide(did)
    let h = CGDisplayPixelsHigh(did)
    let vendor = CGDisplayVendorNumber(did)
    let model = CGDisplayModelNumber(did)
    let serial = CGDisplaySerialNumber(did)
    var uuidStr = "n/a"
    if let uuidRef = CGDisplayCreateUUIDFromDisplayID(did)?.takeRetainedValue() {
        uuidStr = CFUUIDCreateString(nil, uuidRef) as String? ?? "n/a"
    }
    print("""
    -----
    displayID   : \(did)
    主屏        : \(isMain ? "✅ 是（不会动它）" : "否")
    内建屏      : \(isBuiltin)
    online      : \(isOnline)   active: \(isActive)
    分辨率      : \(w) x \(h)
    vendor/model: \(vendor) / \(model)   serial: \(serial)
    UUID        : \(uuidStr)
    """)
}

print("\n===== 私有符号探测（只读，不调用） =====")
let candidates = [
    "CGSConfigureDisplayEnabled",   // displayplacer 用的断开符号（CGS 前缀）
    "SLSConfigureDisplayEnabled",   // SkyLight 新前缀的同名候选
    "CGSGetDisplayList",
    "SLSGetDisplayList",
    "CGCompleteDisplayConfiguration",   // 公开，应存在（对照基准）
    "CGBeginDisplayConfiguration",      // 公开，应存在（对照基准）
    "CGRestorePermanentDisplayConfiguration", // 公开恢复兜底
    "CGSGetDisplayConfiguration",
]
for sym in candidates {
    print(String(format: "  %-38@ : %@", sym as NSString, symbolExists(sym) ? "✅ 找到" : "❌ 没有"))
}

print("\n探测完成。本步骤未对显示器做任何更改。")
