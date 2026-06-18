import Testing
import CoreGraphics
@testable import DisplaySwitchCore

@Test("有内建屏:唯一外接屏也可关")
func canDisableLastExternalWhenBuiltInExists() {
    let ext = makeInfo(id: 2)
    #expect(canDisable(ext, among: [ext], hasBuiltIn: true) == true)
}

@Test("无内建屏:剩两块时可关其一")
func canDisableOneOfTwoWithoutBuiltIn() {
    let a = makeInfo(id: 2, x: 0)
    let b = makeInfo(id: 3, x: 1920)
    #expect(canDisable(a, among: [a, b], hasBuiltIn: false) == true)
}

@Test("无内建屏:最后一块外接屏禁止关")
func cannotDisableLastExternalWithoutBuiltIn() {
    let a = makeInfo(id: 2)
    #expect(canDisable(a, among: [a], hasBuiltIn: false) == false)
}

@Test("内建屏本身不允许作为关闭目标")
func cannotDisableBuiltinTarget() {
    let builtin = makeInfo(id: 1, builtin: true)
    let ext = makeInfo(id: 2)
    #expect(canDisable(builtin, among: [builtin, ext], hasBuiltIn: true) == false)
}

@Test("已经非活跃的屏不可再关")
func cannotDisableInactiveTarget() {
    let inactive = makeInfo(id: 2, active: false)
    let other = makeInfo(id: 3)
    #expect(canDisable(inactive, among: [inactive, other], hasBuiltIn: true) == false)
}
