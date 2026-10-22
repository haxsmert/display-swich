import Foundation

/// 显示驱动的健康状况,显示在面板底部状态栏(他的要求:能看到系统驱动是否正常)。
///
/// 只认两条有实测依据的信号(2026-10-22):
/// - **卡死**:macOS 27.0 的雷雳显示输出驱动卡死时,系统日志里 `AppleThunderboltDPOutAdapter`
///   持续报 `evaluating for > 1m`——卡死那天任意 2 分钟约 1200 条,重启后健康的 3 小时里一条都没有。
///   卡死本身不影响使用,拔坞时才出事(残影屏、开盖后内核崩溃),所以要在拔坞前就让人看到。
/// - **残影屏**:驱动卡死后拔坞,已拔走的屏仍被系统当成在线(实测物理 0、在线 2),窗口困在上面。
///   日志轮换后看不到卡死记录时,这是还能看到的后果。
public enum DriverHealth: Equatable, Sendable {
    case checking
    case normal
    /// 雷雳显示驱动卡死:近 2 分钟系统日志里卡死特征出现的条数。
    case wedged(logLines: Int)
    /// 残影屏:已拔掉却仍被当成在线的外接屏块数。
    case ghostScreens(Int)
    /// 读不到系统日志,又没看到残影:判断不了,不说正常。
    case unknown
}

/// 由两条信号定状态。卡死特征出现一条就算——健康时一条都不会有,不需要拍阈值。
/// 两样都有时报卡死:残影是它的后果。
public func assessDriverHealth(wedgeLogLines: Int?, ghostScreens: Int) -> DriverHealth {
    if let lines = wedgeLogLines, lines > 0 { return .wedged(logLines: lines) }
    if ghostScreens > 0 { return .ghostScreens(ghostScreens) }
    return wedgeLogLines == nil ? .unknown : .normal
}

/// 状态栏里的一句短话。
public func driverStatusLabel(_ health: DriverHealth) -> String {
    switch health {
    case .checking: "正在检查显示驱动"
    case .normal: "显示驱动正常"
    case .wedged: "显示驱动卡死"
    case .ghostScreens: "显示驱动异常"
    case .unknown: "无法检查显示驱动"
    }
}

/// 状态栏可能出现的每一句,界面按最长的预留宽度(状态变化时面板不变宽)。
public let driverStatusLabels = ["正在检查显示驱动", "显示驱动正常", "显示驱动卡死", "显示驱动异常", "无法检查显示驱动"]

/// 详情:依据是什么、该怎么办。每句都短,放进菜单不会把菜单撑得很宽。
public func driverStatusDetails(_ health: DriverHealth) -> [String] {
    switch health {
    case .checking:
        ["正在读系统日志"]
    case .normal:
        ["近 2 分钟没有雷雳显示驱动卡死的记录", "在线的外接屏与物理连接一致"]
    case .wedged(let lines):
        ["近 2 分钟系统日志报了 \(lines) 次雷雳显示驱动超时",
         "先别拔拓展坞，重启电脑可以恢复",
         "带着它拔坞会出现残影屏，严重时内核崩溃"]
    case .ghostScreens(let count):
        ["有 \(count) 块已拔掉的屏仍被当成在线（残影屏）",
         "窗口困在上面时，在面板里关掉它们就能找回",
         "之后重启电脑"]
    case .unknown:
        ["读不到系统日志（需要管理员账户），无法判断是否卡死"]
    }
}
