import Testing
import CoreGraphics
@testable import DisplaySwitchCore

@Test("剩两块时可关其一")
func canDisableOneOfTwo() {
    let a = makeInfo(id: 1); let b = makeInfo(id: 2)
    #expect(canDisable(a, among: [a, b]) == true)
}
@Test("最后一块活跃屏禁止关(绝不全黑)")
func cannotDisableLastActive() {
    let a = makeInfo(id: 1)
    #expect(canDisable(a, among: [a]) == false)
}
@Test("内建屏也可关(只要不是最后一块活跃屏)")
func canDisableBuiltinIfNotLast() {
    let builtin = makeInfo(id: 1, builtin: true); let ext = makeInfo(id: 2)
    #expect(canDisable(builtin, among: [builtin, ext]) == true)
}
@Test("非活跃屏不可再关")
func cannotDisableInactive() {
    let inactive = makeInfo(id: 1, active: false); let other = makeInfo(id: 2)
    #expect(canDisable(inactive, among: [inactive, other]) == false)
}
@Test("只剩一块活跃(另一块已断开)时禁止关")
func cannotDisableWhenOnlyOneActive() {
    let active = makeInfo(id: 1); let off = makeInfo(id: 2, active: false)
    #expect(canDisable(active, among: [active, off]) == false)
}
