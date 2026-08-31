import CoreGraphics

/// 把所有与系统显示子系统的副作用交互藏在协议后,便于注入测试。
public protocol SystemDisplayService {
    /// 私有断开符号是否可用;不可用时(如未来 macOS 改名/移除)应禁用开关并提示,而非静默失败。
    var isSupported: Bool { get }
    /// 当前所有活跃屏(含内建屏)。
    func activeDisplays() -> [DisplayInfo]
    /// 这台机器是否**具备**内建屏面板(便携机即便合盖、内建屏不活跃也算);
    /// 用于「关到全黑后能否开盖恢复」的兜底判定。
    func hasBuiltInDisplay() -> Bool
    /// 物理连接着的外接屏数量(IOKit 层),**不受本 app 软件断开影响**。
    /// 返回 `nil` 表示**查不到**(查询失败),与「确实一块都没接」(`0`)是两回事——
    /// 混淆二者会让对账把还连着的屏当成已拔走而误删,故必须可区分。
    ///
    /// 必要性:被软件关掉的屏在 CoreGraphics 层与被拔掉的屏**完全同形**——都从 online 列表消失、
    /// UUID 也解析不出(实测)。只有 IOKit 的 framebuffer 节点还留着那条物理连接,
    /// 故用它区分「我关的(该留在菜单里等你开回来)」与「已经拔掉的(该从菜单消失)」。
    func physicalExternalCount() -> Int?
    /// 启用/断开某块屏,返回是否成功。
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool
}
