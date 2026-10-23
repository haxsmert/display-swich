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
// Apple Silicon 上,每块外接屏由一个显示控制器(设备树里的 `dispext0`、`dispext1`……)输出,
// 再经显示交换器(`display-crossbar0`)路由到某个机身端口的某条通路(`atc0` 的直连口,或它的几条雷雳隧道)。
// 交换器驱动的 `current-state` 记着当前路由,形如 `0:ufp0,0-dfp0,1`:上游第 0 个(`ufp-endpoints` 里的
// `dispext0`)接到下游第 0 个端点的 1 号口。下游每条通路的节点上写着 `port-type`(2 = USB-C,6 = HDMI)、
// `port-number`(机身端口号)与 `transport-tunneled`(是不是雷雳隧道)。2026-10-23 在他的机器上逐项核对过:
// 两块同型号屏分别是 `0:ufp0,0-dfp0,1` 与 `0:ufp1,0-dfp0,2`,即 1 号口的两条雷雳隧道,
// 与端口传输节点(`Port-USB-C@1/CIO/DisplayPort@0/1`)、系统信息(Receptacle 1 上接着拓展坞)一致。
// 这条链按显示控制器对应,**同型号、EDID 完全相同的两块屏也不会对错**——EDID 对不上是哪块,曾是不写接法的原因。
// 都是系统未写成文档的数据,解析不了就不写,不猜。

/// 交换器里的一条路由。
struct CrossbarRoute: Equatable {
    let domain: Int
    /// 上游序号:交换器 `ufp-endpoints` 里的第几个(如 `dispext0`)。
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

/// 交换器下游的一条通路(设备树里 `atc0-dpphy`、`atc0-dpin0` 这类节点上的属性)。
struct CrossbarDFP: Equatable {
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

/// 把交换器的路由翻成「显示控制器名 → 机身端口」,如 `["dispext0": .thunderbolt(1)]`。
/// 某条路由对不上上游名字或下游通路,就跳过那一条。
func macPortsByController(routes: [String], ufpEndpoints: [String], dfps: [CrossbarDFP]) -> [String: MacPort] {
    var result: [String: MacPort] = [:]
    for text in routes {
        guard let r = parseCrossbarRoute(text), ufpEndpoints.indices.contains(r.ufp),
              let dfp = dfps.first(where: { $0.domain == r.domain && $0.endpoint == r.dfpEndpoint && $0.port == r.dfpPort }),
              let port = macPort(of: dfp, among: dfps) else { continue }
        result[ufpEndpoints[r.ufp]] = port
    }
    return result
}

/// 从 CoreDisplay 给的设备树位置里取出显示控制器名,如 `…/dispext0@B0000000/…` → `dispext0`。
func displayController(inLocation location: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"(dispext\d+)"#),
          let m = regex.firstMatch(in: location, range: NSRange(location.startIndex..., in: location)) else { return nil }
    return (location as NSString).substring(with: m.range(at: 1))
}
