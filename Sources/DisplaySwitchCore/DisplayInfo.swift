import CoreGraphics

/// 一块显示器的不可变快照。
public struct DisplayInfo: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let uuid: String
    public let name: String
    public let bounds: CGRect
    public let isMain: Bool
    public let isBuiltin: Bool
    public let isActive: Bool

    public init(id: CGDirectDisplayID, uuid: String, name: String, bounds: CGRect,
                isMain: Bool, isBuiltin: Bool, isActive: Bool) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.bounds = bounds
        self.isMain = isMain
        self.isBuiltin = isBuiltin
        self.isActive = isActive
    }
}

