import AppKit
import SwiftUI
import DisplaySwitchCore

/// 菜单栏弹出面板。
///
/// 视觉照抄菜单栏的 Wi-Fi 菜单(他指定的参照):图标、文字、锁、悬停底、动效都与它逐像素对照过
/// (macOS 27,2026-10-23:临时垫一块纯白窗口在两者背后,截图比颜色、尺寸与「墨量」)。
/// 底是系统材质(见 `PanelBackground`);行没有底色与描边,开关状态只由行首的圆形图标表达,
/// 文字不因开关变淡——Wi-Fi 菜单里没连上的网络也是同样的黑字,见 `StatusIcon`;
/// 鼠标经过时整行一层浅灰圆角底,图标与文字不变,见 `HoverBackground`。
/// Wi-Fi 的每行只有一行字,两行字的行(名字 + 说明行)照系统菜单项自带的「副标题」写法,见 `DisplayRow`。
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
            // 行与面板边缘的间距照 Wi-Fi 菜单悬停底的实测值(7pt,macOS 27)。
            .padding(.horizontal, 7)
            .padding(.bottom, 5)
            Divider().padding(.horizontal, 14)          // 分隔线两头缩进,同 Wi-Fi 菜单
            statusBar
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 标题取系统自己的叫法:控制中心与系统设置里都叫「显示器」(曾叫「显示器开关」,他嫌土)。
    /// 字号、字重、颜色同 Wi-Fi 菜单的标题:13pt 半粗,控件文字色(实测最深处 (38, 38, 38),不是纯黑)。
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("显示器")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlTextColor))
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

    /// 底部状态栏(取法 WhatCable 的底栏,他的建议):一行小字,左边显示驱动状态(点开是开发者工具),
    /// 右边版本与退出。「全黑救援已就绪」曾常驻这里,他指出会误导:普通使用用不着知道它,挪进开发者工具。
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

