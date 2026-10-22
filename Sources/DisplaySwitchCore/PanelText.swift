import Foundation

/// 面板上给人看的文字。全部是纯函数,界面层只负责摆放,不再拼字。

// 不写接法(雷雳 / HDMI / USB-C)。系统能确定的只有 Mac 这一端:信号从哪个口出、走不走雷雳隧道;
// 他关心的是显示器那头接的什么线,而那一头系统不知道——实测(2026-10-22):两块屏一块接 DP 线、
// 一块接 USB-C 线,系统为每块屏记的都只是「上游 DP、下游 DP」;同型号两块屏的 EDID 也一模一样,
// 连 Mac 这一端都对不上是哪一块。写 Mac 这一端(曾写「雷雳」),读起来就是在说显示器那头,等于写错。
// 接口路径仍原样写进诊断(见 `DisplayController` 的诊断快照),排查时用。

/// 分辨率与刷新率,如 `3840×2160 · 60Hz`。刷新率为 0(可变刷新率)时不写 Hz。
func modeText(_ mode: DisplayMode) -> String {
    let size = "\(mode.pixelWidth)×\(mode.pixelHeight)"
    let hz = Int(mode.refreshRate.rounded())
    return hz > 0 ? "\(size) · \(hz)Hz" : size
}

/// 面板顶部提示区要写的话;没什么要说的时候为 nil,提示区就空着。
/// 目前只有一种情况要说:只剩最后一块亮着、被锁住,写清为什么不能关。
/// 放在顶部而不是被锁住那一行里,行高就不会变,面板不会跳(他的设计)。
/// 曾在平时报数「3 块屏 · 2 块亮着」,他指出没用:每行行首的图标已经写明开没开(2026-10-22)。
public func panelHint(_ items: [DisplayMenuItem]) -> String? {
    items.lazy.compactMap(\.lockReason).first
}
