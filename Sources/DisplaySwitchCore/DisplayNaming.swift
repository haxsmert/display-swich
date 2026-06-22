import CoreGraphics
import Foundation

/// 去掉系统名末尾的 " (N)" 消歧后缀。系统这个编号是「动态消歧」:仅当同名屏同时在场时才出现,
/// 关掉其一就消失,不稳定。我们按整组、绑定 UUID 自行编号,故先剥掉它取得稳定基名。
func baseName(_ name: String) -> String {
    let stripped = name.replacingOccurrences(
        of: #"\s*\(\d+\)$"#, with: "", options: .regularExpression)
    return stripped.isEmpty ? "显示器" : stripped
}

/// 单块屏标签:稳定基名 + 主屏标记(无消歧上下文、或同名屏唯一时用)。
public func displayLabel(for display: DisplayInfo) -> String {
    let base = baseName(display.name)
    return display.isMain ? "\(base)（主）" : base
}

/// 整组屏的稳定标签:同基名有多块时编号 (1)(2)…,唯一则不加号;主屏额外加(主)。
/// 编号**绑定 UUID(稳定标识)、与屏的位置无关**——关闭/重开/主屏转移导致 bounds 漂移时,
/// 同一块物理屏始终是同一个号。编号基于传入的「整组」(应含已关闭快照),故关掉同名其一也不丢号。
public func displayLabels(for displays: [DisplayInfo]) -> [CGDirectDisplayID: String] {
    var groups: [String: [DisplayInfo]] = [:]
    for d in displays { groups[baseName(d.name), default: []].append(d) }
    var labels: [CGDirectDisplayID: String] = [:]
    for (base, members) in groups {
        // 按稳定标识排序后编号;UUID 取不到时用 displayID 兜底,保证全序稳定。
        let ordered = members.sorted { ($0.uuid, $0.id) < ($1.uuid, $1.id) }
        for (index, d) in ordered.enumerated() {
            var label = ordered.count > 1 ? "\(base) (\(index + 1))" : base
            if d.isMain { label += "（主）" }
            labels[d.id] = label
        }
    }
    return labels
}
