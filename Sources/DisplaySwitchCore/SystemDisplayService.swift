import CoreGraphics

/// 把所有与系统显示子系统的副作用交互藏在协议后,便于注入测试。
public protocol SystemDisplayService {
    /// 当前活跃(在线且启用)的外接屏。
    func activeExternalDisplays() -> [DisplayInfo]
    /// 这台机器是否具备内建屏(基于机器具备性,而非当前是否激活)。
    func hasBuiltInDisplay() -> Bool
    /// 启用/断开某块屏,返回是否成功。
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool
}
