import Testing
import CoreGraphics
@testable import DisplaySwitchCore

func makeInfo(id: CGDirectDisplayID, builtin: Bool = false, main: Bool = false,
              active: Bool = true, x: CGFloat = 0, name: String = "Mi Monitor") -> DisplayInfo {
    DisplayInfo(id: id, uuid: "uuid-\(id)", name: name,
                bounds: CGRect(x: x, y: 0, width: 1920, height: 1080),
                isMain: main, isBuiltin: builtin, isActive: active)
}
