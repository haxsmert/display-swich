import AppKit
import SwiftUI
import DisplaySwitchCore

/// 菜单栏弹出面板。
///
/// 视觉取法 macOS 27 自己的菜单栏面板:底是系统材质(见 `PanelBackground`);行没有底色与描边,
/// 开关状态由行首的圆形图标表达——开着是强调色实心圆、白色图形,关着是浅灰圆(同控制中心的
/// Wi-Fi、蓝牙);鼠标经过时整行是系统菜单那样的强调色选中底,文字与图标转白(见 `SelectionBackground`)。
/// 不用鼠标悬停提示(他认为低级):需要说明的话直接写在顶部的提示区。
///
/// **布局在交互中保持不动**:每行高度固定;锁住原因写在顶部提示区(他的设计),
/// 不在行里加字——曾因多出一行让面板长高、整体跳动,打乱他接下来要点的位置(2026-10-22)。
/// 宽度按内容定(他嫌固定的 320pt 太宽),而开关屏、主屏转移时会变的文字都按最长的写法预留,
/// 所以面板只在屏幕增减时才会变宽变窄,点来点去不会。
public struct PanelView: View {
    @ObservedObject var model: PanelModel

    public init(model: PanelModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.supported { unsupportedNotice }
            VStack(spacing: 0) {
                if model.items.isEmpty {
                    Text("没有检测到显示器")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                ForEach(model.items, id: \.id) { item in
                    DisplayRow(item: item, supported: model.supported, lockedTaps: model.lockedTaps) { model.toggle(item.id) }
                }
            }
            // 行与面板边缘的间距照系统菜单选中底的实测值(5pt,macOS 27)。
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
            Divider()
            statusBar
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 标题取系统自己的叫法:控制中心与系统设置里都叫「显示器」(曾叫「显示器开关」,他嫌土)。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("显示器")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 16)
            // 提示区(他的设计):平时空着,只剩最后一块亮着被锁住时写原因,原地淡入淡出。
            // 锁形图标嵌在文字里、随文字排版:单独摆一个图标会把这一行撑高 1pt,面板跟着跳(截图实测)。
            ZStack(alignment: .trailing) {
                Self.hintText(lockReasonText).hidden()          // 按会出现的那句预留宽度,提示出现时面板不变宽
                if let hint = model.hint {
                    Self.hintText(hint)
                        .shakes(on: model.lockedTaps)
                        .transition(.opacity)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .animation(.easeInOut(duration: 0.15), value: model.hint)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 8)
    }

    private static func hintText(_ hint: String) -> some View {
        Text("\(Image(systemName: "lock.fill")) \(hint)").imageScale(.small)
    }

    private var unsupportedNotice: some View {
        Label("此设备不支持开关显示器（需 Apple Silicon 与受支持的 macOS），只能查看",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.bottom, 8)
    }

    /// 底部状态栏(取法 WhatCable 的底栏,他的建议):一行小字,左边开发者工具,右边版本与退出。
    /// 「全黑救援已就绪」曾常驻这里,他指出会误导:普通使用用不着知道它,挪进开发者工具。
    private var statusBar: some View {
        HStack(spacing: 6) {
            DeveloperMenu(model: model)
            Spacer(minLength: 16)
            Button(model.versionText, action: model.openRepository)
                .buttonStyle(QuietTextButtonStyle())
            Text("·").foregroundStyle(.tertiary)
            Button("退出", action: model.quit)
                .buttonStyle(QuietTextButtonStyle())
                .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// 开发者工具:点图标弹出系统菜单,开发、排查用的东西都在这里,平时不占面板地方。
/// 菜单里的条目是固定的几项,不随记录增多而变长;日志文件本身也有上限(见 `RescueLog`)。
private struct DeveloperMenu: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        Menu {
            Section("全黑救援（拔线导致没有一块屏亮着时，自动点亮）") {
                Text(model.supported ? "状态：已就绪" : "状态：不可用，此设备不支持开关显示器")
                Text(model.lastRescue.map { "上次触发：\(Self.relative($0))" } ?? "上次触发：从未")
            }
            Divider()
            Button("打开救援日志", action: model.openRescueLog)
            Button("复制诊断信息", action: model.copyDiagnostics)
        } label: {
            // 与状态栏的小字同大小、同颜色:这是给开发、排查用的入口,不该比别的东西显眼。
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("开发者工具")
    }

    /// 今天的只写时刻,更早的带上日期。
    private static func relative(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M 月 d 日 HH:mm"
        return f.string(from: date)
    }
}

/// 一块屏一行,**整行就是开关**:点一下就切换,没有任何开关控件(他的要求)。
/// 状态由行首圆形图标表达,关着时文字变淡并写「已关闭」——不只靠颜色。
/// 被锁住时行尾一把小锁,原因写在顶部提示区;这一行切不了,但点了要有反应:锁与顶部提示一起抖一下
/// (他的要求)。所以它不设成不可点,只是鼠标经过时不给选中底——选中底表示「点了会切换」。
private struct DisplayRow: View {
    let item: DisplayMenuItem
    let supported: Bool
    let lockedTaps: Int
    let toggle: () -> Void

    private var locked: Bool { item.isOn && !item.canToggleOff }
    private var clickable: Bool { supported && !locked }
    /// 鼠标在不在这一行上。在行外层跟踪(不放进按钮样式):行被锁住时按钮不收悬停事件,
    /// 鼠标趁这时离开,解锁后这一行会一直亮着高亮(他的截图里最后一行就是)。
    @State private var hovering = false
    private var highlighted: Bool { hovering && clickable }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                StatusIcon(symbol: item.isBuiltin ? "laptopcomputer" : "display", isOn: item.isOn, highlighted: highlighted)
                VStack(alignment: .leading, spacing: 2) {
                    // 隐藏的那句是这一行可能出现的最长写法,只占宽度不显示,见 `DisplayMenuItem.sizingLabel`。
                    ZStack(alignment: .leading) {
                        Text(item.sizingLabel).hidden()
                        Text(item.label)
                            .foregroundStyle(highlighted ? Self.selectedText : item.isOn ? .primary : .secondary)
                    }
                    .font(.system(size: 13, weight: .medium))
                    ZStack(alignment: .leading) {
                        Text(item.sizingDetail).hidden()
                        Text(item.detail)
                            .foregroundStyle(highlighted ? AnyShapeStyle(Self.selectedText.opacity(0.8))
                                         : item.isOn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    }
                    .font(.system(size: 11))
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .animatingOnly(.easeInOut(duration: 0.2)) { $0.opacity(locked ? 1 : 0) }
                    .shakes(on: lockedTaps)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
            .background { if highlighted { SelectionBackground() } }
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!supported)
        .onHover { inside in
            // 选中底跟系统菜单一样即时出现、即时消失,不带渐变:行首图标的颜色动画只给开关用。
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { hovering = inside }
        }
        .accessibilityLabel("\(item.label),\(item.isOn ? "已打开" : "已关闭")")
        .accessibilityHint(clickable ? (item.isOn ? "点击关掉" : "点击打开") : (item.lockReason ?? ""))
    }

    /// 选中底上的文字色,用系统给菜单选中项定的那个。
    static let selectedText = Color(nsColor: .selectedMenuItemTextColor)
}

/// 行首的圆形状态图标(取法控制中心):开着为强调色实心圆 + 白色图形,关着为浅灰圆 + 灰色图形。
/// 行被选中(蓝底)时反过来:开着是白色实心圆 + 强调色图形,关着是半透明白圆 + 白色图形——
/// 不然开着的蓝圆落在蓝底上就看不见了(系统菜单里的图标在选中时同样转白)。
/// 开关时的动画**只作用在颜色与透明度上**,原地渐变,见 `animatingOnly`。
private struct StatusIcon: View {
    let symbol: String
    let isOn: Bool
    let highlighted: Bool

    private static let accent = Color(nsColor: .controlAccentColor)

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? DisplayRow.selectedText.opacity(0.25) : Color.primary.opacity(0.08))
            Circle()
                .fill(highlighted ? DisplayRow.selectedText : Self.accent)
                .animatingOnly(.easeInOut(duration: 0.2)) { $0.opacity(isOn ? 1 : 0) }
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .animatingOnly(.easeInOut(duration: 0.2)) {
                    $0.foregroundStyle(highlighted ? (isOn ? Self.accent : DisplayRow.selectedText)
                                                   : (isOn ? Color.white : Color.secondary))
                }
        }
        .frame(width: 28, height: 28)
    }
}

