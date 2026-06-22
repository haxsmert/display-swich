import Foundation
// 复用源码:直接把 CGDisplayService 逻辑跑一遍。运行方式见下方命令。
import CoreGraphics

// 最小内联版断开测试,确认 .forAppOnly 是否让断开「全局生效」(活跃屏减少)。
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
typealias Fn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
guard let sym = dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled") else {
    print("符号 CGSConfigureDisplayEnabled 不可用,退出。"); exit(1)
}
let fn = unsafeBitCast(sym, to: Fn.self)

func activeCount() -> UInt32 { var c: UInt32 = 0; CGGetActiveDisplayList(0, nil, &c); return c }
func setEnabled(_ id: CGDirectDisplayID, _ on: Bool, _ opt: CGConfigureOption) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    let e = fn(cfg, id, on)
    return e == .success && CGCompleteDisplayConfiguration(cfg, opt) == .success
}

var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
let main = CGMainDisplayID()
guard count >= 2, let target = ids.first(where: { $0 != main }) else {
    print("需要至少 2 块屏且存在非主屏,跳过。"); exit(0)
}
print("forAppOnly 测试:断开非主屏 \(target),当前活跃=\(count)")
_ = setEnabled(target, false, .forAppOnly)
Thread.sleep(forTimeInterval: 2)
let afterOff = activeCount()
print("断开后活跃=\(afterOff) → \(afterOff < count ? "✅ forAppOnly 全局生效" : "❌ forAppOnly 不生效,需改用 .forSession")")
_ = setEnabled(target, true, .forAppOnly)
CGRestorePermanentDisplayConfiguration()
Thread.sleep(forTimeInterval: 2)
print("恢复后活跃=\(activeCount())")
