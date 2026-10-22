import Foundation

/// 面板上给人看的文字。全部是纯函数,界面层只负责摆放,不再拼字。

/// 一个外接屏接口路径属于哪种接法。认不出的返回 nil——宁可不写,也不写错。
/// 判据是传输节点路径(实测形态):机身 HDMI 为 `Port-HDMI@1/DisplayPort`,
/// 走雷雳 / USB4 隧道的(含雷雳拓展坞)为 `Port-USB-C@1/CIO/DisplayPort@0`,
/// USB-C 直出(DP 替代模式,不经隧道)为 `Port-USB-C@N/DisplayPort`。
/// 注意「雷雳」只说明走的是雷雳隧道:直连的雷雳显示器也会是这个形态,所以不写成「拓展坞」。
func linkKind(ofPort port: String) -> String? {
    if port.hasPrefix("Port-HDMI") { return "HDMI" }
    if port.contains("/CIO/") { return "雷雳" }
    if port.hasPrefix("Port-USB-C") { return "USB-C" }
    return nil
}

/// 所有外接屏共用的接法;混用(如一块 HDMI、一块雷雳)或有认不出的,返回 nil。
/// 为什么不逐块标:系统没有给出「哪块屏走哪个接口」的可靠对应——同型号两块屏的 EDID 头部序列号
/// 都是 19(实测),按它对应会张冠李戴。接法唯一时,每块外接屏必然都是这种接法,写上才不会错。
func sharedLinkLabel(_ ports: [String]?) -> String? {
    guard let ports, !ports.isEmpty else { return nil }
    let kinds = ports.map(linkKind(ofPort:))
    guard let first = kinds.first, let kind = first, kinds.allSatisfy({ $0 == kind }) else { return nil }
    return kind
}

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