/// 开发者工具:状态栏左边那一组(工具图标 + 显示驱动状态),点开是系统菜单,
/// 开发、排查用的东西都在这里,平时不占面板地方。菜单里的条目是固定的几项,不随记录增多而变长;
/// 日志文件本身也有上限(见 `RescueLog`)。
private struct DeveloperMenu: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        Menu {
            Section("显示驱动") {
                ForEach(driverStatusDetails(model.driverHealth), id: \.self) { Text($0) }
                if let at = model.driverCheckedAt { Text("上次检查：\(Self.relative(at, seconds: true))") }
                Button("重新检查") { model.refreshDriverHealth(force: true) }
            }
            Section("全黑救援（拔线导致没有一块屏亮着时，自动点亮）") {
                Text(model.supported ? "状态：已就绪" : "状态：不可用，此设备不支持开关显示器")
                Text(model.lastRescue.map { "上次触发：\(Self.relative($0))" } ?? "上次触发：从未")
            }
            Divider()
            Button("打开救援日志", action: model.openRescueLog)
            Button("复制诊断信息", action: model.copyDiagnostics)
        } label: {
            // 与状态栏的小字同大小、同颜色:这是给开发、排查用的入口,不该比别的东西显眼;
            // 只有驱动出问题时,圆点与文字变橙色。
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                Circle().fill(statusColor).frame(width: 6, height: 6)
                ZStack(alignment: .leading) {
                    ForEach(driverStatusLabels, id: \.self) { Text($0).hidden() }   // 按最长的一句预留宽度
                    Text(driverStatusLabel(model.driverHealth)).foregroundStyle(problem ? Color(nsColor: .systemOrange) : .secondary)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("开发者工具，\(driverStatusLabel(model.driverHealth))")
    }

    private var problem: Bool {
        switch model.driverHealth {
        case .wedged, .ghostScreens: true
        default: false
        }
    }

    private var statusColor: Color {
        switch model.driverHealth {
        case .normal: Color(nsColor: .systemGreen)
        case .wedged, .ghostScreens: Color(nsColor: .systemOrange)
        case .checking, .unknown: Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// 今天的只写时刻,更早的带上日期。
    private static func relative(_ date: Date, seconds: Bool = false) -> String {
        let f = DateFormatter()
        let time = seconds ? "HH:mm:ss" : "HH:mm"
        f.dateFormat = Calendar.current.isDateInToday(date) ? "今天 \(time)" : "M 月 d 日 \(time)"
        return f.string(from: date)
    }
}

/// 一块屏一行,**整行就是开关**:点一下就切换,没有任何开关控件(他的要求)。
/// 状态由行首圆形图标表达,说明行写「已关闭」——不只靠颜色。
/// 被锁住时行尾一把锁,原因写在顶部提示区;这一行切不了,但点了要有反应:锁与顶部提示一起抖一下
/// (他的要求)。所以它不设成不可点,只是鼠标经过时不给悬停底——悬停底表示「点了会切换」。
///
/// 量出来的规格(macOS 27):
/// - 照 Wi-Fi 菜单:圆离面板边缘 14pt,圆到文字 8pt;名字 13pt 常规体、控件文字色(曾用中等字重,偏粗);
///   锁是 13pt 的 `lock.fill`、次要色,尺寸、墨量、颜色三项都与 Wi-Fi 的锁吻合(曾用 11pt,偏小)。
/// - 照系统菜单项的「副标题」(`NSMenuItem.subtitle`,弹一个临时菜单实测):两行字的行高 36pt,
///   上下两行顶到顶 15pt,副标题用 `secondaryLabelColor`。曾是 46pt、行间多 2pt、说明行偏浅,比原生松散。
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
            HStack(spacing: 8) {
                StatusIcon(symbol: item.isBuiltin ? "laptopcomputer" : "display", isOn: item.isOn)
                VStack(alignment: .leading, spacing: 0) {
                    // 隐藏的那句是这一行可能出现的最长写法,只占宽度不显示,见 `DisplayMenuItem.sizingLabel`。
                    ZStack(alignment: .leading) {
                        Text(item.sizingLabel).hidden()
                        Text(item.label)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .controlTextColor))
                    ZStack(alignment: .leading) {
                        Text(item.sizingDetail).hidden()
                        Text(item.detail)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .animatingOnly(.easeInOut(duration: 0.2)) { $0.opacity(locked ? 1 : 0) }
                    .shakes(on: lockedTaps)
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background { if highlighted { HoverBackground() } }
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!supported)
        .onHover { inside in
            // 悬停底跟 Wi-Fi 菜单一样即时出现、即时消失,不带渐变。
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { hovering = inside }
        }
        .accessibilityLabel("\(item.label),\(item.isOn ? "已打开" : "已关闭")")
        .accessibilityHint(clickable ? (item.isOn ? "点击关掉" : "点击打开") : (item.lockReason ?? ""))
    }
}

/// 行首的圆形状态图标,照 Wi-Fi 菜单(macOS 27 实测,与它的已连接 / 未连接两行逐像素比):
/// - 直径 26pt;图形是 13pt 粗体的系统符号——Wi-Fi 的扇形在这个字号字重下尺寸与墨量都对得上
///   (曾用 12pt 中等,偏小偏细)。
/// - 开着:实心圆 + 白色图形,圆的颜色见 `onFill`。
/// - 关着:系统填充色 `secondarySystemFill` 的浅灰圆 + 主文字色图形(浅色模式下纯黑,与 Wi-Fi 一致;
///   曾用灰色图形,看上去像不可用)。
/// 开关时的动画**只作用在颜色与透明度上**,原地渐变,见 `animatingOnly`。
private struct StatusIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Self.offFill)
            Circle()
                .fill(Self.onFill)
                .animatingOnly(.easeInOut(duration: 0.2)) { $0.opacity(isOn ? 1 : 0) }
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .animatingOnly(.easeInOut(duration: 0.2)) { $0.foregroundStyle(isOn ? Color.white : Color.primary) }
        }
        .frame(width: 26, height: 26)
    }

    private static var offFill: Color {
        if #available(macOS 14.0, *) { return Color(nsColor: .secondarySystemFill) }
        return Color.primary.opacity(0.08)       // macOS 13 没有系统填充色
    }

    /// 系统强调色选「多色」(默认)时,Wi-Fi 菜单的圆是系统蓝 `systemBlue`——实测 (62, 136, 249),与它一致;
    /// 强调色 `controlAccentColor` 在「多色」下是另一种偏深的蓝 (55, 123, 249),曾用它,比 Wi-Fi 深。
    /// 「多色」的含义是各 app 用自己的颜色;用户选定某种强调色后,系统界面统一改用那种颜色,这里随之用强调色。
    /// 选了别的强调色时 Wi-Fi 菜单的样子没有实测(不去改他的系统设置),按这条含义推定。
    private static var onFill: Color {
        UserDefaults.standard.object(forKey: "AppleAccentColor") == nil
            ? Color(nsColor: .systemBlue)
            : Color(nsColor: .controlAccentColor)
    }
}

/// 鼠标经过时的整行底,照抄菜单栏 Wi-Fi 菜单(macOS 27 实测,他把 Wi-Fi 图标放出来让我对照):
/// 浅灰圆角块,离面板边缘 7pt、圆角约 11pt,图标与文字不变,出现与消失都没有过渡(录屏逐帧看过)。
/// 颜色是系统填充色 `secondarySystemFill`:真实背景上 Wi-Fi 菜单悬停时底色从 (251, 251, 255) 变 (231, 231, 235),
/// 纯白垫底上是 (254) 变 (234),两种背景下都与它相同(颜色只认截图,录屏帧有颜色转换,不能拿来比)。
/// 走过的弯:先是一层 6% 的灰(他:「不明显」),再是系统文字菜单的强调色蓝底(他:「太怪异」)。
private struct HoverBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Self.fill)
    }

    private static var fill: Color {
        if #available(macOS 14.0, *) { return Color(nsColor: .secondarySystemFill) }
        return Color.primary.opacity(0.08)       // macOS 13 没有系统填充色;主色随深浅模式变
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
