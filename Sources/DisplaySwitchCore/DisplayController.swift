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

    public func menuItems() -> [DisplayMenuItem] {
        let active = service.activeExternalDisplays()
        let hasBuiltIn = service.hasBuiltInDisplay()
        // 合并:当前活跃 + 已关闭(去重,活跃优先),按 x 排序稳定显示。
        var byID: [CGDirectDisplayID: DisplayInfo] = [:]
        for d in disabled.values { byID[d.id] = d }
        for d in active { byID[d.id] = d }
        let ordered = byID.values.sorted { $0.bounds.minX < $1.bounds.minX }

        return ordered.map { d in
            let on = disabled[d.id] == nil
            let canOff = on ? canDisable(d, among: active, hasBuiltIn: hasBuiltIn) : false
            return DisplayMenuItem(id: d.id,
                                   label: displayLabel(for: d, among: ordered),
                                   isOn: on,
                                   canToggleOff: canOff)
        }
    }

    @discardableResult
    public func toggle(id: CGDirectDisplayID) -> Bool {
        // 当前关着 → 打开
        if disabled[id] != nil {
            guard service.setEnabled(id, true) else { return false }
            disabled[id] = nil
            return true
        }
        // 当前开着 → 尝试关闭(带保护校验)
        let active = service.activeExternalDisplays()
        guard let target = active.first(where: { $0.id == id }) else { return false }
        guard canDisable(target, among: active, hasBuiltIn: service.hasBuiltInDisplay()) else { return false }
        guard service.setEnabled(id, false) else { return false }
        disabled[id] = target
        return true
    }

    /// 恢复所有被本 app 关闭的屏(用于 app 退出兜底)。
    public func restoreAll() {
        for id in disabled.keys {
            _ = service.setEnabled(id, true)
        }
        disabled.removeAll()
    }
}
