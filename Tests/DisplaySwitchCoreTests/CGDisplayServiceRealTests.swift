import Testing
import CoreGraphics
@testable import DisplaySwitchCore

/// 跑在真实系统上的自洽性断言(不依赖具体接了几块屏,任何机器上都成立)。
/// 作用:守住 IOKit 那条物理连接查询——它是本 app 判断「屏还在不在」的唯一真相,
/// 一旦它低报,被软件关掉、线还插着的屏就会从菜单里消失,用户再也点不开。

@Test("真机自洽:物理外接屏数不少于活跃外接屏数(活跃的必然物理连着)")
func physicalCountCoversActiveExternals() {
    let svc = CGDisplayService()
    let activeExternals = svc.activeDisplays().filter { !$0.isBuiltin }.count
    // 注:测试进程连不上 WindowServer 时 activeDisplays 会是空,断言退化为 >= 0 仍成立;
    // 在能取到活跃屏的环境里则是一条真检查。
    #expect((svc.liveExternalCount() ?? 0) >= activeExternals)
}

@Test("真机自洽:活跃屏 id 不重复")
func activeDisplayIDsAreUnique() {
    let ids = CGDisplayService().activeDisplays().map { $0.id }
    #expect(Set(ids).count == ids.count)
}
