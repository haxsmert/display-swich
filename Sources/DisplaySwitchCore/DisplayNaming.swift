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

/// 单块屏的标签(同名只有它一块时):显示器自己的名字(去掉系统的 (N))+ 主屏标记。
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

/// 整组屏(活跃 + 已关闭)每块的写法:同型号屏带系统设置里的号 (1)(2),说明行再写序列号尾号(他的决定,2026-10-23)。
///
/// 号要和系统设置对得上(他:「不然用户怎么和系统设置里的屏幕对上」),所以两块都亮着时**照抄系统此刻给的号**。
/// 但系统的号是「动态消歧」:关掉同名的另一块,剩下那块的号就被系统去掉——这个他明确不要(「动态关闭后缀 1、2 很没道理」)。
/// 所以号不随开关消失:关掉的屏用关掉前的号(快照里的名字带着),亮着但此刻没被系统编号的屏用它上次的号(`knownNumbers`,
/// 按显示器身份记)。哪块都没有、或号撞了,补最小的空号。系统重新编号(换口、重开后可能对调)时跟着系统走。
/// 认出是哪一台不靠号,靠尾号与行序(按 `identityKey(of:)` 排,见 `DisplayController.menuItems`)。
/// 同名只有一块时不编号,同系统设置。
func displayNames(for displays: [DisplayInfo], knownNumbers: [String: Int]) -> [CGDirectDisplayID: DisplayNames] {
    let tails = serialTails(for: displays)
    var groups: [String: [DisplayInfo]] = [:]
    for d in displays { groups[baseName(d.name), default: []].append(d) }
    var result: [CGDirectDisplayID: DisplayNames] = [:]
    for (base, group) in groups {
        guard group.count > 1 else {
            let d = group[0]
            result[d.id] = DisplayNames(label: displayLabel(for: d), sizingLabel: base + mainMarker, serialTail: tails[d.id])
            continue
        }
        let members = group.sorted { (identityKey(of: $0), $0.uuid, $0.id) < (identityKey(of: $1), $1.uuid, $1.id) }
        var number: [CGDirectDisplayID: Int] = [:]
        var taken = Set<Int>()
        func assign(_ d: DisplayInfo, _ n: Int?) {
            guard number[d.id] == nil, let n, n > 0, !taken.contains(n) else { return }
            number[d.id] = n
            taken.insert(n)
        }
        // 先后:系统此刻给的号 → 关掉的屏关掉那一刻的号(快照名字里的)→ 上次记下的号 → 补最小的空号。
        // 关掉那一刻两块是系统同时编的号,不会撞;撞只会来自很久以前记下的号,所以它排在快照后面。
        for d in members where d.isActive { assign(d, systemNumber(in: d.name)) }
        for d in members where !d.isActive { assign(d, systemNumber(in: d.name)) }
        for d in members { assign(d, knownNumbers[identityKey(of: d)]) }
        for d in members where number[d.id] == nil { assign(d, (1...).first { !taken.contains($0) }) }
        let widest = max(group.count, taken.max() ?? 0)
        for d in members {
            let name = "\(base) (\(number[d.id] ?? 0))"
            result[d.id] = DisplayNames(label: d.isMain ? name + mainMarker : name,
                                        sizingLabel: "\(base) (\(widest))" + mainMarker, serialTail: tails[d.id])
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
