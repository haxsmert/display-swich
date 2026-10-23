import Testing
import CoreGraphics
@testable import DisplaySwitchCore

// MARK: 单块屏标签 displayLabel

@Test("主屏:名字 +(主)")
func labelMain() {
    #expect(displayLabel(for: makeInfo(id: 1, main: true, name: "External Display")) == "External Display（主）")
}
@Test("非主屏:只显示名字")
func labelNonMain() {
    #expect(displayLabel(for: makeInfo(id: 2, name: "External Display")) == "External Display")
}
@Test("内建屏同样规则(名字 +(主))")
func labelBuiltinMain() {
    #expect(displayLabel(for: makeInfo(id: 1, builtin: true, main: true, name: "内建显示器")) == "内建显示器（主）")
}
@Test("名字为空回退为显示器")
func labelEmpty() {
    #expect(displayLabel(for: makeInfo(id: 1, name: "")) == "显示器")
}
@Test("去掉系统给同名屏加的 (N):写显示器自己的名字")
func labelStripsSystemSuffix() {
    #expect(displayLabel(for: makeInfo(id: 1, name: "External Display (2)")) == "External Display")
    #expect(displayLabel(for: makeInfo(id: 1, main: true, name: "External Display (1)")) == "External Display（主）")
}

// MARK: 整组写法 displayNames

@Test("两块都亮着:照抄系统此刻的号(与系统设置一致),再带尾号;按带最大号 +(主)预留宽度")
func namesFollowSystemNumbers() {
    // 系统的号与序列号顺序无关:这里系统把序列号大的那台叫 (1)。
    let names = displayNames(for: [makeInfo(id: 2, main: true, name: "External Display (1)", serial: "SN-0007"),
                                   makeInfo(id: 4, name: "External Display (2)", serial: "SN-0002")], knownNumbers: [:])
    #expect(names[2] == DisplayNames(label: "External Display (1)（主）", sizingLabel: "External Display (2)（主）", serialTail: "…0007"))
    #expect(names[4] == DisplayNames(label: "External Display (2)", sizingLabel: "External Display (2)（主）", serialTail: "…0002"))
}
@Test("关掉一块:系统去掉了剩下那块的号,面板不跟着去——关掉的用关掉前的号,亮着的用它上次的号")
func namesKeepNumbersWhenSiblingClosed() {
    let closed = makeInfo(id: 2, active: false, name: "External Display (1)", serial: "SN-0007")   // 快照:关掉前叫 (1)
    let lit = makeInfo(id: 4, name: "External Display", serial: "SN-0002")                          // 系统此刻不给号
    let names = displayNames(for: [closed, lit], knownNumbers: ["serial:SN-0002": 2])
    #expect(names[2]?.label == "External Display (1)")
    #expect(names[4]?.label == "External Display (2)")
}
@Test("没记过号、或号撞了:补最小的空号,不让两块同号")
func namesFillGaps() {
    let closed = makeInfo(id: 2, active: false, name: "External Display (1)", serial: "SN-0007")
    let lit = makeInfo(id: 4, name: "External Display", serial: "SN-0002")
    #expect(displayNames(for: [closed, lit], knownNumbers: [:])[4]?.label == "External Display (2)")
    #expect(displayNames(for: [closed, lit], knownNumbers: ["serial:SN-0002": 1])[4]?.label == "External Display (2)")
}
@Test("系统重新编号(换口、重开后对调)时跟着系统走,不留旧号")
func namesFollowSystemRenumbering() {
    let names = displayNames(for: [makeInfo(id: 2, name: "External Display (2)", serial: "SN-0007"),
                                   makeInfo(id: 4, name: "External Display (1)", serial: "SN-0002")],
                             knownNumbers: ["serial:SN-0007": 1, "serial:SN-0002": 2])
    #expect(names[2]?.label == "External Display (2)")
    #expect(names[4]?.label == "External Display (1)")
}
@Test("同型号读不到序列号:号照样有,只是没有尾号")
func namesWithoutSerials() {
    let names = displayNames(for: [makeInfo(id: 2, name: "External Display (1)"), makeInfo(id: 4, name: "External Display (2)")],
                             knownNumbers: [:])
    #expect(names[2] == DisplayNames(label: "External Display (1)", sizingLabel: "External Display (2)（主）", serialTail: nil))
    #expect(names[4]?.label == "External Display (2)" && names[4]?.serialTail == nil)
}
@Test("名字独一无二:不编号、不写尾号;关掉前带着的旧号也去掉(同系统设置)")
func namesForUniqueDisplays() {
    let names = displayNames(for: [makeInfo(id: 1, builtin: true, main: true, name: "Built-in Retina Display", serial: "PANEL1"),
                                   makeInfo(id: 2, active: false, name: "External Display (2)", serial: "SN-0002")],
                             knownNumbers: [:])
    #expect(names[1] == DisplayNames(label: "Built-in Retina Display（主）", sizingLabel: "Built-in Retina Display（主）", serialTail: nil))
    #expect(names[2] == DisplayNames(label: "External Display", sizingLabel: "External Display（主）", serialTail: nil))
}

// MARK: 序列号尾号 serialTails

@Test("同型号两块:各写序列号末 4 位;只差最后一位也分得开")
func tailsForSameModel() {
    let tails = serialTails(for: [makeInfo(id: 2, name: "External Display (1)", serial: "AB0000000001X7"),
                                  makeInfo(id: 4, name: "External Display (2)", serial: "AB0000000001X2")])
    #expect(tails == [2: "…01X7", 4: "…01X2"])
}
@Test("末 4 位撞了就加长到能分开为止")
func tailsGrowUntilDistinct() {
    let tails = serialTails(for: [makeInfo(id: 1, serial: "A99-0000"), makeInfo(id: 2, serial: "B99-0000")])
    #expect(tails == [1: "A99-0000", 2: "B99-0000"])                 // 加长到整串时不加省略号
    let mid = serialTails(for: [makeInfo(id: 1, serial: "X1-0000"), makeInfo(id: 2, serial: "X2-0000")])
    #expect(mid == [1: "…1-0000", 2: "…2-0000"])
}
@Test("名字独一无二、或读不到序列号的屏不写尾号")
func tailsOnlyWhenNeeded() {
    #expect(serialTails(for: [makeInfo(id: 1, builtin: true, name: "Built-in Retina Display", serial: "PANEL123456"),
                              makeInfo(id: 2, name: "External Display", serial: "EXT0000001")]).isEmpty)
    #expect(serialTails(for: [makeInfo(id: 1), makeInfo(id: 2)]).isEmpty)
    // 同名三块里只有两块读得到序列号:只给这两块写
    #expect(serialTails(for: [makeInfo(id: 1, serial: "SN-0001"), makeInfo(id: 2, serial: "SN-0002"), makeInfo(id: 3)])
            == [1: "…0001", 2: "…0002"])
    #expect(serialTails(for: [makeInfo(id: 1, serial: "SN-0001"), makeInfo(id: 2)]) == [1: "…0001"])   // 一块有、一块没有
}
@Test("尾号按基名分组:系统名带不带 (N) 都算同一型号")
func tailsGroupByBaseName() {
    let tails = serialTails(for: [makeInfo(id: 1, name: "External Display", serial: "SN-0001"),
                                  makeInfo(id: 2, active: false, name: "External Display (2)", serial: "SN-0002")])
    #expect(tails == [1: "…0001", 2: "…0002"])
}
