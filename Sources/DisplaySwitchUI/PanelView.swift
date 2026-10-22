import SwiftUI
import DisplaySwitchCore

/// 菜单栏弹出面板。
///
/// 视觉取法 macOS 27 自己的菜单栏面板(控制中心):系统玻璃底、大圆角;行没有底色与描边,
/// 开关状态由行首的圆形图标表达——开着是强调色实心圆、白色图形,关着是浅灰圆(同控制中心的
/// Wi-Fi、蓝牙);鼠标经过时只出现一层很淡的圆角高亮,与系统菜单一致。
/// 不用鼠标悬停提示(他认为低级):需要说明的话直接写在顶部的提示区。
///
/// **布局在交互中保持不动**:每行高度固定;锁住原因写在顶部摘要的位置(他的设计),
/// 不在行里加字——曾因多出一行让面板长高、整体跳动,打乱他接下来要点的位置(2026-10-22)。
public struct PanelView: View {
    @ObservedObject var model: PanelModel

    public init(model: PanelModel) { self.model = model }

    private var hasLockedRow: Bool { model.items.contains { $0.lockReason != nil } }

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
                    DisplayRow(item: item, supported: model.supported) { model.toggle(item.id) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
            Divider().padding(.horizontal, 14)
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("显示器开关")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            // 提示区:平时报数,有屏被锁住时写为什么不能关。新旧两句在原地交叉淡化,不挪动别的东西。
            // 锁形图标嵌在文字里、随文字排版:单独摆一个图标会把这一行撑高 1pt,面板跟着跳(截图实测)。
            ZStack(alignment: .trailing) {
                Text(hasLockedRow ? "\(Image(systemName: "lock.fill")) \(model.summary)" : "\(model.summary)")
                    .monospacedDigit()
                    .imageScale(.small)
                    .id(model.summary)
                    .transition(.opacity)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .animation(.easeInOut(duration: 0.2), value: model.summary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
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
                    Text(rescueStatusText)
                }
            }
            .buttonStyle(QuietTextButtonStyle())

            HStack {
                Button(model.versionText, action: model.openRepository)
                    .buttonStyle(QuietTextButtonStyle())
                Spacer()
                Button("退出", action: model.quit)
                    .buttonStyle(QuietTextButtonStyle())
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 12)
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
/// 状态由行首圆形图标表达,关着时文字变淡并写「已关闭」——不只靠颜色;被锁住时整行不可点,
/// 行尾一把小锁,原因写在顶部提示区。
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
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(item.isOn ? .secondary : .tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(locked ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: locked)
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .disabled(!clickable)
        .accessibilityLabel("\(item.label),\(item.isOn ? "已打开" : "已关闭")")
        .accessibilityHint(clickable ? (item.isOn ? "点击关掉" : "点击打开") : (item.lockReason ?? ""))
    }
}

/// 行首的圆形状态图标(取法控制中心):开着为强调色实心圆 + 白色图形,关着为浅灰圆 + 灰色图形。
/// 动画只作用在颜色上,原地渐变——曾把动画挂在整行上,连带行内位置、尺寸的变化一起动,
/// 他看到的是「蓝色从别处浮过来」(2026-10-22)。
private struct StatusIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))
            Circle()
                .fill(Color(nsColor: .controlAccentColor))
                .opacity(isOn ? 1 : 0)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .frame(width: 28, height: 28)
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

/// 行的点击反馈,与系统菜单一致:平时无底色;鼠标经过时一层很淡的圆角高亮,按下时深一点。
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let level = !isEnabled ? 0 : configuration.isPressed ? 0.10 : hovering ? 0.06 : 0
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(level))
                        .animation(.easeOut(duration: 0.12), value: level)
                )
                .onHover { hovering = $0 }
        }
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
