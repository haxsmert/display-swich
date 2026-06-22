import Testing
import CoreGraphics
@testable import DisplaySwitchCore

@Test("剩两块时可关其一")
func canDisableOneOfTwo() {
    let a = makeInfo(id: 1); let b = makeInfo(id: 2)
    #expect(canDisable(a, among: [a, b], builtInFallback: false) == true)
}
@Test("无内建兜底时:最后一块活跃屏禁止关(绝不全黑)")
func cannotDisableLastActiveNoFallback() {
    let a = makeInfo(id: 1)
    #expect(canDisable(a, among: [a], builtInFallback: false) == false)
}
@Test("有可开盖恢复的内建兜底时:允许关最后一块(外接)活跃屏")
func canDisableLastExternalWithBuiltInFallback() {
    let ext = makeInfo(id: 2)
    #expect(canDisable(ext, among: [ext], builtInFallback: true) == true)
}
@Test("即便有内建兜底:也禁止把内建屏自己关成全黑(关掉它兜底即失效,防死锁)")
func cannotDisableBuiltinIntoBlackEvenWithFallback() {
    let builtin = makeInfo(id: 1, builtin: true)
    #expect(canDisable(builtin, among: [builtin], builtInFallback: true) == false)
}
@Test("内建屏可关(只要不是最后一块活跃屏),与兜底无关")
func canDisableBuiltinIfNotLast() {
    let builtin = makeInfo(id: 1, builtin: true); let ext = makeInfo(id: 2)
    #expect(canDisable(builtin, among: [builtin, ext], builtInFallback: false) == true)
    #expect(canDisable(builtin, among: [builtin, ext], builtInFallback: true) == true)
}
@Test("非活跃屏不可再关")
func cannotDisableInactive() {
    let inactive = makeInfo(id: 1, active: false); let other = makeInfo(id: 2)
    #expect(canDisable(inactive, among: [inactive, other], builtInFallback: false) == false)
}
@Test("只剩一块活跃(另一块已断开)、无兜底时禁止关")
func cannotDisableWhenOnlyOneActiveNoFallback() {
    let active = makeInfo(id: 1); let off = makeInfo(id: 2, active: false)
    #expect(canDisable(active, among: [active, off], builtInFallback: false) == false)
}
