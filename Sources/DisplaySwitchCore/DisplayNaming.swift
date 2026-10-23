import CoreGraphics
import Foundation

/// 去掉系统名末尾的 " (N)" 消歧后缀,得到基名(显示器自己报的名字,如 `External Display`)。
func baseName(_ name: String) -> String {
    let stripped = name.replacingOccurrences(
        of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    return stripped.isEmpty ? "显示器" : stripped
}

/// 系统名末尾 " (N)" 里的 N;没有就是 nil。
func systemNumber(in name: String) -> Int? {
    guard let range = name.range(of: #"\((\d+)\)$"#, options: .regularExpression) else { return nil }
    return Int(name[range].dropFirst().dropLast())
}

/// 标签末尾的主屏标记。
let mainMarker = "（主）"

/// 单块屏的标签:显示器自己的名字(去掉系统的 (N))+ 主屏标记。
public func displayLabel(for display: DisplayInfo) -> String {
    let base = baseName(display.name)
    return display.isMain ? base + mainMarker : base
}

/// 一块屏在面板上的写法。
struct DisplayNames: Equatable {
    let label: String
    /// 标签可能出现的最长写法,界面按它预留宽度(他不要开关屏时面板变宽);任何亮着的屏都可能成为主屏,都带主屏标记。
    let sizingLabel: String
    /// 序列号尾号,同型号屏才有,写进说明行。
    let serialTail: String?
}

/// 整组屏(活跃 + 已关闭)每块的写法:名字用显示器自己的名字,同型号屏靠序列号尾号分清(他的决定,2026-10-23)。
///
/// 系统给同名屏加的 (1)(2) 不用:它跟着接法走,换个口、关掉同名的另一块,号就变或消失;有了序列号尾号它就没有用处。
/// 也不自己编号:自编的号与系统设置对不上(试过,他否了)。唯一的例外是**读不到序列号**的同型号屏——没有尾号可看,
/// 只好照抄系统的叫法,至少此刻分得开。行的顺序按显示器身份排(`identityKey(of:)`),见 `DisplayController.menuItems`。
func displayNames(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DisplayNames] {
    let tails = serialTails(for: displays)
    var sameName: [String: Int] = [:]
    for d in displays { sameName[baseName(d.name), default: 0] += 1 }
    var result: [CGDirectDisplayID: DisplayNames] = [:]
    for d in displays {
        let base = baseName(d.name)
        let count = sameName[base] ?? 1
        let tail = tails[d.id]
        if count > 1 && tail == nil {
            let name = d.name.isEmpty ? base : d.name
            let widest = max(count, systemNumber(in: d.name) ?? 0)
            result[d.id] = DisplayNames(label: d.isMain ? name + mainMarker : name,
                                        sizingLabel: "\(base) (\(widest))" + mainMarker, serialTail: nil)
        } else {
            result[d.id] = DisplayNames(label: displayLabel(for: d), sizingLabel: base + mainMarker, serialTail: tail)
        }
    }
    return result
}

/// 同名屏之间排序用的身份:有序列号文本就用它,没有才用系统的 UUID。
///
/// 只用 UUID 不够(2026-10-23 他换接口后发现同一台屏从 (2) 变成 (1)):他的两台同型号屏 EDID 只差序列号文本,
/// 系统给这类屏的 UUID 跟着接法走——显示偏好里这一型号累计分到了 10 个 UUID,而显示器只有两台。
/// 序列号文本是显示器自己报的,换口、换坞都不变。
func identityKey(of d: DisplayInfo) -> String {
    d.serial.isEmpty ? "uuid:" + d.uuid : "serial:" + d.serial
}

/// 同型号屏的序列号尾号,写进说明行,让人分得清是哪一台(他的提议,2026-10-23:「把唯一码放出来」)。
/// 只给基名相同、不止一块的屏里读得到序列号的那些;取末 4 位,同组里撞了就加长到能分开为止。
/// 只露尾号:完整序列号是设备标识,不必整串出现在截图里。
func serialTails(for displays: [DisplayInfo]) -> [CGDirectDisplayID: String] {
    var groups: [String: [DisplayInfo]] = [:]
    for d in displays { groups[baseName(d.name), default: []].append(d) }
    var tails: [CGDirectDisplayID: String] = [:]
    for group in groups.values where group.count > 1 {
        let members = group.filter { !$0.serial.isEmpty }
        guard !members.isEmpty else { continue }
        let longest = members.map(\.serial.count).max() ?? 0
        var length = min(4, longest)
        while length < longest, Set(members.map { $0.serial.suffix(length) }).count < members.count { length += 1 }
        for d in members {
            let tail = String(d.serial.suffix(length))
            tails[d.id] = tail.count < d.serial.count ? "…" + tail : tail
        }
    }
    return tails
}
