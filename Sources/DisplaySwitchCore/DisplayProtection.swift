import CoreGraphics

/// 能否关闭某块屏。核心目标:绝不把用户置于「无法恢复的全黑」死局。
///
/// 规则:
/// - 关掉后仍剩 ≥1 块活跃屏 → 允许;
/// - 关掉后会变成 0 块活跃(全黑)→ 仅当存在「可开盖恢复的内建屏」兜底才允许
///   (笔记本合盖用外接、开盖即恢复内建)。
///
/// `builtInFallback`:是否存在「可开盖恢复的内建屏」——即这台机器有内建屏面板、
/// 且该内建屏当前**未被本 app 软件关闭**(被软件关掉的内建屏开盖也救不回,不算兜底)。
/// 由 `DisplayController` 计算后传入。此外,若 `target` 本身就是内建屏,关掉它后内建屏即被
/// 软件关闭、不再是兜底,故也禁止(防「软件关内建 → 全黑」死锁)。
public func canDisable(_ target: DisplayInfo, among all: [DisplayInfo], builtInFallback: Bool) -> Bool {
    guard target.isActive else { return false }
    let activeAfter = all.filter { $0.isActive && $0.id != target.id }.count
    if activeAfter >= 1 { return true }
    return builtInFallback && !target.isBuiltin
}
