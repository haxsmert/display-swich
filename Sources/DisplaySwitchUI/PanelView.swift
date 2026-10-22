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
                    DisplayRow(item: item, supported: model.supported) { on in model.setOn(on, for: item.id) }
                }
            }
            .padding(12)
            Divider()
            footer
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
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

/// 一块屏一张卡片:图标、名称、说明行、开关;开关被锁住时直接写出原因。
private struct DisplayRow: View {
    let item: DisplayMenuItem
    let supported: Bool
    let setOn: (Bool) -> Void

    private var locked: Bool { item.isOn && !item.canToggleOff }

    var body: some View {
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
            Toggle(item.label, isOn: Binding(get: { item.isOn }, set: setOn))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!supported || locked)
                .help(locked ? (item.lockReason ?? "") : (item.isOn ? "关掉这块屏" : "打开这块屏"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
