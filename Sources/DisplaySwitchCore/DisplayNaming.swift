import CoreGraphics
import Foundation

/// 去掉系统名末尾的 " (N)" 消歧后缀。系统这个编号是「动态消歧」:仅当同名屏同时在场时才出现,
/// 关掉其一就消失,不稳定。我们按整组、绑定 UUID 自行编号,故先剥掉它取得稳定基名。
func baseName(_ name: String) -> String {
    let stripped = name.replacingOccurrences(
        of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    return stripped.isEmpty ? "显示器" : stripped
}

/// 标签末尾的主屏标记。
let mainMarker = "（主）"

/// 单块屏标签:稳定基名 + 主屏标记(无消歧上下文、或同名屏唯一时用)。
public func displayLabel(for display: DisplayInfo) -> String {
    let base = baseName(display.name)
    return display.isMain ? base + mainMarker : base
}

/// 同名屏之间排序、编号用的身份:有序列号文本就用它,没有才用系统的 UUID。
///
/// 只用 UUID 不够(2026-10-23 他换接口后发现同一台屏从 (2) 变成 (1)):他的两台同型号屏 EDID 只差序列号文本,
/// 系统给这类屏的 UUID 跟着接法走——显示偏好里这一型号累计分到了 10 个 UUID,而显示器只有两台。
/// 序列号文本是显示器自己报的,换口、换坞都不变。
func identityKey(of d: DisplayInfo) -> String {
    d.serial.isEmpty ? "uuid:" + d.uuid : "serial:" + d.serial
}

/// 整组屏的稳定标签:同基名有多块时编号 (1)(2)…,唯一则不加号;主屏额外加(主)。
/// 编号**绑定显示器身份(`identityKey(of:)`)、与屏的位置无关**——关闭/重开/主屏转移导致 bounds 漂移、
/// 换接口导致 UUID 与 display ID 变化时,同一台物理屏始终是同一个号。
/// 编号基于传入的「整组」(应含已关闭快照),故关掉同名其一也不丢号。
public func displayLabels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: String] {
    var groups: [String: [DisplayInfo]] = [:]
    for d in displays { groups[baseName(d.name), default: []].append(d) }
    var labels: [CGDirectDisplayID: String] = [:]
    for (base, members) in groups {
        // 按身份排序后编号;序列号相同(有的厂商每台都写一样)时退到 UUID、再到 displayID,保证全序确定。
        let ordered = members.sorted { (identityKey(of: $0), $0.uuid, $0.id) < (identityKey(of: $1), $1.uuid, $1.id) }
        for (index, d) in ordered.enumerated() {
            var label = ordered.count > 1 ? "\(base) (\(index + 1))" : base
            if d.isMain { label += mainMarker }
            labels[d.id] = label
        }
    }
    return labels
}