/// 鼠标经过时的整行底,照系统菜单的选中项:强调色实心圆角块,离面板边缘 5pt、圆角 5pt(macOS 27 实测)。
/// 颜色直接用系统强调色(随「系统设置 › 外观」里选的强调色变):同一块屏上,系统菜单选中底与面板里
/// 强调色实心圆的像素一模一样(55, 123, 249)。试过 SDK 推荐的「选中」材质,它在玻璃里是半透明的,
/// 渲染成发白的 (107, 160, 250),比系统菜单浅一截。
private struct SelectionBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(nsColor: .controlAccentColor))
    }
}

extension View {
    /// `trigger` 每变一次,左右抖一下——macOS 拒绝输入时的说法(输错密码时登录框那样抖)。
    /// 只是绘制时的偏移,不改排版,别的东西不会跟着动。macOS 13 没有关键帧动画,不抖。
    @ViewBuilder
    func shakes(on trigger: Int) -> some View {
        if #available(macOS 14.0, *) {
            keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-5, duration: 0.05)
                    CubicKeyframe(5, duration: 0.08)
                    CubicKeyframe(-4, duration: 0.08)
                    CubicKeyframe(3, duration: 0.07)
                    CubicKeyframe(-1.5, duration: 0.06)
                    CubicKeyframe(0, duration: 0.06)
                }
            }
        } else {
            self
        }
    }

    /// 只让 `body` 里加的修饰(颜色、透明度)带动画,位置与尺寸的变化一律直接到位。
    ///
    /// 不用 `.animation(_:value:)`:它会把**同一次刷新里**这块视图的位置变化也一起动画。
    /// 曾因此,行在那一刻被挪动(见 `DisplayController.activeDisplays()`)时,圆形图标从别的位置
    /// 一路滑过来——先是「蓝色从别处浮过来」,后是「从上往下滑出来」(他两次指出,2026-10-22)。
    /// macOS 13 没有限定范围的动画,直接到位、不做动画。
    @ViewBuilder
    func animatingOnly<Modified: View>(_ animation: Animation,
                                       @ViewBuilder _ body: @escaping (AnyView) -> Modified) -> some View {
        if #available(macOS 14.0, *) {
            self.animation(animation) { body(AnyView($0)) }
        } else {
            body(AnyView(self))
        }
    }
}

/// 行按钮不要任何按下效果:反馈就是切换本身(或被锁时的抖动),与系统菜单一致。
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// 底部文字按钮:不描边、不铺底,平时次要色,鼠标经过时变成主色——安静但可发现。
private struct QuietTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration)
    }

    private struct QuietBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
