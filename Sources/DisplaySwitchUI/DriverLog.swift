import Foundation

/// 从系统日志里查雷雳显示驱动卡死的特征(判据与实测依据见 `DriverHealth`)。
enum DriverLog {
    /// 只认内核里这个驱动报的这一句;限定 `process == "kernel"`,
    /// 否则 `log` 命令自己那条「带着哪些参数运行」的记录也会命中(实测)。
    private static let predicate =
        #"process == "kernel" AND sender == "AppleThunderboltDPOutAdapter" AND eventMessage CONTAINS "evaluating for > 1m""#

    /// 近 2 分钟里卡死特征出现的条数;读不到日志(非管理员账户、命令失败或超时)时为 nil。
    /// 耗时约 1 秒,只能在后台线程调。
    static func recentWedgeLines() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--last", "2m", "--style", "compact", "--predicate", predicate]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // 万一 log 命令卡住,10 秒后掐掉,当作读不到。
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .filter { $0.contains("evaluating for > 1m") }
            .count
    }
}
