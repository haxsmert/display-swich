import Testing
import Foundation
@testable import DisplaySwitchCore

// 夹具取自他机器上的显示交换器(2026-10-23,`ioreg -l` 原样抄录形态):
// 两块同型号屏经拓展坞接在 1 号雷雳口,分别走它的第 1、2 条雷雳隧道;机身另有 2、3 号雷雳口与一个 HDMI 口。
private let routes = ["0:ufp0,0-dfp0,1", "0:ufp1,0-dfp0,2"]
private let ufps = ["dispext0", "dispext1", "dispext2", "dispext3", "dispext4", "dispext5", "dispext6", "dispext7", "scodec0"]
private let dfps: [CrossbarDFP] = {
    var all: [CrossbarDFP] = []
    for (endpoint, number) in [(0, 1), (1, 2), (2, 3)] {          // atc0~atc2:1~3 号 USB-C 口,直连 + 4 条雷雳隧道
        all.append(CrossbarDFP(domain: 0, endpoint: endpoint, port: 0, portType: 2, portNumber: number, tunneled: false))
        for p in 1...4 { all.append(CrossbarDFP(domain: 0, endpoint: endpoint, port: p, portType: 2, portNumber: number, tunneled: true)) }
    }
    all.append(CrossbarDFP(domain: 0, endpoint: 3, port: 0, portType: 6, portNumber: 1, tunneled: false))   // atc3:HDMI
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

@Test("按交换器路由对应:同型号两块屏也各对各的控制器,都是 1 号雷雳口")
func macPortsFromCrossbar() {
    #expect(macPortsByController(routes: routes, ufpEndpoints: ufps, dfps: dfps)
            == ["dispext0": .thunderbolt(1), "dispext1": .thunderbolt(1)])
}

@Test("接在不同口的屏分别对上:直连雷雳口也算雷雳口,HDMI 单独认")
func macPortsOnDifferentPorts() {
    let mixed = ["0:ufp0,0-dfp2,0", "0:ufp1,0-dfp3,0"]                // dispext0 直连 3 号口,dispext1 走 HDMI
    #expect(macPortsByController(routes: mixed, ufpEndpoints: ufps, dfps: dfps)
            == ["dispext0": .thunderbolt(3), "dispext1": .hdmi(1)])
}

@Test("没有雷雳隧道通路的 USB-C 口写 USB-C;对不上的路由跳过,不猜")
func macPortFallbacks() {
    let plain = [CrossbarDFP(domain: 0, endpoint: 5, port: 0, portType: 2, portNumber: 4, tunneled: false)]
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp5,0"], ufpEndpoints: ufps, dfps: plain) == ["dispext0": .usbC(4)])
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp9,1", "0:ufp42,0-dfp0,1", "乱码"], ufpEndpoints: ufps, dfps: dfps).isEmpty)
    let unknownType = [CrossbarDFP(domain: 0, endpoint: 0, port: 0, portType: 9, portNumber: 1, tunneled: false)]
    #expect(macPortsByController(routes: ["0:ufp0,0-dfp0,0"], ufpEndpoints: ufps, dfps: unknownType).isEmpty)
}

@Test("从设备树位置里取显示控制器名")
func controllerFromLocation() {
    #expect(displayController(inLocation: "IOService:/AppleARMPE/arm-io@10F00000/AppleT605xIO/dispext0@B0000000/IOMobileFramebufferShim") == "dispext0")
    #expect(displayController(inLocation: "IOService:/AppleARMPE/arm-io/disp0@A0000000") == nil)
}

@Test("真机自洽:查到接口的只有亮着的外接屏")
func realMacPortsOnlyForActiveExternals() {
    let svc = CGDisplayService()
    let externals = Set(svc.activeDisplays().filter { !$0.isBuiltin }.map(\.id))
    #expect(Set(svc.macPorts().keys).isSubset(of: externals))
}
