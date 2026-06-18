import Testing
import CoreGraphics
@testable import DisplaySwitchCore

func makeInfo(id: CGDirectDisplayID, builtin: Bool = false, main: Bool = false,
              active: Bool = true, x: CGFloat = 0, name: String = "Mi Monitor") -> DisplayInfo {
    DisplayInfo(id: id, uuid: "uuid-\(id)", name: name,
                bounds: CGRect(x: x, y: 0, width: 1920, height: 1080),
                isMain: main, isBuiltin: builtin, isActive: active)
}

@Test("externalDisplays 过滤掉内建屏")
func externalDisplaysExcludesBuiltin() {
    let builtin = makeInfo(id: 1, builtin: true)
    let ext = makeInfo(id: 2, builtin: false)
    #expect(externalDisplays([builtin, ext]) == [ext])
}

@Test("externalDisplays 全外接时原样返回")
func externalDisplaysKeepsAllExternal() {
    let a = makeInfo(id: 2)
    let b = makeInfo(id: 3, x: 1920)
    #expect(externalDisplays([a, b]) == [a, b])
}
