import SwiftUI

/// 面板顶边箭头该指向哪里(相对面板左边缘的横坐标)。由摆放面板的一方按图标位置更新;
/// `nil` 表示居中(截图工具用)。
public final class PanelArrow: ObservableObject {
    @Published public var x: CGFloat?
    public init(x: CGFloat? = nil) { self.x = x }
}

/// 面板外框:实底圆角 + 顶边一个指向菜单栏图标的小箭头,与系统弹出面板的样子一致,
/// 让人一眼看出面板属于哪个图标。面板被屏幕边缘往里推时,箭头仍对准图标。
public struct PanelChrome<Content: View>: View {
    @ObservedObject var arrow: PanelArrow
    let content: Content

    static var arrowHeight: CGFloat { 9 }

    public init(arrow: PanelArrow, @ViewBuilder content: () -> Content) {
        self.arrow = arrow
        self.content = content()
    }

    public var body: some View {
        let shape = CalloutShape(arrowX: arrow.x, arrowHeight: Self.arrowHeight)
        // 只画底与边,不裁剪内容:面板内容都在圆角以内(卡片有内边距、分隔线不进圆角区),无需裁剪;
        // 而裁剪会让按钮里的图标在截图工具的离屏渲染中丢失(实测,app 里不受影响)。
        content
            .padding(.top, Self.arrowHeight)
            .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// 圆角矩形,顶边在 `arrowX` 处向上凸出一个箭头(箭尖略圆,与系统弹出面板接近)。
struct CalloutShape: Shape {
    var arrowX: CGFloat?
    var arrowHeight: CGFloat
    var arrowWidth: CGFloat = 20
    var cornerRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let top = rect.minY + arrowHeight
        let r = min(cornerRadius, (rect.maxY - top) / 2)
        let half = arrowWidth / 2
        // 箭头不能伸进圆角里:夹在两个圆角之间。
        let cx = min(max(arrowX ?? rect.midX, rect.minX + r + half), rect.maxX - r - half)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: top))
        p.addLine(to: CGPoint(x: cx - half, y: top))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), control: CGPoint(x: cx - half * 0.35, y: top - arrowHeight * 0.1))
        p.addQuadCurve(to: CGPoint(x: cx + half, y: top), control: CGPoint(x: cx + half * 0.35, y: top - arrowHeight * 0.1))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: top + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: top + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: top + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
