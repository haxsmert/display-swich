import CoreGraphics
import Foundation

/// 去掉系统名末尾的 " (N)" 消歧后缀,得到基名。只用于分组(哪些屏同型号)与预留宽度,不用于显示。
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

/// 一块屏的标签:照抄系统的叫法,包括系统给同名屏加的 (1)(2);主屏额外加(主)。
///
/// 为什么不自己编号(他的决定,2026-10-23):面板与系统设置里的名字要对得上。系统的 (1)(2) 跟着接法走——
/// 换个口、关掉同名的另一块,号都可能变或消失——但这是系统的叫法,我们改不了:系统设置里没有改名入口,
/// 显示器覆盖文件只能按厂商 + 型号改,同型号的两台会被改成同一个名字。自己编一套稳定的号,就会和系统设置对不上。
/// 分清是哪一台靠两样:行的顺序按显示器身份排(`identityKey(of:)`,不随系统改号而跳),
/// 说明行写序列号尾号(`serialTails(for:)`)。
public func displayLabel(for display: DisplayInfo) -> String {
    let name = display.name.isEmpty ? "显示器" : display.name
    return display.isMain ? name + mainMarker : name
}

/// 标签可能出现的最长写法,界面按它预留宽度(他不要开关屏时面板变宽)。
/// 同名屏不止一块、或名字已带系统的号时,系统随时可能加上或去掉 (N),按带号写;
/// 任何亮着的屏都可能成为主屏,都带主屏标记。
func sizingLabel(for display: DisplayInfo, sameNameCount: Int) -> String {
    let number = max(systemNumber(in: display.name) ?? 0, sameNameCount)
    let name = number > 1 ? "\(baseName(display.name)) (\(number))" : (display.name.isEmpty ? "显示器" : display.name)
    return name + mainMarker
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
/// 只给基名相同、不止一块、且读得到序列号的屏;取末 4 位,同组里撞了就加长到能分开为止。
/// 只露尾号:完整序列号是设备标识,不必整串出现在截图里。
func serialTails(for displays: [DisplayInfo]) -> [CGDirectDisplayID: String] {
    var groups: [String: [DisplayInfo]] = [:]
    for d in displays where !d.serial.isEmpty { groups[baseName(d.name), default: []].append(d) }
    var tails: [CGDirectDisplayID: String] = [:]
    for members in groups.values where members.count > 1 {
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
