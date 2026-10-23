import Testing
import Foundation
@testable import DisplaySwitchCore

// 夹具一取自 Mac mini M4 的显示交换器(2026-10-23,`ioreg -l` 原样抄录形态):外接屏插在机身 HDMI 口,
// 由主协处理器 `dcp` 经 `disp0` 输出。所有节点都没写 domain,HDMI 的 `dptx-phy` 也没写 port——按内核的规矩都是 0。
/// 交换器 `display-crossbar0` 的句柄 `AAPL,phandle` = <b9000000>。
private let mini = 0xB9
private let miniRoutes = ["0:ufp0,0-dfp4,0"]
private let miniUFPs = [CrossbarUFP(crossbar: mini, domain: 0, endpoint: 0, role: "DCP"),
                        CrossbarUFP(crossbar: mini, domain: 0, endpoint: 1, role: "DCPEXT0"),
                        CrossbarUFP(crossbar: mini, domain: 0, endpoint: 2, role: "DCPEXT1")]
private let miniDFPs: [CrossbarDFP] = {
    var all: [CrossbarDFP] = []
    for (endpoint, number) in [(0, 1), (1, 2), (3, 4)] {          // atc0、atc1、atc3:1、2、4 号 USB-C 口,直连 + 2 条雷雳隧道
        all.append(CrossbarDFP(crossbar: mini, domain: 0, endpoint: endpoint, port: 0, portType: 2, portNumber: number, tunneled: false))
        for p in 1...2 { all.append(CrossbarDFP(crossbar: mini, domain: 0, endpoint: endpoint, port: p, portType: 2, portNumber: number, tunneled: true)) }
    }
    all.append(CrossbarDFP(crossbar: mini, domain: 0, endpoint: 4, port: 0, portType: 6, portNumber: 1, tunneled: false))   // dptx-phy:HDMI
    return all
}()

// 夹具二取自他的 MacBook(`AppleT6050DisplayCrossbar`,2026-10-23 原样抄录):两块同型号屏经拓展坞接在一个雷雳口上,
// 分别走它的第 1、2 条雷雳隧道;机身有 1~3 号雷雳口与一个 HDMI 口。
// 上游:`dcpext0`~`dcpext3` 各自声明 0~3 号口(都没写 domain);交换器名单写着 dispext0~7、scodec0,
// 但声明 5、6 号口的是两个只走 AUX 的 `dptx0-aux-ufp`、`dptx1-aux-ufp`(没有 role,读取时就不收),
// 没有节点声明 4、7、8 号口——名单在这台机器上同样只是标签,只是前 4 项碰巧与协处理器对齐。
/// 交换器 `display-crossbar0` 的句柄 `AAPL,phandle` = <1a010000>。
private let xbar = 0x11A
private let routes = ["0:ufp0,0-dfp0,1", "0:ufp1,0-dfp0,2"]                 // 拓展坞插在 1 号口时
private let routesOnPort2 = ["0:ufp0,0-dfp1,1", "0:ufp1,0-dfp1,2"]          // 换插 2 号口后
private let ufps = (0..<4).map { CrossbarUFP(crossbar: xbar, domain: 0, endpoint: $0, role: "DCPEXT\($0)") }
private let dfps: [CrossbarDFP] = {
    var all: [CrossbarDFP] = []
    for (endpoint, number) in [(0, 1), (1, 2), (2, 3)] {          // atc0~atc2:1~3 号 USB-C 口,直连 + 4 条雷雳隧道
        all.append(CrossbarDFP(crossbar: xbar, domain: 0, endpoint: endpoint, port: 0, portType: 2, portNumber: number, tunneled: false))
        for p in 1...4 { all.append(CrossbarDFP(crossbar: xbar, domain: 0, endpoint: endpoint, port: p, portType: 2, portNumber: number, tunneled: true)) }
    }
    all.append(CrossbarDFP(crossbar: xbar, domain: 0, endpoint: 3, port: 0, portType: 6, portNumber: 1, tunneled: false))   // atc3:HDMI
    return all
}()

@Test("接口写法:雷雳 N、USB-C N;只有一个 HDMI 口时不写编号")
func macPortLabels() {
    #expect(macPortLabel(.thunderbolt(1)) == "雷雳 1")
    #expect(macPortLabel(.usbC(2)) == "USB-C 2")
    #expect(macPortLabel(.hdmi(1)) == "HDMI")
    #expect(macPortLabel(.hdmi(2)) == "HDMI 2")
}

@Test("解析交换器路由:上游序号、下游端点与通路;格式不对就不认")
func crossbarRouteParsing() {
    #expect(parseCrossbarRoute("0:ufp1,0-dfp0,2") == CrossbarRoute(domain: 0, ufp: 1, dfpEndpoint: 0, dfpPort: 2))
    #expect(parseCrossbarRoute("1:ufp3,0-dfp2,0") == CrossbarRoute(domain: 1, ufp: 3, dfpEndpoint: 2, dfpPort: 0))
    #expect(parseCrossbarRoute("ufp1-dfp0") == nil)
    #expect(parseCrossbarRoute("") == nil)
}

@Test("Mac mini:机身 HDMI 上的屏由主协处理器经 disp0 输出,对到 HDMI")
func macPortsOnMacMiniHDMI() {
    #expect(macPortsByController(routes: miniRoutes, crossbar: mini, ufps: miniUFPs, dfps: miniDFPs) == ["disp0": .hdmi(1)])
}

@Test("上游口按协处理器自己声明的编号对,不按交换器名单的序号:Mac mini 的 1 号口上是 dcpext0")
func upstreamByDeclaredEndpoint() {
    let routes = ["0:ufp1,0-dfp0,1", "0:ufp2,0-dfp3,0"]
    #expect(macPortsByController(routes: routes, crossbar: mini, ufps: miniUFPs, dfps: miniDFPs)
            == ["dispext0": .thunderbolt(1), "dispext1": .thunderbolt(4)])
}

