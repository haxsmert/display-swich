import Foundation

/// 日志超过 `limit` 字节时,只留最新的一段:从末尾往前约 `limit / 2` 处的下一个整行开始。
/// 没超过返回 nil(不用动)。只留一半,是为了清一次能管很久,不必每写一条就重写一遍文件。
public func trimmedLog(_ data: Data, limit: Int) -> Data? {
    guard data.count > limit else { return nil }
    let start = data.index(data.endIndex, offsetBy: -(limit / 2))
    guard let newline = data[start...].firstIndex(of: UInt8(ascii: "\n")) else { return Data() }
    return Data(data[data.index(after: newline)...])
}
