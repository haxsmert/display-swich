import Testing
import CoreGraphics
@testable import DisplaySwitchCore

@Test("主屏:系统名 +(主)")
func labelMain() {
    #expect(displayLabel(for: makeInfo(id: 1, main: true, name: "Mi Monitor (2)")) == "Mi Monitor (2)（主）")
}
@Test("非主屏:只显示系统名")
func labelNonMain() {
    #expect(displayLabel(for: makeInfo(id: 2, name: "Mi Monitor (1)")) == "Mi Monitor (1)")
}
@Test("内建屏同样规则(系统名 +(主))")
func labelBuiltinMain() {
    #expect(displayLabel(for: makeInfo(id: 1, builtin: true, main: true, name: "内建显示器")) == "内建显示器（主）")
}
@Test("名字为空回退为显示器")
func labelEmpty() {
    #expect(displayLabel(for: makeInfo(id: 1, name: "")) == "显示器")
}
