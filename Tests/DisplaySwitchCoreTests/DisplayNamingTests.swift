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

@Test("同型号两块都有序列号:都写显示器自己的名字,靠尾号分清;按名字 +(主)预留宽度")
func namesForSameModelWithSerials() {
    let names = displayNames(for: [makeInfo(id: 2, main: true, name: "External Display (1)", serial: "SN-0007"),
                                   makeInfo(id: 4, active: false, name: "External Display (2)", serial: "SN-0002")])
    #expect(names[2] == DisplayNames(label: "External Display（主）", sizingLabel: "External Display（主）", serialTail: "…0007"))
    #expect(names[4] == DisplayNames(label: "External Display", sizingLabel: "External Display（主）", serialTail: "…0002"))
}
@Test("同型号却读不到序列号:没有尾号可看,只好照抄系统的叫法;系统随时可能加号去号,按带最大号预留")
func namesFallBackToSystemWithoutSerials() {
    let names = displayNames(for: [makeInfo(id: 2, name: "External Display (1)"), makeInfo(id: 4, name: "External Display")])
    #expect(names[2] == DisplayNames(label: "External Display (1)", sizingLabel: "External Display (2)（主）", serialTail: nil))
    #expect(names[4] == DisplayNames(label: "External Display", sizingLabel: "External Display (2)（主）", serialTail: nil))
}
@Test("同型号只有一块读得到序列号:它写名字 + 尾号,另一块照抄系统的叫法")
func namesMixedSerials() {
    let names = displayNames(for: [makeInfo(id: 2, name: "External Display (1)", serial: "SN-0007"),
                                   makeInfo(id: 4, name: "External Display (2)")])
    #expect(names[2]?.label == "External Display" && names[2]?.serialTail == "…0007")
    #expect(names[4]?.label == "External Display (2)" && names[4]?.serialTail == nil)
}
@Test("名字独一无二:写名字,不写尾号;关掉前带着的旧号也去掉")
func namesForUniqueDisplays() {
    let names = displayNames(for: [makeInfo(id: 1, builtin: true, main: true, name: "Built-in Retina Display", serial: "PANEL1"),
                                   makeInfo(id: 2, active: false, name: "External Display (2)", serial: "SN-0002")])
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
