import AppKit

/// 面板的底:直接用系统自己的材质组件,不自己画(他的要求:用 mac 官方组件,保持原生风格)。
///
/// macOS 26 起是 `NSGlassEffectView`——菜单栏菜单、控制中心同款的系统玻璃。系统「外观」里的玻璃样式、
/// 「辅助功能 › 减少透明度」这类设置由系统直接作用在它上面,面板与系统同步变化,不用我们跟。
/// 更早的系统用 `NSVisualEffectView` 的菜单材质(同样随系统设置变化)。
///
/// 曾自己画过一个带指向箭头的外框:他先是嫌面板离图标太远、建议加箭头,
/// 看过之后改为要和 mac 一样的纯圆角矩形(2026-10-22)。
public enum PanelBackground {
    /// 圆角取系统菜单栏菜单的实测值:macOS 27 上弹出一个临时菜单截图,逐行量左上角边缘
    /// 在约 26px(13pt)处收直(2026-10-22)。
    public static let cornerRadius: CGFloat = 13

    /// 把 `content` 放进系统材质里,返回给窗口当 `contentView`。
    public static func wrapping(_ content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        // 窗口背后的模糊要靠遮罩图才能裁成圆角;可拉伸的遮罩,四角保持圆角。
        let r = cornerRadius
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        effect.maskImage = mask
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }
}
