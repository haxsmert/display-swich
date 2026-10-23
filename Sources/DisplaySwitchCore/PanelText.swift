import Foundation

/// 面板上给人看的文字。全部是纯函数,界面层只负责摆放,不再拼字。

// 接法只写电脑这一端、带上口的编号:「外接 · 雷雳 1」(他的要求,2026-10-23),写法见 `macPortLabel`。
// 曾不写接法(2026-10-22):当时只写一个「雷雳」,读起来像在说显示器那头接的线(他一块接 DP 线、一块接 USB-C 线),
// 而且同型号两块屏 EDID 一模一样,按 EDID 对不上哪块屏走哪个口。现在按显示交换器的路由对应(见 `MacPort.swift`),
// 写明是 Mac 上的几号口;显示器那头接的什么口不写(DDC/CI 读得到,编号由厂商自定,他判断意义不大)。
// 接口路径仍原样写进诊断(见 `DisplayController` 的诊断快照),排查时用。

/// 分辨率与刷新率,如 `3840×2160 · 60Hz`。刷新率为 0(可变刷新率)时不写 Hz。
func modeText(_ mode: DisplayMode) -> String {
    let size = "\(mode.pixelWidth)×\(mode.pixelHeight)"
    let hz = Int(mode.refreshRate.rounded())
    return hz > 0 ? "\(size) · \(hz)Hz" : size
}

/// 锁住原因,取他本人的说法(2026-10-22)。目前是顶部提示区唯一会出现的一句,界面按它预留宽度。
public let lockReasonText = "至少要保留一块屏幕点亮"

/// 面板顶部提示区要写的话;没什么要说的时候为 nil,提示区就空着。
/// 目前只有一种情况要说:只剩最后一块亮着、被锁住,写清为什么不能关。
/// 放在顶部而不是被锁住那一行里,行高就不会变,面板不会跳(他的设计)。
/// 曾在平时报数「3 块屏 · 2 块亮着」,他指出没用:每行行首的图标已经写明开没开(2026-10-22)。
public func panelHint(_ items: [DisplayMenuItem]) -> String? {
    items.lazy.compactMap(\.lockReason).first
}
