import CoreGraphics

/// 一块屏当前的显示模式(像素尺寸与刷新率)。`refreshRate` 为 0 表示可变刷新率,系统不报固定值。
public struct DisplayMode: Equatable, Sendable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double

    public init(pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }
}

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

