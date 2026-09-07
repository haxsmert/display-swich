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
    /// 物理连着的外接屏(IOKit 视角):软件关屏不改变它,只有拔线才会。
    private var physicallyConnected: Set<CGDirectDisplayID>
    private(set) var setCalls: [(id: CGDirectDisplayID, on: Bool)] = []

    init(all: [DisplayInfo]) {
        known = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        activeIDs = Set(all.filter { $0.isActive }.map { $0.id })
        physicallyConnected = Set(all.filter { !$0.isBuiltin }.map { $0.id })
        liveConnected = physicallyConnected
    }

    var isSupported: Bool { supported }
    func hasBuiltInDisplay() -> Bool { hasBuiltIn }
    /// nil 模拟「IOKit 查询失败」。
    var physicalQueryFails = false
    func physicalExternalCount() -> Int? { physicalQueryFails ? nil : physicallyConnected.count }

    /// 瞬时计数(带 EDID 的传输节点),与内核拔线通知同步。真机上它比上面那个快约 3.5 秒。
    private var liveConnected: Set<CGDirectDisplayID>
    func liveExternalCount() -> Int? { physicalQueryFails ? nil : liveConnected.count }

    func activeDisplays() -> [DisplayInfo] {
        known.values
            .filter { activeIDs.contains($0.id) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }

    /// 记下注册的拔线回调,测试可用 fireDisconnectNotification() 模拟内核通知到达。
    private var disconnectHandler: (() -> Void)?
    func observeDisplayDisconnect(_ handler: @escaping () -> Void) { disconnectHandler = handler }
    /// 模拟内核的拔线终止通知抵达(真机上由 IOKit 派发)。
    func fireDisconnectNotification() { disconnectHandler?() }

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

    /// 模拟「物理拔掉线」:该屏既不再活跃,IOKit 也看不到它的物理连接了。
    func unplug(_ id: CGDirectDisplayID) {
        activeIDs.remove(id)
        physicallyConnected.remove(id)
        liveConnected.remove(id)
    }

    /// 模拟**拔线那一瞬间**的真实状态:内核通知已到、带 EDID 的节点已归零,
    /// 但 framebuffer 计数与 CG 活跃列表都还滞后着报旧数字(实测滞后约 3.5 秒)。
    /// 救援就发生在这一刻,必须在这种状态下也判对。
    func unplugAsSeenAtNotificationTime(_ id: CGDirectDisplayID) {
        liveConnected.remove(id)
    }

    /// 模拟「显示器息屏」:CoreGraphics 活跃列表归零(实测确会如此——active 的定义含 awake),
    /// 但线都还插着,IOKit 物理连接不变。用来锁住「息屏绝不能被当成全黑」。
    func sleepAllDisplays() {
        activeIDs.removeAll()
    }

    /// 模拟「CoreGraphics 读数陈旧」:线已经拔了(IOKit 侧都归零),
    /// 但 CG 的活跃列表还报着拔线前的屏。实测拔线瞬间就是这个状态。
    func unplugButLeaveStaleActiveList(_ id: CGDirectDisplayID) {
        physicallyConnected.remove(id)
        liveConnected.remove(id)
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

@Test("被关掉的外接屏遭物理拔线:菜单不再残留该屏")
func unpluggedDisabledDisplayIsDropped() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 4) == true)                       // app 关掉外接屏
    #expect(ctrl.menuItems().count == 2)                      // 还连着 → 仍显示,可开回来
    #expect(ctrl.menuItems().first { $0.id == 4 }?.isOn == false)

    svc.unplug(4)                                             // 拔线
    let items = ctrl.menuItems()
    #expect(items.count == 1)                                 // 幽灵项消失
    #expect(items.first?.id == 1)
}

