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

/// 面板顶部的一句话摘要。
public func panelSummary(_ items: [DisplayMenuItem]) -> String {
    guard !items.isEmpty else { return "没有检测到显示器" }
    return "\(items.count) 块屏 · \(items.filter(\.isOn).count) 块亮着"
}
