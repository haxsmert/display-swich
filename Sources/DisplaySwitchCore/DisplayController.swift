import CoreGraphics

/// 渲染给菜单的一行。
public struct DisplayMenuItem: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let label: String
    public let isOn: Bool
    public let canToggleOff: Bool
}

/// 组合纯逻辑(命名/保护)与系统服务,维护「被本 app 关闭的屏」状态。
public final class DisplayController {
    private let service: SystemDisplayService
    /// 被本 app 关掉的屏(关闭前捕获的快照),用于在菜单里仍能显示并恢复。
    private var disabled: [CGDirectDisplayID: DisplayInfo] = [:]

    public init(service: SystemDisplayService) {
        self.service = service
    }

    /// 系统是否支持开关(私有符号存在)。不支持时 UI 应只读并提示,各项 canToggleOff 亦为 false。
    public var isSupported: Bool { service.isSupported }

    /// 把「已被本 app 关闭」的记录与系统真相对账。每次读状态前跑一遍即可自愈,不依赖任何回调。
    ///
    /// **正向**:任何当前活跃的屏一律视为「开」并从 disabled 剔除。远程会话重配置 / 睡眠唤醒 /
    /// 重新插拔会在 app 之外把被关的屏重新点亮;不对齐的话,菜单会把一块活跃屏显示成「关」,
    /// 且因 app 误以为它仍关着、再点会被当成「开」,于是永远勾不上。
    ///
    /// **反向**:已被物理拔走的屏要从 disabled 剔除,否则它会像幽灵一样长期赖在菜单里
    /// (点它只是对一个已失效的 display ID 调开屏,毫无效果)。难点在于 CoreGraphics 分不出
    /// 「被我软件关掉」和「被拔掉」——两种情况下该屏都从 online 列表消失、UUID 也解析不出;
    /// 只有 IOKit 还留着那条物理连接,故改用它的物理外接屏数来对账。
    private func reconcileDisabled(active: [DisplayInfo]) {
        let activeIDs = Set(active.map { $0.id })
        disabled = disabled.filter { !activeIDs.contains($0.key) }

        let disabledExternals = disabled.values.filter { !$0.isBuiltin }
        guard !disabledExternals.isEmpty else { return }
        // 查不到物理连接就什么都不做:此时无法证明任何一块屏已被拔走,
        // 而误删的代价是用户再也开不回那块屏。
        guard let physical = service.physicalExternalCount() else { return }
        // 还能容下几块「被我关着的外接屏」= 物理连着的外接屏 − 已经活跃的外接屏。
        let slots = physical - active.filter { !$0.isBuiltin }.count
        if slots <= 0 {
            // 一块都容不下 → 这些记录全是拔线后的残留,清掉。
            for d in disabledExternals { disabled[d.id] = nil }
        }
        // slots 大于 0 却少于记录数:确知有屏被拔走了,但无从判定是哪几块
        // (实测 IOKit 的 IOMFBUUID 与 CoreGraphics 的 display UUID 不是同一套标识,对不上)。
        // 此时不猜、一律保留:多显示一项的代价,远小于误删一块还连着、用户正等着开回来的屏。
        //
        // 内建屏不参与反向对账:它不会被「拔掉」,合盖也只是暂时不活跃,开盖即回。
    }

    /// 是否存在「可开盖恢复的内建屏」兜底:机器有内建屏面板,且内建屏当前未被本 app 软件关闭。
    /// (被软件关掉的内建屏开盖救不回,不算兜底。)
    private func builtInFallbackAvailable() -> Bool {
        let builtInDisabledByUs = disabled.values.contains { $0.isBuiltin }
        return service.hasBuiltInDisplay() && !builtInDisabledByUs
    }

