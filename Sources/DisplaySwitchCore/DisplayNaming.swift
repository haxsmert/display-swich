import CoreGraphics

/// 菜单显示名:系统名(已含序号区分,如 "Mi Monitor (1)")+ 主屏标记。
public func displayLabel(for display: DisplayInfo) -> String {
    let base = display.name.isEmpty ? "显示器" : display.name
    return display.isMain ? "\(base)（主）" : base
}
