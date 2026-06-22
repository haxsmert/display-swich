import Testing
import CoreGraphics
@testable import DisplaySwitchCore

/// 可控的假系统服务:维护一份「全集」与「当前活跃」,模拟开关后的活跃变化。
final class MockService: SystemDisplayService {
    private var known: [CGDirectDisplayID: DisplayInfo]
    private var activeIDs: Set<CGDirectDisplayID>
    var setResult = true
    var supported = true
    var hasBuiltIn = false
    private(set) var setCalls: [(id: CGDirectDisplayID, on: Bool)] = []

    init(all: [DisplayInfo]) {
        known = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        activeIDs = Set(all.filter { $0.isActive }.map { $0.id })
    }

    var isSupported: Bool { supported }
    func hasBuiltInDisplay() -> Bool { hasBuiltIn }

    func activeDisplays() -> [DisplayInfo] {
        known.values
            .filter { activeIDs.contains($0.id) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }

    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        setCalls.append((id, on))
        guard setResult else { return false }
        if on {
            activeIDs.insert(id)
        } else {
            activeIDs.remove(id)
            // 模拟 macOS:关掉主屏后,主屏角色转移给剩余的第一个活跃屏
            if known[id]?.isMain == true, let next = activeIDs.sorted().first, let info = known[next] {
                known[id] = withMain(known[id]!, false)
                known[next] = withMain(info, true)
            }
        }
        return true
    }

    private func withMain(_ d: DisplayInfo, _ isMain: Bool) -> DisplayInfo {
        DisplayInfo(id: d.id, uuid: d.uuid, name: d.name, bounds: d.bounds,
                    isMain: isMain, isBuiltin: d.isBuiltin, isActive: d.isActive)
    }

    /// 模拟「系统在 app 之外把某块屏重新点亮」(远程会话重配置 / 睡眠唤醒 / 重新插拔),
    /// 不经过 app 的 toggle —— 这是真机上 disabled 状态变陈旧的来源。
    func externallyReactivate(_ id: CGDirectDisplayID) {
        activeIDs.insert(id)
    }
}

private func twoExternals() -> [DisplayInfo] {
    [makeInfo(id: 2, main: true, x: 0), makeInfo(id: 3, x: 1920)]
}

@Test("关闭一块外接屏会调用 setEnabled(false) 并记入已关闭")
func toggleOffRecordsDisabled() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 3) == true)
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == false })
    let item = ctrl.menuItems().first { $0.id == 3 }
    #expect(item?.isOn == false)
}

@Test("唯一活跃屏时 toggle 关闭被拒绝,不调用 setEnabled")
func toggleOffLastActiveRejected() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)])
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 2) == false)
    #expect(svc.setCalls.isEmpty)
}

@Test("内建屏可被关闭(两块里关内建那块成功)")
func toggleOffBuiltinWhenNotLast() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true), makeInfo(id: 2, x: 0)])
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 1) == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == false })
}

@Test("重新打开已关闭的屏会调用 setEnabled(true) 并移出已关闭")
func toggleOnRestores() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)              // 关
    #expect(ctrl.toggle(id: 3) == true) // 开
    #expect(svc.setCalls.last?.on == true)
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == true)
}

@Test("menuItems 合并活跃与已关闭,均出现")
func menuItemsMergeActiveAndDisabled() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3) // 关掉 3
    let items = ctrl.menuItems()
    #expect(items.count == 2)
    #expect(items.first { $0.id == 2 }?.isOn == true)
    #expect(items.first { $0.id == 3 }?.isOn == false)
}

@Test("restoreAll 把所有已关闭的屏重新打开并清空")
func restoreAllReenables() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)
    ctrl.restoreAll()
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == true })
    #expect(ctrl.menuItems().allSatisfy { $0.isOn })
}

