import Foundation

/// 救援路径的诊断日志。
///
/// 为什么非要有:全黑时用户看不到任何界面,菜单栏也点不开——救援若失败,现场随强制重启一起消失,
/// 事后无从判断「通知到底到没到、判据是多少、恢复调用成没成」。日志是这条路径唯一的黑匣子。
/// 2026-09-18 的事故能在几分钟内定位到确切环节,全靠它。只在救援相关事件发生时写,平时不产生一个字节。
public enum RescueLog {
    public static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DisplaySwitch.log")

    /// 与**上一条**完全相同的消息不重复写。
    /// 事件源天然会重复派发(一次拔线实测来 6 条终止通知),状态没变时消息也一字不差——
    /// 重复记录只会把真正的现场淹没。只比上一条,所以状态变过又变回来仍会重新记录。
    private static var lastMessage: String?

    /// 最近一次真的下了恢复指令的时间;从没救援过、或日志读不到时为 nil。面板底部显示它。
    public static func lastRescueDate() -> Date? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let line = text.split(separator: "\n").last(where: { $0.contains("已下恢复指令") }),
              let open = line.firstIndex(of: "["), let close = line.firstIndex(of: "]") else { return nil }
        return ISO8601DateFormatter().date(from: String(line[line.index(after: open)..<close]))
    }

    public static func write(_ message: String) {
        guard message != lastMessage else { return }
        lastMessage = message
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "[\(stamp)] \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
