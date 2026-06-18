import Testing
import CoreGraphics
@testable import DisplaySwitchCore

@Test("两块屏按 x 坐标标左右,主屏加标记")
func labelsLeftRightWithMain() {
    let left = makeInfo(id: 2, main: true, x: 0)
    let right = makeInfo(id: 3, x: 1920)
    let externals = [left, right]
    #expect(displayLabel(for: left, among: externals) == "Mi Monitor（左·主屏）")
    #expect(displayLabel(for: right, among: externals) == "Mi Monitor（右）")
}

@Test("单块外接屏无位置标签")
func labelSingleExternalNoPosition() {
    let only = makeInfo(id: 2, x: 0)
    #expect(displayLabel(for: only, among: [only]) == "Mi Monitor")
}

@Test("单块外接屏是主屏时只标主屏")
func labelSingleMainOnly() {
    let only = makeInfo(id: 2, main: true, x: 0)
    #expect(displayLabel(for: only, among: [only]) == "Mi Monitor（主屏）")
}

@Test("三块及以上用序号")
func labelThreeUsesIndex() {
    let a = makeInfo(id: 2, x: 0)
    let b = makeInfo(id: 3, x: 1920)
    let c = makeInfo(id: 4, x: 3840)
    let externals = [a, b, c]
    #expect(displayLabel(for: b, among: externals) == "Mi Monitor（#2）")
}

@Test("名字为空时回退为显示器")
func labelEmptyNameFallback() {
    let only = makeInfo(id: 2, x: 0, name: "")
    #expect(displayLabel(for: only, among: [only]) == "显示器")
}
