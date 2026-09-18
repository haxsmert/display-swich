import Testing
@testable import DisplaySwitchCore

@Test("只认「合 → 开」这一个跳变")
func detectsOnlyTheOpeningEdge() {
    var d = LidEdgeDetector(initiallyClosed: true)
    #expect(d.didOpen(nowClosed: false) == true)     // 合 → 开
}

@Test("合盖期间的重复事件一律不上报:这正是浪费的来源")
func repeatedEventsWhileClosedReportNothing() {
    var d = LidEdgeDetector(initiallyClosed: false)
    #expect(d.didOpen(nowClosed: true) == false)     // 开 → 合:合盖本身不需要动作
    // 真机上 IOPMrootDomain 在合盖期间会持续派发(实测一分半来了二十多条)。
    // 结论恒定不变,一条都不该惊动上层。
    for _ in 0..<20 { #expect(d.didOpen(nowClosed: true) == false) }
}

@Test("盖子一直开着:任何电源事件都不上报")
func stayingOpenReportsNothing() {
    var d = LidEdgeDetector(initiallyClosed: false)
    for _ in 0..<10 { #expect(d.didOpen(nowClosed: false) == false) }
}

@Test("反复合上再打开:每次打开各上报一次,不多不少")
func eachOpeningReportsExactlyOnce() {
    var d = LidEdgeDetector(initiallyClosed: false)
    var opens = 0
    for closed in [true, true, false, false, true, false, true, true, false] {
        if d.didOpen(nowClosed: closed) { opens += 1 }
    }
    #expect(opens == 3)                               // 序列里恰好三次「合 → 开」
}

@Test("注册时就是开着的:第一条事件不该被当成刚打开")
func initiallyOpenDoesNotFireOnFirstEvent() {
    var d = LidEdgeDetector(initiallyClosed: false)
    #expect(d.didOpen(nowClosed: false) == false)     // 否则 app 一启动就会误救援
}
