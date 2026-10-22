#!/bin/bash
# 系统升级后的依赖自检。
#
# 为什么需要:本 app 依赖 macOS 私有符号(CGSConfigureDisplayEnabled / CGSGetDisplayList)
# 与 IOKit 内部结构(IOPortTransportState 节点、EDID 键、IOPMrootDomain 的 AppleClamshellState),
# 这些都**不在 Apple 的兼容性承诺内**,系统大版本升级是它们失效的主要风险源。
#
# 关键:本脚本拼接**产品代码本身**来跑,不另写一套检查逻辑——
# 否则验的就不是真实路径了。而且它不只查「符号在不在」,更查「行为对不对」:
# 2026-09-18 的事故正是「符号还在、行为变了」(一个判据从能看到被禁用的屏,变成看不到)。
#
# 用法:bash scripts/selfcheck.sh          (升级后必跑)
#       bash scripts/selfcheck.sh --plug   (再加一项动手检查:按提示拔掉一块外接屏)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat "$ROOT"/Sources/DisplaySwitchCore/*.swift > "$TMP/check.swift"
cat >> "$TMP/check.swift" <<'EOF'

import Foundation
// 输出重定向到文件时也要逐行落地:动手检查的提示必须即时可见。
setvbuf(stdout, nil, _IOLBF, 0)
var fail = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("  \(ok ? "✅" : "❌") \(name)\(detail.isEmpty ? "" : "  → \(detail)")")
    if !ok { fail += 1 }
}
print("系统:\(ProcessInfo.processInfo.operatingSystemVersionString)\n")

print("【私有符号】不在 Apple 兼容性承诺内,升级后最可能消失")
let h = UnsafeMutableRawPointer(bitPattern: -2)
for sym in ["CGSConfigureDisplayEnabled", "CGSGetDisplayList"] { check(sym, dlsym(h, sym) != nil) }

print("\n【IOKit 类名】")
func nodeCount(_ cls: String) -> Int {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &it) == KERN_SUCCESS else { return -1 }
    defer { IOObjectRelease(it) }
    var n = 0, s = IOIteratorNext(it)
    while s != 0 { n += 1; IOObjectRelease(s); s = IOIteratorNext(it) }
    return n
}
let tp = nodeCount("IOPortTransportState"), pm = nodeCount("IOPMrootDomain")
check("IOPortTransportState", tp > 0, "\(tp) 个节点")
check("IOPMrootDomain", pm > 0, "\(pm) 个节点")

print("\n【属性键 + 行为】符号在 ≠ 行为对,这里查的是行为")
let svc = CGDisplayService()
check("AppleClamshellState 可读", svc.isClamshellClosed() != nil, "盖子合着=\(String(describing: svc.isClamshellClosed()))")
let live = svc.liveExternalCount() ?? -1
check("EDID 键仍能数出外接屏", live >= 0, "带 EDID 的节点=\(live) \(svc.liveExternalPorts() ?? [])")
check("isSupported", svc.isSupported)
let activeExt = svc.activeDisplays().filter { !$0.isBuiltin }.count
check("物理外接屏数 ≥ 活跃外接屏数", live >= activeExt, "物理=\(live) 活跃外接=\(activeExt)")
// 跑自检时人就在屏幕前,屏幕必然醒着。误判成睡眠是危险方向:拔线瞬间的救援会被推迟到
// 一次不会来的唤醒。睡眠时判为「睡」、唤醒通知那一刻已判为「醒」,2026-09-29 已在真机实测。
let asleep = svc.isDisplaySystemAsleep()
check("屏幕醒着时不判为睡眠", asleep != true, "判定=\(asleep.map { $0 ? "睡" : "醒" } ?? "查不到")")
let inactive = svc.inactiveDisplayIDs()
check("CGSGetDisplayList 能枚举被禁用的屏", inactive != nil, "未点亮 ID=\(inactive.map(String.init(describing:)) ?? "nil")")

let ctrl = DisplayController(service: svc)
let items = ctrl.menuItems()
check("菜单能渲染", !items.isEmpty, "\(items.count) 项")
for i in items { print("       \(i.isOn ? "✓" : " ") \(i.label)") }
check("无关闭记录时不误救援", ctrl.needsBlackoutRescue() == false)

// 可选的动手检查(bash scripts/selfcheck.sh --plug):拔线通知依赖系统驱动的内部行为——
// 拓展坞靠「节点被销毁」,机身 HDMI 靠「节点被重新登记」(2026-09-29 实测)。
// 这类行为升级后可能悄悄变掉,又只能靠真的拔一次线来验,所以做成可选项,升级后跑一次。
if CommandLine.arguments.contains("--plug") {
    let before = svc.liveExternalCount() ?? -1
    print("\n【拔线通知】需要动手:当前外接屏 \(before) 块,请在 60 秒内拔掉其中一块(HDMI 或拓展坞均可)……")
    var atNotice: Int?
    var kind = ""
    svc.observeDisplayDisconnect { signal in
        // 通知也会因插线、充电等别的变化而来;只认「到达这一刻计数已经减少」的那一次。
        if atNotice == nil, let now = svc.liveExternalCount(), now < before { atNotice = now; kind = signal.logText }
    }
    let deadline = Date().addingTimeInterval(60)
    while atNotice == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    check("拔线通知到达,且到达时计数已减少", before > 0 && atNotice != nil,
          "拔线前=\(before) 通知时=\(atNotice.map { "\($0)(\(kind))" } ?? "60 秒内没等到")")
}

print("\n【AppKit 通知名】")
check("didWakeNotification", !NSWorkspace.didWakeNotification.rawValue.isEmpty)
check("screensDidWakeNotification", !NSWorkspace.screensDidWakeNotification.rawValue.isEmpty)

print("\n" + (fail == 0 ? "✅ 全部通过" : "❌ \(fail) 项失败 —— 升级破坏了依赖,先修再用"))
exit(fail == 0 ? 0 : 1)
EOF
swift "$TMP/check.swift" "$@"
