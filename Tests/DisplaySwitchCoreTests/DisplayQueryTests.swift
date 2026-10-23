import Testing
import CoreGraphics
@testable import DisplaySwitchCore

func makeInfo(id: CGDirectDisplayID, builtin: Bool = false, main: Bool = false,
              active: Bool = true, x: CGFloat = 0, name: String = "External Display",
              uuid: String? = nil, serial: String = "") -> DisplayInfo {
    DisplayInfo(id: id, uuid: uuid ?? "uuid-\(id)", name: name,
                bounds: CGRect(x: x, y: 0, width: 1920, height: 1080),
                isMain: main, isBuiltin: builtin, isActive: active, serial: serial)
}
