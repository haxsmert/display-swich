// 第 2 步:断开 + 自动恢复实测。带多重安全网。
// 安全保证:
//  1) 只动【非主屏】,代码硬校验绝不碰主屏
//  2) 活跃屏少于 2 块时直接拒绝执行
//  3) 断开后固定 6 秒自动恢复,无需人工干预
//  4) atexit / SIGINT / SIGTERM 都挂了恢复兜底,异常退出也会尝试把屏开回来
//  5) 额外调用公开的 CGRestorePermanentDisplayConfiguration() 做二次兜底
import CoreGraphics
import Foundation

let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
typealias ConfigEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
guard let symAddr = dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled") else {
    print("❌ 找不到 CGSConfigureDisplayEnabled,无法继续"); exit(1)
}
let CGSConfigureDisplayEnabled = unsafeBitCast(symAddr, to: ConfigEnabledFn.self)

func activeCount() -> UInt32 {
    var c: UInt32 = 0; CGGetActiveDisplayList(0, nil, &c); return c
}

// 枚举,挑出非主屏作为实验目标
var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
let mainID = CGMainDisplayID()
let originalCount = count

guard count >= 2 else {
    print("⚠️ 安全保护:当前活跃显示器少于 2 块,拒绝执行。"); exit(1)
}
guard let target = ids.first(where: { $0 != mainID }) else {
    print("⚠️ 找不到非主屏,拒绝执行。"); exit(1)
}
if target == mainID { print("⛔ 拒绝:目标竟是主屏,中止。"); exit(1) }

// 全局目标,供 signal/atexit 兜底使用
var gTarget = target

func setEnabled(_ did: CGDirectDisplayID, _ on: Bool) -> CGError {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return .failure }
    let e = CGSConfigureDisplayEnabled(cfg, did, on)
    let c = CGCompleteDisplayConfiguration(cfg, .forSession)
    return (e == .success && c == .success) ? .success : .failure
}

func recover() {
    _ = setEnabled(gTarget, true)
    CGRestorePermanentDisplayConfiguration()
}

atexit { recover() }
signal(SIGINT)  { _ in recover(); _exit(1) }
signal(SIGTERM) { _ in recover(); _exit(1) }

print("目标非主屏 displayID=\(target)（主屏 \(mainID) 绝不动）。当前活跃屏=\(originalCount)")
print(">>> 正在断开副屏...")
let off = setEnabled(target, false)
Thread.sleep(forTimeInterval: 1)
print("断开调用: \(off == .success ? "返回成功" : "返回失败")   断开后活跃屏=\(activeCount())")
print(">>> 6 秒后自动恢复（这期间副屏应变黑、窗口迁移到主屏）...")
Thread.sleep(forTimeInterval: 6)

print(">>> 正在恢复...")
let on = setEnabled(target, true)
CGRestorePermanentDisplayConfiguration()
Thread.sleep(forTimeInterval: 2)
let after = activeCount()
print("恢复调用: \(on == .success ? "返回成功" : "返回失败")   恢复后活跃屏=\(after)")

if after >= originalCount {
    print("\n✅✅ 结论:断开与恢复都成功 —— 纯自研真断开路线在这台机器上可行!")
} else {
    print("\n⚠️ 恢复后活跃屏未回到 \(originalCount),触发二次兜底...")
    recover()
    Thread.sleep(forTimeInterval: 3)
    print("二次兜底后活跃屏=\(activeCount())")
    print("（若仍未恢复:合盖再开 / 睡眠唤醒一次,或拔插一次副屏线即可。配置是会话级的,重启也会恢复。）")
}
