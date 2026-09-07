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
    /// 物理连着的外接屏数量,**拔线瞬间即刻准确**(数带 EDID 的显示传输节点)。专供全黑救援。
    ///
    /// 为什么不能复用 `physicalExternalCount()`——实测(2026-09-07 拔拓展坞现场):
    /// 拔线的内核通知到达那一刻,`physicalExternalCount()` 仍报着拔线前的 2 块屏,
    /// **滞后约 3.5 秒**才归零;而带 EDID 的传输节点在通知到达时已经是 0。
    /// 救援就发生在通知到达那一刻,拿滞后的数字判断等于不救。
    ///
    /// 两者保守方向也不同,故不合并:某些屏/转接器可能不报 EDID,导致本方法**偏小**——
    /// 对救援是安全方向(偏向多救),对菜单反向对账却是危险方向(会把还连着的屏误删)。
    /// 所以反向对账继续用 `physicalExternalCount()`,救援用本方法。
    func liveExternalCount() -> Int?

    /// 注册「显示器被物理拔掉」的**内核事件**监听(IOKit 服务终止通知),用于全黑救援。
    ///
    /// 为什么不用 CoreGraphics 的 `CGDisplayRegisterReconfigurationCallback`:
    /// 实测(2026-09-07 拔拓展坞现场)拔线**全程 0 次派发**——它只对配置变更(如改分辨率)
    /// 派发,对物理拔线不派发;同一刻 `CGGetActiveDisplayList` 还报着拔线前的屏数。
    /// 而 IOKit 的终止通知在拔线瞬间就到,且计数当场归零。
    ///
    /// 同一次拔线会连着回调多次(实测一次拔线来了 6 条),故 handler 必须幂等。
    func observeDisplayDisconnect(_ handler: @escaping () -> Void)

    /// 启用/断开某块屏,返回是否成功。
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool
}
