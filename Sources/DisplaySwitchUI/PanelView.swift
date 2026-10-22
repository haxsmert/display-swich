import SwiftUI
import DisplaySwitchCore

/// 菜单栏弹出面板。
///
/// 视觉取法 macOS 自己的菜单栏面板(控制中心、系统设置的列表),而不是网页卡片:
/// 不描边、不用重色块,靠圆形状态图标、字重与留白分层;配色只用系统语义色,浅色、实底、不透明。
/// **布局在交互中保持不动**:每行高度固定,锁住原因替换第二行而不是新增一行——
/// 曾因多出一行让面板长高、整体跳动,打乱他接下来要点的位置(2026-10-22)。
public struct PanelView: View {
    @ObservedObject var model: PanelModel

    public init(model: PanelModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.supported { unsupportedNotice }
            VStack(spacing: 4) {
                if model.items.isEmpty {
                    Text("没有检测到显示器")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                ForEach(model.items, id: \.id) { item in
                    DisplayRow(item: item, supported: model.supported) { model.toggle(item.id) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: 320)
        // 底色与外框由 PanelChrome 画(圆角 + 指向图标的箭头)。
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("显示器开关")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(model.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .modifier(NumericTransition())
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var unsupportedNotice: some View {
        Label("此设备不支持开关显示器（需 Apple Silicon 与受支持的 macOS），只能查看",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 救援是否就绪要看得见:全黑时界面全无,平时就该知道这道兜底在不在。点它打开救援日志。
            Button(action: model.openRescueLog) {
                HStack(spacing: 5) {
                    Image(systemName: model.supported ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(model.supported ? Color.green : Color.orange)
                    Text(rescueStatusText).foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开救援日志")

            HStack {
                Button(model.versionText, action: model.openRepository)
                    .buttonStyle(QuietTextButtonStyle())
                    .help("在 GitHub 上查看本项目")
                Spacer()
                Button("退出", action: model.quit)
                    .buttonStyle(QuietTextButtonStyle())
                    .keyboardShortcut("q", modifiers: .command)
                    .help("退出(关掉的屏会全部恢复)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 11)
    }

    private var rescueStatusText: String {
        guard model.supported else { return "全黑救援不可用：此设备不支持开关显示器" }
        guard let last = model.lastRescue else { return "全黑救援已就绪" }
        return "全黑救援已就绪 · 上次救援 \(Self.relative(last))"
    }

    /// 今天的只写时刻,更早的带上日期。
    private static func relative(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M 月 d 日 HH:mm"
        return f.string(from: date)
    }
}

/// 一块屏一行,**整行就是开关**:点一下就切换,没有任何开关控件(他的要求)。
/// 开着:行铺一层很淡的强调色,行首圆形图标为强调色实心、白色图形;
/// 关着:行无底色,图标灰、文字变淡并写「已关闭」——状态不只靠颜色区分。
/// 被锁住时整行不可点,第二行换成原因(行高不变,面板不跳)。
private struct DisplayRow: View {
    let item: DisplayMenuItem
    let supported: Bool
    let toggle: () -> Void

    private var locked: Bool { item.isOn && !item.canToggleOff }
    private var clickable: Bool { supported && !locked }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                StatusIcon(symbol: item.isBuiltin ? "laptopcomputer" : "display", isOn: item.isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(item.isOn ? .primary : .secondary)
                        .lineLimit(1)
                    // 两种第二行叠放、只切换透明度:换内容时不改变行高,也就不会推动下面的行。
                    ZStack(alignment: .leading) {
                        Text(item.detail)
                            .opacity(locked ? 0 : 1)
                        if let reason = item.lockReason {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill").font(.system(size: 8, weight: .semibold))
                                Text(reason)
                            }
                            .opacity(locked ? 1 : 0)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(item.isOn ? .secondary : .tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(isOn: item.isOn))
        .disabled(!clickable)
        .animation(.easeInOut(duration: 0.2), value: item.isOn)
        .animation(.easeInOut(duration: 0.2), value: locked)
        .help(locked ? "\(item.detail)\n\(item.lockReason ?? "")" : (item.isOn ? "点击关掉这块屏" : "点击打开这块屏"))
        .accessibilityLabel("\(item.label),\(item.isOn ? "已打开" : "已关闭")")
        .accessibilityHint(clickable ? (item.isOn ? "点击关掉" : "点击打开") : (item.lockReason ?? ""))
    }
}

/// 行首的圆形状态图标:开着为强调色实心圆 + 白色图形,关着为浅灰圆 + 灰色图形(取法控制中心)。
private struct StatusIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Color(nsColor: .controlAccentColor) : Color(nsColor: .quaternaryLabelColor).opacity(0.55))
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color(nsColor: .secondaryLabelColor))
        }
        .frame(width: 28, height: 28)
    }
}

/// 行的底色即开关状态:开着铺一层很淡的强调色,关着无底色(融进面板)。
/// 悬停时加深一点、按下时再深一点,让人看出整行可以点;锁住的行没有悬停反馈。
private struct RowButtonStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isOn: isOn)
    }

    private struct RowBody: View {
        let configuration: ButtonStyle.Configuration
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            // 直接取系统强调色:SwiftUI 的 accentColor 在按钮被禁用时会自动变灰,
            // 锁住的行(亮着但不能关)就会看不出「开着」(实测)。
            let accent = Color(nsColor: .controlAccentColor)
            let feedback = !isEnabled ? 0 : configuration.isPressed ? 0.08 : hovering ? 0.045 : 0
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(isOn ? 0.10 : 0))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(feedback))
                        )
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// 底部文字按钮:不描边、不铺底,平时次要色,悬停时变成主色——安静但可发现。
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

/// 摘要里的数字变化时逐位滚动(macOS 14+),更早的系统直接替换。
private struct NumericTransition: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.numericText())
        } else {
            content
        }
    }
}
