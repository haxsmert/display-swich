import CoreGraphics

/// 能否关闭某块屏。统一规则:绝不让系统无屏可用——
/// 必须始终至少保留一块活跃屏(任意类型,含内建)。
public func canDisable(_ target: DisplayInfo, among all: [DisplayInfo]) -> Bool {
    guard target.isActive else { return false }
    return all.filter { $0.isActive }.count > 1
}
