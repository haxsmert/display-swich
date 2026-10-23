import Testing
import CoreGraphics
@testable import DisplaySwitchCore

// MARK: 单块屏标签 displayLabel

@Test("主屏:基名 +(主)")
func labelMain() {
    #expect(displayLabel(for: makeInfo(id: 1, main: true, name: "External Display")) == "External Display（主）")
}
@Test("非主屏:只显示基名")
func labelNonMain() {
    #expect(displayLabel(for: makeInfo(id: 2, name: "External Display")) == "External Display")
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
    #expect(displayLabel(for: makeInfo(id: 1, name: "External Display (2)")) == "External Display")
}

// MARK: 整组稳定编号 displayLabels(绑定 UUID 稳定标识,与位置无关)

@Test("同名两块:按稳定标识编号 (1)(2)")
func labelsNumbersDuplicates() {
    let a = makeInfo(id: 1, name: "External Display")        // uuid-1
    let b = makeInfo(id: 2, name: "External Display")        // uuid-2
    let labels = displayLabels(for: [b, a])            // 故意乱序传入
    #expect(labels[1] == "External Display (1)")
    #expect(labels[2] == "External Display (2)")
}
@Test("编号绑定 UUID 而非位置:左右对调后编号不漂移")
func labelsStableByIdentityNotPosition() {
    let a = makeInfo(id: 1, x: 1920, name: "External Display")   // uuid-1,现处右侧
    let b = makeInfo(id: 2, x: 0,    name: "External Display")   // uuid-2,现处左侧
    let labels = displayLabels(for: [a, b])
    #expect(labels[1] == "External Display (1)")             // 仍跟随 uuid-1,无视它在右
    #expect(labels[2] == "External Display (2)")
}
@Test("有序列号文本时按它编号,不按 UUID:两者顺序相反时以序列号为准")
func labelsBySerialOverUUID() {
    let a = makeInfo(id: 1, uuid: "uuid-a", serial: "SN-7")
    let b = makeInfo(id: 2, uuid: "uuid-b", serial: "SN-2")
    let labels = displayLabels(for: [a, b])
    #expect(labels[2] == "External Display (1)")
    #expect(labels[1] == "External Display (2)")
}
@Test("换接口后系统给的 UUID 与屏幕编号都换了,同一台屏的号不变(跟序列号走)")
func labelsSurviveReconnectWithNewUUIDs() {
    // 换口前:SN-7 那台拿着 uuid-a、id 4;换口后它变成 uuid-z、id 2,另一台反过来。
    let before = displayLabels(for: [makeInfo(id: 4, uuid: "uuid-a", serial: "SN-7"),
                                     makeInfo(id: 2, uuid: "uuid-z", serial: "SN-2")])
    let after = displayLabels(for: [makeInfo(id: 2, uuid: "uuid-z", serial: "SN-7"),
                                    makeInfo(id: 4, uuid: "uuid-a", serial: "SN-2")])
    #expect(before[4] == "External Display (2)" && after[2] == "External Display (2)")   // SN-7 始终是 (2)
    #expect(before[2] == "External Display (1)" && after[4] == "External Display (1)")   // SN-2 始终是 (1)
}
@Test("没有序列号文本的屏仍按 UUID 编号;与有序列号的同名屏放在一起时也有确定顺序")
func labelsFallBackToUUIDWithoutSerial() {
    let labels = displayLabels(for: [makeInfo(id: 1, uuid: "uuid-b"), makeInfo(id: 2, uuid: "uuid-a")])
    #expect(labels[2] == "External Display (1)")
    #expect(labels[1] == "External Display (2)")
    let mixed = displayLabels(for: [makeInfo(id: 3, uuid: "uuid-a"), makeInfo(id: 4, uuid: "uuid-z", serial: "SN-9")])
    #expect(mixed[4] == "External Display (1)")
    #expect(mixed[3] == "External Display (2)")
}
@Test("关掉同名其一后,剩下那块仍保号、不被顶替(整组含已关闭快照)")
func labelsKeepNumberWhenSiblingDisabled() {
    // 关掉一块:它仍在组里(系统名带原后缀);另一块活跃的系统已摘号成 "External Display"
    let disabledOne = makeInfo(id: 1, active: false, name: "External Display (1)")
    let activeOther = makeInfo(id: 2, name: "External Display")
    let labels = displayLabels(for: [disabledOne, activeOther])
    #expect(labels[1] == "External Display (1)")
    #expect(labels[2] == "External Display (2)")             // 关键:另一块没丢号也没顶替
}
@Test("不同名各自唯一:都不加号")
func labelsNoNumberForDistinctNames() {
    let builtin = makeInfo(id: 1, builtin: true, main: true, name: "内建显示器")
    let external = makeInfo(id: 2, name: "External Display")
    let labels = displayLabels(for: [builtin, external])
    #expect(labels[1] == "内建显示器（主）")
    #expect(labels[2] == "External Display")
}
@Test("同名多块时主屏:号 +(主)")
func labelsMainWithinDuplicates() {
    let a = makeInfo(id: 1, main: true, name: "External Display")
    let b = makeInfo(id: 2, name: "External Display")
    let labels = displayLabels(for: [a, b])
    #expect(labels[1] == "External Display (1)（主）")
    #expect(labels[2] == "External Display (2)")
}