    public func menuItems() -> [DisplayMenuItem] {
        let active = service.activeDisplays()
        reconcileDisabled(active: active)
        var byID: [CGDirectDisplayID: DisplayInfo] = [:]
        for d in disabled.values {
            // 已被本 app 断开的屏不可能是主屏:显示时清除 isMain,
            // 否则关掉主屏后(主屏角色转移给另一块)会出现两块都标「主屏」的错乱。
            byID[d.id] = DisplayInfo(id: d.id, uuid: d.uuid, name: d.name, bounds: d.bounds,
                                     isMain: false, isBuiltin: d.isBuiltin, isActive: false)
        }
        for d in active { byID[d.id] = d }
        // 按稳定键(基名+UUID)排序:同名屏相邻、与编号同序,不随位置漂移。
        let ordered = byID.values.sorted {
            (baseName($0.name), $0.uuid, $0.id) < (baseName($1.name), $1.uuid, $1.id)
        }
        // 整组(活跃+已关闭)一起算标签:同名屏按 UUID 稳定编号,关掉其一不丢号、重开不漂移。
        let labels = displayLabels(for: ordered)
        let fallback = builtInFallbackAvailable()
        return ordered.map { d in
            let on = disabled[d.id] == nil
            let canOff = (service.isSupported && on) ? canDisable(d, among: active, builtInFallback: fallback) : false
            return DisplayMenuItem(id: d.id, label: labels[d.id] ?? displayLabel(for: d), isOn: on, canToggleOff: canOff)
        }
    }

    @discardableResult
    public func toggle(id: CGDirectDisplayID) -> Bool {
        // 私有符号缺失:开关不可用,直接拒绝(恢复走 restoreAll/启动兜底,不受此限)。
        guard service.isSupported else { return false }
        // 先与系统真实活跃状态对账:被系统在 app 之外重新点亮的屏要从 disabled 剔除,
        // 否则一块已经活跃的屏会被误当成「关着」而走进开屏分支。
        let active = service.activeDisplays()
        reconcileDisabled(active: active)
        // 当前关着 → 打开
        if disabled[id] != nil {
            guard service.setEnabled(id, true) else { return false }
            disabled[id] = nil
            return true
        }
        // 当前开着 → 尝试关闭(带保护校验)
        guard let target = active.first(where: { $0.id == id }) else { return false }
        guard canDisable(target, among: active, builtInFallback: builtInFallbackAvailable()) else { return false }
        guard service.setEnabled(id, false) else { return false }
        disabled[id] = target
        return true
    }

    /// 全黑兜底:只要「一块活跃屏都不剩、而本 app 还关着屏」,立刻把关掉的屏全开回来。
    /// 返回是否真的执行了救援。
    ///
    /// 为什么 `canDisable` 不够:它只能校验**按下开关那一刻**——关内建屏时外接屏还活跃,
    /// 判定合法、并没有错。错的是那之后世界会变:作兜底的那块活跃屏可能被物理拔走
    /// (拔拓展坞 / 拔线 / 外接屏断电),而 WindowServer 仍记着被本 app 关掉的屏
    /// (`.forAppOnly` 实测不因拔线回滚)→ 活跃屏归零 → 全黑。
    ///
    /// 为什么必须由系统事件驱动:本 app 其余的对账(`reconcileDisabled`)全都挂在
    /// `menuItems()` / `toggle()` 上,也就是**只有用户点开菜单才会跑**;而全黑时
    /// 用户根本点不开菜单栏,死局无法自愈,只能盲操作退屏或强制重启。
    ///
    /// 为什么全开而不是只开一块:全黑是紧急情况,「该开哪一块」的挑选逻辑既要多余的判据、
    /// 又多一个出错面;全开与「退出 app」的既有语义一致,用户看见画面后随时能自己再关。
    @discardableResult
    public func rescueFromBlackout() -> Bool {
        // 没关过任何屏 → 与本 app 无关(屏黑是别的原因),不动手也不查系统。
        guard !disabled.isEmpty else { return false }
        // 还有屏亮着 → 用户的关闭意图有效,绝不擅自开回来。
        guard service.activeDisplays().isEmpty else { return false }
        restoreAll()
        return true
    }

    /// 恢复所有被本 app 关闭的屏(app 退出兜底 / 全黑救援)。
    ///
    /// **只清掉真正恢复成功的那些**:系统调用失败却照样清记录,等于把失败谎报成成功——
    /// 屏还黑着,菜单里却连那块屏都没了,用户既看不见画面也点不回来(双重失联)。
    /// 记录留着,菜单仍列得出它,救援下一轮也还能重试。
    public func restoreAll() {
        for id in Array(disabled.keys) where service.setEnabled(id, true) {
            disabled[id] = nil
        }
    }
}