@Test("被关掉的外接屏线还插着:绝不能被反向对账误删(否则再也开不回来)")
func softDisabledDisplayIsKept() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 4)
    // 连续多次读状态都不该把它清掉(物理连接仍在)。
    for _ in 0..<3 { #expect(ctrl.menuItems().contains { $0.id == 4 && !$0.isOn }) }
    #expect(ctrl.toggle(id: 4) == true)                       // 仍能正常开回来
    #expect(ctrl.menuItems().first { $0.id == 4 }?.isOn == true)
}

@Test("两块外接屏都被关掉后只拔走一块:无从判定是哪块,一律保留不猜")
func ambiguousUnplugKeepsRecords() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0),
                                makeInfo(id: 4, x: 1920), makeInfo(id: 5, x: 3840)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 4)
    _ = ctrl.toggle(id: 5)
    svc.unplug(4)                                             // 物理外接屏 2 → 1
    // slots = 1 > 0:确知少了一块,但认不出是哪块 → 两条记录都保留,绝不误删。
    #expect(ctrl.menuItems().count == 3)
}

@Test("拔线后所有被关的外接屏都清空,但内建屏的关闭记录不受影响")
func reverseReconcileIgnoresBuiltin() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                                    // 关内建屏(外接屏还活跃)
    svc.unplug(4)                                             // 再把外接屏拔走
    // 内建屏的关闭记录必须留着(它没被拔,靠开盖/重开恢复),不能被反向对账误清。
    #expect(ctrl.menuItems().contains { $0.id == 1 && !$0.isOn })
}

@Test("IOKit 查询失败时不做反向对账:绝不能因查不到就把还连着的屏误删")
func physicalQueryFailureKeepsRecords() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 4)
    svc.physicalQueryFails = true          // 查询坏了(返回 nil,而不是 0)
    #expect(ctrl.menuItems().contains { $0.id == 4 && !$0.isOn })   // 记录必须留着
    #expect(ctrl.toggle(id: 4) == true)                             // 仍能开回来
}

// MARK: - 全黑兜底
//
// canDisable 只能校验「按下开关那一刻」:关内建屏时外接屏还活跃,判定合法、没错。
// 但那块「兜底的活跃屏」可能在之后被物理拔走(拔拓展坞 / 拔线 / 外接屏断电),
// 此时 WindowServer 仍记着被关的内建屏(.forAppOnly 不因拔线回滚)→ 活跃屏归零 → 全黑。
// 全黑时用户点不开菜单栏,而本 app 的对账全挂在「菜单被打开」上 → 无法自愈的死局。

@Test("关掉内建屏后拔走唯一活跃的外接屏(全黑):必须自动把内建屏开回来")
func blackoutAfterUnplugIsRescued() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 1) == true)          // 关内建屏(外接屏还活跃,合法)
    svc.unplug(4)                                // 拔掉拓展坞,外接屏物理消失
    #expect(svc.activeDisplays().isEmpty)        // 前提成立:确实一块活跃屏都不剩了

    #expect(ctrl.rescueFromBlackout() == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == true })  // 内建屏被开回来
    #expect(!svc.activeDisplays().isEmpty)                          // 不再全黑
    #expect(ctrl.menuItems().first { $0.id == 1 }?.isOn == true)    // 记录也同步清干净
}

@Test("还剩活跃屏时不救援:绝不擅自把用户关掉的屏开回来")
func rescueSkippedWhileAnyDisplayActive() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                       // 关内建屏,外接屏仍活跃
    let before = svc.setCalls.count

    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.count == before)                           // 一次 setEnabled 都不该发
    #expect(ctrl.menuItems().first { $0.id == 1 }?.isOn == false)   // 用户的关闭意图保留
}

@Test("没有任何屏是本 app 关的:即便查到 0 块活跃屏也不动手")
func rescueSkippedWhenNothingDisabledByUs() {
    let svc = MockService(all: [makeInfo(id: 4, x: 0)])
    let ctrl = DisplayController(service: svc)
    svc.unplug(4)                                // 屏是被拔走的,不是本 app 关的
    #expect(svc.activeDisplays().isEmpty)

    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.isEmpty)                // 不该对不属于自己的屏发指令
}