@Test("上游只按域和口对:同一协处理器换一条输出管线,仍是同一个控制器")
func upstreamIgnoresPipe() {
    #expect(macPortsByController(routes: ["0:ufp0,1-dfp4,0"], crossbar: mini, ufps: miniUFPs, dfps: miniDFPs) == ["disp0": .hdmi(1)])
}

@Test("MacBook:拓展坞插在哪个雷雳口,两块屏就都写那个口")
func macPortsFromCrossbar() {
    #expect(macPortsByController(routes: routes, crossbar: xbar, ufps: ufps, dfps: dfps)
            == ["dispext0": .thunderbolt(1), "dispext1": .thunderbolt(1)])
    #expect(macPortsByController(routes: routesOnPort2, crossbar: xbar, ufps: ufps, dfps: dfps)
            == ["dispext0": .thunderbolt(2), "dispext1": .thunderbolt(2)])
}

@Test("MacBook:名单上的 dispext5 并不是 5 号口上的东西,没有协处理器声明的上游口就不认")
func upstreamNotFromNameList() {
    #expect(macPortsByController(routes: ["0:ufp5,0-dfp1,0"], crossbar: xbar, ufps: ufps, dfps: dfps).isEmpty)
}

@Test("接在不同口的屏分别对上:直连雷雳口也算雷雳口,HDMI 单独认")
func macPortsOnDifferentPorts() {
    let mixed = ["0:ufp0,0-dfp2,0", "0:ufp1,0-dfp3,0"]                // dispext0 直连 3 号口,dispext1 走 HDMI
    #expect(macPortsByController(routes: mixed, crossbar: xbar, ufps: ufps, dfps: dfps)
            == ["dispext0": .thunderbolt(3), "dispext1": .hdmi(1)])
}

@Test("没有雷雳隧道通路的 USB-C 口写 USB-C;对不上的路由跳过,不猜")
func macPortFallbacks() {
    let plain = [CrossbarDFP(crossbar: xbar, domain: 0, endpoint: 5, port: 0, portType: 2, portNumber: 4, tunneled: false)]
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp5,0"], crossbar: xbar, ufps: ufps, dfps: plain) == ["dispext0": .usbC(4)])
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp9,1", "0:ufp42,0-dfp0,1", "1:ufp0,0-dfp0,1", "乱码"],
                                 crossbar: xbar, ufps: ufps, dfps: dfps).isEmpty)
    let unknownType = [CrossbarDFP(crossbar: xbar, domain: 0, endpoint: 0, port: 0, portType: 9, portNumber: 1, tunneled: false)]
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp0,0"], crossbar: xbar, ufps: ufps, dfps: unknownType).isEmpty)
    let unknownRole = [CrossbarUFP(crossbar: xbar, domain: 0, endpoint: 0, role: "SCODEC0")]
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp0,1"], crossbar: xbar, ufps: unknownRole, dfps: dfps).isEmpty)
}

@Test("有两个交换器时各管各的上下游:编号重叠也不串到另一个交换器的口上")
func macPortsPerCrossbar() {
    let other = 0x2B0
    let otherUFPs = [CrossbarUFP(crossbar: other, domain: 0, endpoint: 0, role: "DCPEXT8")]
    let otherDFPs = [CrossbarDFP(crossbar: other, domain: 0, endpoint: 0, port: 0, portType: 2, portNumber: 5, tunneled: false),
                     CrossbarDFP(crossbar: other, domain: 0, endpoint: 0, port: 1, portType: 2, portNumber: 5, tunneled: true)]
    let allUFPs = ufps + otherUFPs, allDFPs = dfps + otherDFPs
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp0,1"], crossbar: xbar, ufps: allUFPs, dfps: allDFPs) == ["dispext0": .thunderbolt(1)])
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp0,1"], crossbar: other, ufps: allUFPs, dfps: allDFPs) == ["dispext8": .thunderbolt(5)])
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp3,0"], crossbar: other, ufps: allUFPs, dfps: allDFPs).isEmpty)
}

@Test("协处理器的 role 对到它输出的显示控制器:DCP → disp0,DCPEXTn → dispextn,别的不认")
func controllerFromRole() {
    #expect(displayController(forRole: "DCP") == "disp0")
    #expect(displayController(forRole: "DCPEXT0") == "dispext0")
    #expect(displayController(forRole: "DCPEXT7") == "dispext7")
    #expect(displayController(forRole: "DCPEXT") == nil)
    #expect(displayController(forRole: "DCPEXT1a") == nil)
    #expect(displayController(forRole: "SCODEC0") == nil)
    #expect(displayController(forRole: "") == nil)
}

@Test("从设备树位置里取显示控制器名:外接屏也可能在 disp0 上(Mac mini 的机身 HDMI)")
func controllerFromLocation() {
    #expect(displayController(inLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleT605xIO/dispext0@B0000000/IOMobileFramebufferShim") == "dispext0")
    #expect(displayController(inLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleH16GFamilyIO/disp0@8000000/IOMobileFramebufferShim") == "disp0")
    #expect(displayController(inLocation: "IOService:/AppleARMPE/arm-io@10F00000/display@0/IOMobileFramebufferShim") == nil)
    #expect(displayController(inLocation: "") == nil)
}

@Test("真机自洽:查到接口的只有亮着的外接屏")
func realMacPortsOnlyForActiveExternals() {
    let svc = CGDisplayService()
    let externals = Set(svc.activeDisplays().filter { !$0.isBuiltin }.map(\.id))
    #expect(Set(svc.macPorts().keys).isSubset(of: externals))
}
