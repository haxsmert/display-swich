import Testing
import CoreGraphics
@testable import DisplaySwitchCore

/// 可控的假系统服务:维护一份「全集」与「当前活跃」,模拟开关后的活跃变化。
final class MockService: SystemDisplayService {
    private var known: [CGDirectDisplayID: DisplayInfo]
    private var activeIDs: Set<CGDirectDisplayID>
    var builtIn: Bool
    var setResult = true
    private(set) var setCalls: [(id: CGDirectDisplayID, on: Bool)] = []

    init(all: [DisplayInfo], builtIn: Bool) {
        known = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        activeIDs = Set(all.filter { $0.isActive }.map { $0.id })
        self.builtIn = builtIn
    }

    func activeExternalDisplays() -> [DisplayInfo] {
        known.values
            .filter { !$0.isBuiltin && activeIDs.contains($0.id) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }
    func hasBuiltInDisplay() -> Bool { builtIn }
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        setCalls.append((id, on))
        guard setResult else { return false }
        if on { activeIDs.insert(id) } else { activeIDs.remove(id) }
        return true
    }
}

private func twoExternals() -> [DisplayInfo] {
    [makeInfo(id: 2, main: true, x: 0), makeInfo(id: 3, x: 1920)]
}

@Test("关闭一块外接屏会调用 setEnabled(false) 并记入已关闭")
func toggleOffRecordsDisabled() {
    let svc = MockService(all: twoExternals(), builtIn: false)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 3) == true)
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == false })
    let item = ctrl.menuItems().first { $0.id == 3 }
    #expect(item?.isOn == false)
}

@Test("无内建屏关到最后一块被拒绝,不调用 setEnabled")
func toggleOffLastExternalRejected() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: false)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 2) == false)
    #expect(svc.setCalls.isEmpty)
}

@Test("有内建屏可把唯一外接屏关掉")
func toggleOffLastExternalAllowedWithBuiltIn() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: true)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 2) == true)
    #expect(svc.setCalls.contains { $0.id == 2 && $0.on == false })
}

@Test("重新打开已关闭的屏会调用 setEnabled(true) 并移出已关闭")
func toggleOnRestores() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)              // 关
    #expect(ctrl.toggle(id: 3) == true) // 开
    #expect(svc.setCalls.last?.on == true)
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == true)
}

@Test("menuItems 合并活跃与已关闭,均出现")
func menuItemsMergeActiveAndDisabled() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3) // 关掉 3
    let items = ctrl.menuItems()
    #expect(items.count == 2)
    #expect(items.first { $0.id == 2 }?.isOn == true)
    #expect(items.first { $0.id == 3 }?.isOn == false)
}

@Test("restoreAll 把所有已关闭的屏重新打开并清空")
func restoreAllReenables() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)
    ctrl.restoreAll()
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == true })
    #expect(ctrl.menuItems().allSatisfy { $0.isOn })
}

@Test("无内建屏时唯一活跃屏的菜单项 canToggleOff 为 false")
func canToggleOffFalseForLastExternal() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: false)
    let ctrl = DisplayController(service: svc)
    let item = ctrl.menuItems().first { $0.id == 2 }
    #expect(item?.canToggleOff == false)
    #expect(item?.isOn == true)
}