@Test("救援后重复触发不再动手(已恢复,幂等)")
func rescueIsIdempotent() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)
    svc.unplug(4)
    #expect(ctrl.rescueFromBlackout() == true)
    let before = svc.setCalls.count

    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.count == before)
}

@Test("关了两块屏后全黑:两块都开回来,不挑不猜")
func rescueRestoresEveryDisplayWeDisabled() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0),
                                makeInfo(id: 4, x: 1920), makeInfo(id: 5, x: 3840)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                       // 关内建屏
    _ = ctrl.toggle(id: 4)                       // 再关一块外接屏,剩 5 撑着
    svc.unplug(5)                                // 拔走最后的活跃屏 → 全黑

    #expect(ctrl.rescueFromBlackout() == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == true })
    #expect(svc.setCalls.contains { $0.id == 4 && $0.on == true })
}

@Test("恢复失败时不清记录:否则屏黑着、菜单里也没了那块屏,双重失联")
func restoreAllKeepsRecordsWhenSystemCallFails() {
    let svc = MockService(all: twoExternals())
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)
    svc.setResult = false                        // 系统调用开始失败
    ctrl.restoreAll()
    // 屏没能开回来 → 记录必须留着,用户仍能在菜单里看到它、再点一次。
    #expect(ctrl.menuItems().contains { $0.id == 3 && !$0.isOn })

    svc.setResult = true                         // 系统恢复正常
    ctrl.restoreAll()
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == true)
}

@Test("救援时系统调用失败:可以再救一次(重试有意义),成功后才收手")
func rescueStaysRetryableUntilItActuallyWorks() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)
    svc.unplug(4)                                // 全黑
    svc.setResult = false                        // 这一刻 WindowServer 不接受配置

    #expect(ctrl.rescueFromBlackout() == true)   // 试过了
    #expect(svc.activeDisplays().isEmpty)        // 但没成功,仍然全黑
    #expect(ctrl.rescueFromBlackout() == true)   // 记录还在 → 下一次还会再试

    svc.setResult = true                         // 系统缓过来了
    #expect(ctrl.rescueFromBlackout() == true)
    #expect(!svc.activeDisplays().isEmpty)       // 这次真的亮了
    #expect(ctrl.rescueFromBlackout() == false)  // 已无需救援 → 收手,不再重试
}


// MARK: - 救援判据不依赖 CoreGraphics(2026-09-07 拔线现场实测的两个缺陷)

@Test("息屏让 CG 活跃屏归零:绝不能误当成全黑而擅自开屏")
func sleepingDisplaysAreNotBlackout() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                       // 关内建屏,外接屏还亮着
    svc.sleepAllDisplays()                       // 息屏 → CG 活跃屏归零(但线都插着)
    #expect(svc.activeDisplays().isEmpty)        // 前提:CG 视角与全黑完全同形
    let before = svc.setCalls.count

    // 旧判据(activeDisplays().isEmpty)在这里会误救援;新判据看 IOKit,外接屏还连着 → 不动手。
    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.count == before)
    #expect(ctrl.menuItems().first { $0.id == 1 }?.isOn == false)   // 用户的关闭意图保留
}

@Test("拔线瞬间 CG 读数陈旧(还报着屏):必须照样判定全黑并救援")
func staleActiveListStillTriggersRescue() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                              // 关内建屏
    svc.unplugButLeaveStaleActiveList(4)                // 线拔了,但 CG 还报着 4 是活跃的
    #expect(!svc.activeDisplays().isEmpty)              // 前提:CG 仍在骗人

    // 旧判据会因为「还有活跃屏」而不救援 → 用户全黑;新判据看 IOKit,已归零 → 救。
    #expect(ctrl.rescueFromBlackout() == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == true })
}

