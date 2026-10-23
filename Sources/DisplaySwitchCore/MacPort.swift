import Foundation

/// 外接屏接在 Mac 的哪个口——只说电脑这一端(他的要求,2026-10-23:「外接 · 雷雳 1」这样)。
/// 显示器那一端接的什么口不写:DDC/CI 其实读得到当前输入源,但编号由厂商自定,他判断意义不大。
public enum MacPort: Equatable, Sendable {
    /// 带雷雳的 USB-C 口(机身上标着闪电的那种),编号同系统信息里的 Receptacle。
    case thunderbolt(Int)
    /// 不带雷雳的 USB-C 口。
    case usbC(Int)
    case hdmi(Int)
}

/// 说明行里的写法:「雷雳 1」「USB-C 2」「HDMI」。机身只有一个 HDMI 口时不写编号。
public func macPortLabel(_ port: MacPort) -> String {
    switch port {
    case .thunderbolt(let n): "雷雳 \(n)"
    case .usbC(let n): "USB-C \(n)"
    case .hdmi(let n): n == 1 ? "HDMI" : "HDMI \(n)"
    }
}

// MARK: - 从系统的显示交换器读出「哪块屏走哪个口」
//
// Apple Silicon 上,每块外接屏由一个显示控制器(设备树里的 `disp0`、`dispext0`……)输出,它背后的显示协处理器
// (`dcp`、`dcpext0`……)接在显示交换器(`display-crossbar0`)的一个上游口上;交换器再把上游口路由到某个机身端口的
// 某条通路(`atc0` 的直连口、它的几条雷雳隧道,或 HDMI 的 `dptx-phy`)。交换器驱动的 `current-state` 记着当前路由,
// 形如 `0:ufp0,0-dfp4,0`:第 0 域里,上游 0 号口接到下游 4 号端点的 0 号通路。
// 两侧每个口都在自己的设备树节点上声明地址:`dp-switch-parent`(属于哪个交换器)加 `dp-switch-ufp-*` / `dp-switch-dfp-*`
// 的 domain、endpoint、port,**没写的按 0**——这是内核的规矩(`IODPTXPort` 的 `getAddressPropertyWithProvider`:
// 「not specified; defaulting to 0」),不是我们补的:Mac mini M4 上所有节点都没写 domain,HDMI 的 `dptx-phy` 也没写 port。
// 上游口的节点是显示协处理器,写着 `role`(`DCP`、`DCPEXT0`……);下游通路的节点写着 `port-type`(2 = USB-C,6 = HDMI)、
// `port-number`(机身端口号)与 `transport-tunneled`(是不是雷雳隧道)。
//
// 两处曾经的误读,2026-10-23 在 Mac mini M4(机身 HDMI 接一块屏)上查清:
// ① 上游口编号**不是**交换器 `ufp-endpoints` 名单里的序号。那份名单只是交换器给槽位贴的标签(驱动日志也照它打
//   `dispext%u`):Mac mini M4 上名单第 0 个叫 `dispext0`,真正接在 0 号口的却是主协处理器 `dcp`,`dcpext0` 在 1 号口。
//   按名单对,HDMI 上的屏就对不上。他的 MacBook 上 `dcpext0`~`dcpext3` 恰好占 0~3 号口,与名单前 4 项对齐,
//   所以按名单也读得对;但名单第 5、6 项写着 dispext5、dispext6,实际占 5、6 号口的是两个只走 AUX 的口(没有 role)。
// ② 外接屏不一定由 `dispextN` 输出:没有内建屏的 Mac mini,机身 HDMI 由主协处理器 `dcp` 经 `disp0` 输出。
// 协处理器与显示控制器按 `role` 对:`DCP` → `disp0`,`DCPEXTn` → `dispextn`。各协处理器固件端点的名字印证了这一点
// (`dcpext0` 下的端点都叫 `dispext0:…`,`dcp` 下有 `disp0:…`);连接管理器(`AppleDisplayConnectionManager`)的
// `ConnectionMapping` 也写着 `role=DCP、Address=0.4.0`,与这条链读出的结果一致。
// 这条链按显示控制器对应,**同型号、EDID 完全相同的两块屏也不会对错**——EDID 对不上是哪块,曾是不写接法的原因。
// 都是系统未写成文档的数据,解析不了就不写,不猜。

/// 交换器里的一条路由。
struct CrossbarRoute: Equatable {
    let domain: Int
    /// 上游口编号(对应协处理器节点的 `dp-switch-ufp-endpoint`)。
    let ufp: Int
    /// 下游端点序号(对应下游节点的 `dp-switch-dfp-endpoint`)。
    let dfpEndpoint: Int
    /// 下游端点里的第几条通路(对应 `dp-switch-dfp-port`;0 是直连,1 起是雷雳隧道)。
    let dfpPort: Int
}

