import Testing
import CoreGraphics
@testable import DisplaySwitchCore

// MARK: 单块屏标签 displayLabel

@Test("主屏:基名 +(主)")
func labelMain() {
    #expect(displayLabel(for: makeInfo(id: 1, main: true, name: "Mi Monitor")) == "Mi Monitor（主）")
}
@Test("非主屏:只显示基名")
func labelNonMain() {
    #expect(displayLabel(for: makeInfo(id: 2, name: "Mi Monitor")) == "Mi Monitor")
}
@Test("内建屏同样规则(基名 +(主))")
func labelBuiltinMain() {
    #expect(displayLabel(for: makeInfo(id: 1, builtin: true, main: true, name: "内建显示器")) == "内建显示器（主）")
}
@Test("名字为空回退为显示器")
func labelEmpty() {
    #expect(displayLabel(for: makeInfo(id: 1, name: "")) == "显示器")
}
@Test("剥掉系统动态消歧后缀 (N)")
func labelStripsSystemSuffix() {
    #expect(displayLabel(for: makeInfo(id: 1, name: "Mi Monitor (2)")) == "Mi Monitor")
}

// MARK: 整组稳定编号 displayLabels(绑定 UUID 稳定标识,与位置无关)

@Test("同名两块:按稳定标识编号 (1)(2)")
func labelsNumbersDuplicates() {
    let a = makeInfo(id: 1, name: "Mi Monitor")        // uuid-1
    let b = makeInfo(id: 2, name: "Mi Monitor")        // uuid-2
    let labels = displayLabels(for: [b, a])            // 故意乱序传入
    #expect(labels[1] == "Mi Monitor (1)")
    #expect(labels[2] == "Mi Monitor (2)")
}
@Test("编号绑定 UUID 而非位置:左右对调后编号不漂移")
func labelsStableByIdentityNotPosition() {
    let a = makeInfo(id: 1, x: 1920, name: "Mi Monitor")   // uuid-1,现处右侧
    let b = makeInfo(id: 2, x: 0,    name: "Mi Monitor")   // uuid-2,现处左侧
    let labels = displayLabels(for: [a, b])
    #expect(labels[1] == "Mi Monitor (1)")             // 仍跟随 uuid-1,无视它在右
    #expect(labels[2] == "Mi Monitor (2)")
}
@Test("关掉同名其一后,剩下那块仍保号、不被顶替(整组含已关闭快照)")
func labelsKeepNumberWhenSiblingDisabled() {
    // 关掉一块:它仍在组里(系统名带原后缀);另一块活跃的系统已摘号成 "Mi Monitor"
    let disabledOne = makeInfo(id: 1, active: false, name: "Mi Monitor (1)")
    let activeOther = makeInfo(id: 2, name: "Mi Monitor")
    let labels = displayLabels(for: [disabledOne, activeOther])
    #expect(labels[1] == "Mi Monitor (1)")
    #expect(labels[2] == "Mi Monitor (2)")             // 关键:另一块没丢号也没顶替
}
@Test("不同名各自唯一:都不加号")
func labelsNoNumberForDistinctNames() {
    let builtin = makeInfo(id: 1, builtin: true, main: true, name: "内建显示器")
    let mi      = makeInfo(id: 2, name: "Mi Monitor")
    let labels = displayLabels(for: [builtin, mi])
    #expect(labels[1] == "内建显示器（主）")
    #expect(labels[2] == "Mi Monitor")
}
@Test("同名多块时主屏:号 +(主)")
func labelsMainWithinDuplicates() {
    let a = makeInfo(id: 1, main: true, name: "Mi Monitor")
    let b = makeInfo(id: 2, name: "Mi Monitor")
    let labels = displayLabels(for: [a, b])
    #expect(labels[1] == "Mi Monitor (1)（主）")
    #expect(labels[2] == "Mi Monitor (2)")
}
