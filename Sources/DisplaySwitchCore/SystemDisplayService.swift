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
    /// 启用/断开某块屏,返回是否成功。
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool
}