/// 解析一条路由,如 `0:ufp0,0-dfp0,1`;格式对不上返回 nil。
func parseCrossbarRoute(_ text: String) -> CrossbarRoute? {
    let pattern = #"^(\d+):ufp(\d+),\d+-dfp(\d+),(\d+)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), m.numberOfRanges == 5 else { return nil }
    let n = (1...4).map { Int((text as NSString).substring(with: m.range(at: $0))) }
    guard let domain = n[0], let ufp = n[1], let endpoint = n[2], let port = n[3] else { return nil }
    return CrossbarRoute(domain: domain, ufp: ufp, dfpEndpoint: endpoint, dfpPort: port)
}

/// 交换器上游的一个口:一个显示协处理器(设备树里 `dcp`、`dcpext0` 这类节点上的属性)。
struct CrossbarUFP: Equatable {
    /// 属于哪个交换器:节点的 `dp-switch-parent`,同 `CrossbarDFP.crossbar`。
    let crossbar: Int
    let domain: Int
    let endpoint: Int
    /// 协处理器的 `role`,如 `DCP`、`DCPEXT0`。
    let role: String
}

/// 交换器下游的一条通路(设备树里 `atc0-dpphy`、`atc0-dpin0`、`dptx-phy` 这类节点上的属性)。
struct CrossbarDFP: Equatable {
    /// 属于哪个交换器:节点的 `dp-switch-parent`,等于那个交换器节点的 `AAPL,phandle`(实测 `1a010000`、`b9000000`)。
    /// 有不止一个交换器的机器(如 Ultra)上,各交换器的上下游编号会重叠,必须先按它分开。
    let crossbar: Int
    let domain: Int
    let endpoint: Int
    let port: Int
    /// 2 = USB-C,6 = HDMI(实测)。
    let portType: Int
    let portNumber: Int
    let tunneled: Bool
}

/// 一条通路属于机身哪个口。USB-C 口只要有雷雳隧道通路(同一端点下有 `tunneled` 的),就是雷雳口——
/// 即便这块屏此刻是直连(不走隧道),口本身还是机身上那个雷雳口。
func macPort(of dfp: CrossbarDFP, among all: [CrossbarDFP]) -> MacPort? {
    switch dfp.portType {
    case 2:
        let hasTunnel = all.contains { $0.domain == dfp.domain && $0.endpoint == dfp.endpoint && $0.tunneled }
        return hasTunnel ? .thunderbolt(dfp.portNumber) : .usbC(dfp.portNumber)
    case 6:
        return .hdmi(dfp.portNumber)
    default:
        return nil
    }
}

/// 把一个交换器的路由翻成「显示控制器名 → 机身端口」,如 `["dispext0": .thunderbolt(1)]`、`["disp0": .hdmi(1)]`。
/// 只在这个交换器自己的上下游口里找;某条路由对不上上游协处理器或下游通路,就跳过那一条。
/// 上游只按域和口对,不看口内的 port:那是协处理器的第几条输出管线,换一条也还是同一个控制器。
func macPortsByController(routes: [String], crossbar: Int, ufps allUFPs: [CrossbarUFP], dfps allDFPs: [CrossbarDFP]) -> [String: MacPort] {
    let ufps = allUFPs.filter { $0.crossbar == crossbar }
    let dfps = allDFPs.filter { $0.crossbar == crossbar }
    var result: [String: MacPort] = [:]
    for text in routes {
        guard let r = parseCrossbarRoute(text),
              let ufp = ufps.first(where: { $0.domain == r.domain && $0.endpoint == r.ufp }),
              let controller = displayController(forRole: ufp.role),
              let dfp = dfps.first(where: { $0.domain == r.domain && $0.endpoint == r.dfpEndpoint && $0.port == r.dfpPort }),
              let port = macPort(of: dfp, among: dfps) else { continue }
        result[controller] = port
    }
    return result
}

/// 协处理器的 `role` → 它输出的显示控制器名:`DCP` → `disp0`,`DCPEXTn` → `dispextn`;别的不认。
func displayController(forRole role: String) -> String? {
    if role == "DCP" { return "disp0" }
    let n = role.dropFirst("DCPEXT".count)
    guard role.hasPrefix("DCPEXT"), !n.isEmpty, n.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return "dispext\(n)"
}

/// 从 CoreDisplay 给的设备树位置里取出显示控制器名,如 `…/dispext0@B0000000/…` → `dispext0`、
/// `…/disp0@8000000/…` → `disp0`(Mac mini 的机身 HDMI)。
func displayController(inLocation location: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"/(disp(?:ext)?\d+)@"#),
          let m = regex.firstMatch(in: location, range: NSRange(location.startIndex..., in: location)) else { return nil }
    return (location as NSString).substring(with: m.range(at: 1))
}
