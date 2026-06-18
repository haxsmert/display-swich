import CoreGraphics

/// 判断能否关闭某块外接屏。机型感知:
/// - 有内建屏:任意活跃外接屏都可关(开盖用内建屏恢复)。
/// - 无内建屏:必须保留至少一块活跃外接屏。
public func canDisable(_ target: DisplayInfo, among all: [DisplayInfo], hasBuiltIn: Bool) -> Bool {
    guard !target.isBuiltin, target.isActive else { return false }
    if hasBuiltIn { return true }
    let activeExternals = all.filter { !$0.isBuiltin && $0.isActive }
    return activeExternals.count > 1
}