@Test("唯一活跃屏的菜单项 canToggleOff 为 false")
func canToggleOffFalseForLastActive() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)])
    let ctrl = DisplayController(service: svc)
    let item = ctrl.menuItems().first { $0.id == 2 }
    #expect(item?.canToggleOff == false)
    #expect(item?.isOn == true)
}

@Test("私有符号缺失时 toggle 被拒绝,不调用 setEnabled")
func toggleRejectedWhenUnsupported() {
    let svc = MockService(all: twoExternals())
    svc.supported = false
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.isSupported == false)
    #expect(ctrl.toggle(id: 3) == false)
    #expect(svc.setCalls.isEmpty)
}

@Test("私有符号缺失时 menuItems 各项 canToggleOff 均为 false")
func menuItemsNotToggleableWhenUnsupported() {
    let svc = MockService(all: twoExternals())
    svc.supported = false
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.menuItems().allSatisfy { $0.canToggleOff == false })
}

@Test("有内建屏的机器(笔记本合盖):允许关最后一块外接屏(开盖可恢复内建)")
func laptopCanCloseLastExternal() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)])   // 仅一块外接活跃,内建合盖不在列表
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.menuItems().first { $0.id == 2 }?.canToggleOff == true)
    #expect(ctrl.toggle(id: 2) == true)
    #expect(svc.setCalls.contains { $0.id == 2 && $0.on == false })
}

@Test("无内建屏的机器(macmini):禁止关最后一块外接屏")
func desktopCannotCloseLastExternal() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)])
    svc.hasBuiltIn = false
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.menuItems().first { $0.id == 2 }?.canToggleOff == false)
    #expect(ctrl.toggle(id: 2) == false)
    #expect(svc.setCalls.isEmpty)
}

@Test("内建屏已被软件关掉后:禁止关最后一块外接屏(开盖救不回,防死锁)")
func cannotCloseLastExternalAfterBuiltinDisabled() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 2, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 1) == true)    // 先软件关内建,剩外接活跃
    #expect(ctrl.toggle(id: 2) == false)   // 再关最后一块外接 → 拒绝(内建已软件关,非兜底)
    #expect(!svc.setCalls.contains { $0.id == 2 && $0.on == false })
}

@Test("系统在 app 之外重新点亮被关的屏:菜单显示为开,且不再残留为已关闭")
func systemReactivatesDisabledDisplay() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)                                    // app 关掉 3
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == false)

    svc.externallyReactivate(3)                              // 远程会话/重配置在 app 之外把 3 又点亮
    // 它现在是活跃屏 → 必须显示为「开」,不能因陈旧的 disabled 残留而显示为「关」。
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == true)
    // 状态已真正对齐:再点是「关」(正确调用 setEnabled false),而非被误当成「开」。
    #expect(ctrl.toggle(id: 3) == true)
    #expect(svc.setCalls.last?.on == false)
}

@Test("关闭主屏后:已关闭的屏不再标主屏,主屏标记跟随转移到的活跃屏")
func closingMainClearsMainOnDisabledAndTransfersLabel() {
    let main = DisplayInfo(id: 5, uuid: "u5", name: "R",
                           bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                           isMain: true, isBuiltin: false, isActive: true)
    let side = DisplayInfo(id: 2, uuid: "u2", name: "L",
                           bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                           isMain: false, isBuiltin: false, isActive: true)
    let svc = MockService(all: [main, side])
    let ctrl = DisplayController(service: svc)

    #expect(ctrl.toggle(id: 5) == true)   // 关右主屏 → Mock 模拟主屏转移给 id2

    let items = ctrl.menuItems()
    let item5 = items.first { $0.id == 5 }!
    let item2 = items.first { $0.id == 2 }!
    #expect(item5.isOn == false)
    #expect(!item5.label.contains("（主）"))   // 已关闭的屏不再标主屏
    #expect(item2.isOn == true)
    #expect(item2.label.contains("（主）"))     // 转移后的新主屏
}
