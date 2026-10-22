import SwiftUI
import DisplaySwitchCore

/// 菜单栏弹出面板。版式借鉴 MonitorBar(头部摘要 → 一屏一张卡片 → 底部状态栏),
/// 配色跟随系统外观、只用系统语义色:浅色、实底、高对比,不做透明与发光。
public struct PanelView: View {
    @ObservedObject var model: PanelModel

    public init(model: PanelModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 8) {
                if !model.supported { unsupportedNotice }
                if model.items.isEmpty {
                    Text("没有检测到显示器").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(model.items, id: \.id) { item in
                    DisplayRow(item: item, supported: model.supported) { model.toggle(item.id) }
                }
            }
            .padding(12)
            Divider()
            footer
        }
        .frame(width: 340)
        // 底色与外框由 PanelChrome 画(圆角 + 指向图标的箭头)。
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "display.2")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("显示器开关").font(.headline)
                Text(model.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var unsupportedNotice: some View {
        Label("此设备不支持开关显示器（需 Apple Silicon 与受支持的 macOS），只能查看",
              systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 救援是否就绪要看得见:全黑时界面全无,平时就该知道这道兜底在不在。点它打开救援日志。
            Button(action: model.openRescueLog) {
                HStack(spacing: 6) {
                    Image(systemName: model.supported ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(model.supported ? Color.green : Color.orange)
                    Text(rescueStatusText).foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开救援日志")

            HStack {
                Button(model.versionText, action: model.openRepository)
                    .buttonStyle(.link).font(.caption)
                    .help("在 GitHub 上查看本项目")
                Spacer()
                Button("退出", action: model.quit)
                    .keyboardShortcut("q", modifiers: .command)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
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

/// 一块屏一张卡片:**整行就是开关**,点哪里都行;右侧的开关图形只显示真实状态,不单独接收点击。
/// 被锁住时整行不可点,并直接写出原因。
private struct DisplayRow: View {
    let item: DisplayMenuItem
    let supported: Bool
    let toggle: () -> Void

    private var locked: Bool { item.isOn && !item.canToggleOff }
    private var clickable: Bool { supported && !locked }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isOn ? .primary : .tertiary)
                    .frame(width: 28, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(item.isOn ? .primary : .secondary)
                        .lineLimit(1)
                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let reason = item.lockReason {
                        Label(reason, systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                SwitchIndicator(isOn: item.isOn, dimmed: !clickable)
                    .padding(.top, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!clickable)
        .help(locked ? (item.lockReason ?? "") : (item.isOn ? "点击关掉这块屏" : "点击打开这块屏"))
        .accessibilityLabel("\(item.label),\(item.isOn ? "已打开" : "已关闭")")
        .accessibilityHint(clickable ? (item.isOn ? "点击关掉" : "点击打开") : (item.lockReason ?? ""))
    }
}

/// 开关的样子,只用来显示状态(整行才是点击区域)。外形与系统开关一致:开为强调色,关为灰。
private struct SwitchIndicator: View {
    let isOn: Bool
    let dimmed: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.accentColor : Color(nsColor: .tertiaryLabelColor).opacity(0.35))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 0.8, y: 0.5)
                .padding(2)
        }
        .frame(width: 38, height: 22)
        .opacity(dimmed ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// 卡片底色;鼠标悬停时加深一点,按下时再深一点——让人看出整行可以点。
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(!isEnabled ? 0 : configuration.isPressed ? 0.09 : hovering ? 0.045 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .onHover { hovering = $0 }
        }
    }
}
