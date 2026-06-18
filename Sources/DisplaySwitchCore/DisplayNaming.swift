import CoreGraphics

/// 为某块外接屏生成菜单显示名:基名 +(位置·主屏)。
public func displayLabel(for display: DisplayInfo, among externals: [DisplayInfo]) -> String {
    let base = display.name.isEmpty ? "显示器" : display.name
    var tags: [String] = []

    let sorted = externals.sorted { $0.bounds.minX < $1.bounds.minX }
    if let idx = sorted.firstIndex(where: { $0.id == display.id }) {
        if sorted.count == 2 {
            tags.append(idx == 0 ? "左" : "右")
        } else if sorted.count > 2 {
            tags.append("#\(idx + 1)")
        }
    }
    if display.isMain { tags.append("主屏") }

    return tags.isEmpty ? base : "\(base)（\(tags.joined(separator: "·"))）"
}