@Test("台式机(无内建屏):关掉一块、拔走另一块 → 救回还连着的那块")
func desktopRescuesTheStillConnectedDisplay() {
    let svc = MockService(all: [makeInfo(id: 4, x: 0), makeInfo(id: 5, x: 1920)])
    svc.hasBuiltIn = false                              // Mac mini 之类,没有内建屏面板
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 4) == true)                 // 关掉 4,5 还亮着
    svc.unplug(5)                                       // 拔走 5 → 只剩被关掉的 4 还连着

    #expect(ctrl.rescueFromBlackout() == true)
    #expect(svc.setCalls.contains { $0.id == 4 && $0.on == true })
}

@Test("关的是外接屏、内建屏亮着:拔走那块外接屏也不该救援")
func unpluggingDisabledExternalWhileBuiltinLitIsNotBlackout() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 4)                              // 关外接屏(内建屏始终亮着)
    svc.unplug(4)
    let before = svc.setCalls.count

    #expect(ctrl.rescueFromBlackout() == false)         // 内建屏好好亮着,没有全黑
    #expect(svc.setCalls.count == before)
}

@Test("关了内建屏和一块外接屏,另一块外接屏还亮着:不算全黑")
func remainingLitExternalPreventsRescue() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0),
                                makeInfo(id: 4, x: 1920), makeInfo(id: 5, x: 3840)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                              // 关内建
    _ = ctrl.toggle(id: 4)                              // 关一块外接,5 还亮着
    let before = svc.setCalls.count

    // 物理外接屏 2 块 > 本 app 关掉的外接屏 1 块 ⇒ 至少有一块亮着。
    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.count == before)
}

@Test("IOKit 查询失败时绝不救援:查不到物理连接就无法证明有屏被拔走")
func rescueSkippedWhenPhysicalQueryFails() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)
    svc.unplug(4)
    svc.physicalQueryFails = true                       // IOKit 查询坏了(返回 nil,不是 0)
    let before = svc.setCalls.count

    #expect(ctrl.rescueFromBlackout() == false)
    #expect(svc.setCalls.count == before)
}

@Test("装配链路:内核拔线通知抵达 → 救援真的被执行(v1.0.6 断的就是这一环)")
func kernelDisconnectNotificationTriggersRescue() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    // 按 AppDelegate 的方式装配:把救援挂到拔线事件上。
    var rescued = false
    svc.observeDisplayDisconnect { rescued = ctrl.rescueFromBlackout() }

    _ = ctrl.toggle(id: 1)                       // 关内建屏(外接屏还亮着,合法)
    svc.fireDisconnectNotification()             // 此刻还没拔线 → 不该救
    #expect(rescued == false)

    svc.unplug(4)                                // 拔掉拓展坞
    svc.fireDisconnectNotification()             // 内核通知抵达
    #expect(rescued == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == true })
    #expect(!svc.activeDisplays().isEmpty)       // 屏亮回来了

    svc.fireDisconnectNotification()             // 同一次拔线的重复通知(实测一次来 6 条)
    #expect(rescued == false)                    // 幂等,不重复动手
}


@Test("拔线那一刻 framebuffer 计数还滞后着报旧数:救援必须照样判对(否则等于不救)")
func rescueUsesLiveCountNotTheLaggingOne() {
    let svc = MockService(all: [makeInfo(id: 1, builtin: true, x: 0), makeInfo(id: 4, x: 1920)])
    svc.hasBuiltIn = true
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 1)                                   // 关内建屏

    svc.unplugAsSeenAtNotificationTime(4)                    // 内核通知到达的那一刻
    #expect(svc.physicalExternalCount() == 1)                // 滞后的计数还报着 1 块屏
    #expect(svc.liveExternalCount() == 0)                    // 瞬时计数已归零
    #expect(!svc.activeDisplays().isEmpty)                   // CG 也还陈旧

    // 用滞后计数会得出「还有屏亮着」而不救 → 用户全黑。必须用瞬时计数。
    #expect(ctrl.rescueFromBlackout() == true)
    #expect(svc.setCalls.contains { $0.id == 1 && $0.on == true })
}
