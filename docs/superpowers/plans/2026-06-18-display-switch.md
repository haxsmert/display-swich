# 显示器开关小工具 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一个 macOS 菜单栏小工具,点开列出外接显示器,点击即可「虚拟断开/恢复」其中一块(让系统以为被拔掉,窗口自动迁移)。

**Architecture:** Swift Package,分 `DisplaySwitchCore`(纯逻辑 + 系统服务封装,可单测)与 `DisplaySwitchApp`(AppKit 菜单栏 UI)两个 target。纯逻辑(筛选/左右命名/机型保护)用 swift-testing 做 TDD;系统副作用(显示器枚举、私有符号开关、内建屏检测)藏在 `SystemDisplayService` 协议后,用 Mock 测 `DisplayController` 行为,真实硬件调用做手动 smoke 验证。

**Tech Stack:** Swift 6(tools 6.0)、SwiftPM、AppKit、CoreGraphics(含私有符号 `CGSConfigureDisplayEnabled`)、IOKit.ps(内建屏/电池检测)、swift-testing。零第三方依赖。

## Global Constraints

- **平台**:Apple Silicon + macOS 13+(开发机 M5 Pro / macOS 26.5.1)。不支持 Intel。
- **零第三方依赖**,只用系统框架。
- **私有符号** `CGSConfigureDisplayEnabled` 一律通过 `dlsym(RTLD_DEFAULT, ...)`(`RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)`)解析后 `unsafeBitCast` 调用,**不硬链接**。
- **绝不使用** `CGConfigureOption.permanently`(断开后可能无法用代码恢复的死坑)。配置选项首选 `.forAppOnly`,fallback `.forSession`。
- **机型感知保护**:有内建屏→外接屏可全关;无内建屏→至少保留一块活跃外接屏;「是否有内建屏」检测不确定时**保守按无内建屏处理**。
- **UI 文案用中文**;**commit message 用中文、开头带 emoji**。
- 测试框架:**swift-testing**(`import Testing` / `@Test` / `#expect`)。
- 运行测试统一用 `swift test`;预期失败一般表现为编译错误或断言失败。
- **Swift 6 并发**:UI 与系统服务类型均仅在主线程使用。若 `swift build` 报 Sendable / actor 隔离错误,在对应 target 的 `swiftSettings` 中加 `.swiftLanguageMode(.v5)` 放宽(本工具无多线程需求,这样最简单)。

---

### Task 1: SwiftPM 脚手架 + 冒烟测试

**Files:**
- Create: `Package.swift`
- Create: `Sources/DisplaySwitchCore/Placeholder.swift`
- Create: `Sources/DisplaySwitchApp/main.swift`
- Create: `Tests/DisplaySwitchCoreTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: 无
- Produces: 两个 target(`DisplaySwitchCore` library、`DisplaySwitchApp` executable)与测试 target,可 `swift build` / `swift test`。

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DisplaySwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DisplaySwitchCore"),
        .executableTarget(
            name: "DisplaySwitchApp",
            dependencies: ["DisplaySwitchCore"]
        ),
        .testTarget(
            name: "DisplaySwitchCoreTests",
            dependencies: ["DisplaySwitchCore"]
        ),
    ]
)
```

- [ ] **Step 2: 写最小占位源文件**

`Sources/DisplaySwitchCore/Placeholder.swift`:
```swift
// 占位,后续任务会替换为真实类型。先让 target 能编译。
public enum DisplaySwitchCore {
    public static let version = "0.0.1"
}
```

`Sources/DisplaySwitchApp/main.swift`:
```swift
import DisplaySwitchCore

// 占位入口,Task 8 会替换为真正的菜单栏启动代码。
print("DisplaySwitch \(DisplaySwitchCore.version)")
```

- [ ] **Step 3: 写冒烟测试**

`Tests/DisplaySwitchCoreTests/SmokeTests.swift`:
```swift
import Testing
@testable import DisplaySwitchCore

@Test("构建管道可用")
func buildPipelineWorks() {
    #expect(DisplaySwitchCore.version == "0.0.1")
}
```

- [ ] **Step 4: 写 .gitignore**

```
.build/
.swiftpm/
build/
*.xcodeproj
```

- [ ] **Step 5: 运行测试确认通过**

Run: `swift test`
Expected: 编译成功,`buildPipelineWorks` PASS。

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "🏗️ 搭建 SwiftPM 脚手架与冒烟测试"
```

---

### Task 2: DisplayInfo 值类型 + 外接屏筛选

**Files:**
- Create: `Sources/DisplaySwitchCore/DisplayInfo.swift`
- Delete: `Sources/DisplaySwitchCore/Placeholder.swift`
- Modify: `Sources/DisplaySwitchApp/main.swift`(移除对 Placeholder 的引用)
- Modify: `Tests/DisplaySwitchCoreTests/SmokeTests.swift`(移除对 Placeholder 的引用)
- Create: `Tests/DisplaySwitchCoreTests/DisplayQueryTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `struct DisplayInfo: Equatable, Sendable`,字段 `id: CGDirectDisplayID`、`uuid: String`、`name: String`、`bounds: CGRect`、`isMain: Bool`、`isBuiltin: Bool`、`isActive: Bool`,含全字段 `public init`。
  - `func externalDisplays(_ all: [DisplayInfo]) -> [DisplayInfo]`(过滤掉内建屏)。

- [ ] **Step 1: 写失败测试**

`Tests/DisplaySwitchCoreTests/DisplayQueryTests.swift`:
```swift
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
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test`
Expected: 编译失败(`DisplayInfo`、`externalDisplays` 未定义)。

- [ ] **Step 3: 实现 DisplayInfo 与筛选,删除占位**

删除 `Sources/DisplaySwitchCore/Placeholder.swift`。

`Sources/DisplaySwitchCore/DisplayInfo.swift`:
```swift
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

/// 只保留外接屏(排除内建屏)。
public func externalDisplays(_ all: [DisplayInfo]) -> [DisplayInfo] {
    all.filter { !$0.isBuiltin }
}
```

更新 `Sources/DisplaySwitchApp/main.swift`:
```swift
// 占位入口,Task 8 会替换为真正的菜单栏启动代码。
print("DisplaySwitch")
```

更新 `Tests/DisplaySwitchCoreTests/SmokeTests.swift`:
```swift
import Testing
@testable import DisplaySwitchCore

@Test("构建管道可用")
func buildPipelineWorks() {
    #expect(externalDisplays([]) == [])
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "🧱 定义 DisplayInfo 值类型与外接屏筛选"
```

---

### Task 3: 显示器左右命名

**Files:**
- Create: `Sources/DisplaySwitchCore/DisplayNaming.swift`
- Create: `Tests/DisplaySwitchCoreTests/DisplayNamingTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`(Task 2)
- Produces: `func displayLabel(for display: DisplayInfo, among externals: [DisplayInfo]) -> String`
  - 规则:基名取 `display.name`(空则 `"显示器"`);把 `externals` 按 `bounds.minX` 升序排;若恰 2 块,最左→`左`、最右→`右`;若 >2 块→`#序号`(从 1 起);若 1 块→无位置标签;主屏追加 `主屏`;标签用 `·` 连接放进全角括号。例:`Mi Monitor（左·主屏）` / `Mi Monitor（右）` / `Mi Monitor（主屏）` / `Mi Monitor`。

- [ ] **Step 1: 写失败测试**

`Tests/DisplaySwitchCoreTests/DisplayNamingTests.swift`:
```swift
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
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test`
Expected: 编译失败(`displayLabel` 未定义)。

- [ ] **Step 3: 实现命名**

`Sources/DisplaySwitchCore/DisplayNaming.swift`:
```swift
import CoreGraphics

/// 为某块外接屏生成菜单显示名:基名 +(位置·主屏)。
public func displayLabel(for display: DisplayInfo, among externals: [DisplayInfo]) -> String {
    let base = display.name.isEmpty ? "显示器" : display.name
    var tags: [String] = []

    let sorted = externals.sorted { $0.bounds.minX < $1.bounds.minX }
    if let idx = sorted.firstIndex(where: { $0.id == display.id }) {
        if sorted.count == 2 {
            tags.append(idx == 0 ? "左" : "右")
        } else if sorted.count > 2 {
            tags.append("#\(idx + 1)")
        }
    }
    if display.isMain { tags.append("主屏") }

    return tags.isEmpty ? base : "\(base)（\(tags.joined(separator: "·"))）"
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "🏷️ 实现显示器左右命名"
```

---

### Task 4: 机型感知保护规则

**Files:**
- Create: `Sources/DisplaySwitchCore/DisplayProtection.swift`
- Create: `Tests/DisplaySwitchCoreTests/DisplayProtectionTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`(Task 2)
- Produces: `func canDisable(_ target: DisplayInfo, among all: [DisplayInfo], hasBuiltIn: Bool) -> Bool`
  - 规则:target 必须是外接屏且当前 `isActive`,否则 `false`;`hasBuiltIn == true` 则允许;`hasBuiltIn == false` 时,当前活跃外接屏数量必须 `> 1`(关掉后仍 ≥1)。

- [ ] **Step 1: 写失败测试**

`Tests/DisplaySwitchCoreTests/DisplayProtectionTests.swift`:
```swift
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
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test`
Expected: 编译失败(`canDisable` 未定义)。

- [ ] **Step 3: 实现保护规则**

`Sources/DisplaySwitchCore/DisplayProtection.swift`:
```swift
import CoreGraphics

/// 判断能否关闭某块外接屏。机型感知:
/// - 有内建屏:任意活跃外接屏都可关(开盖用内建屏恢复)。
/// - 无内建屏:必须保留至少一块活跃外接屏。
public func canDisable(_ target: DisplayInfo, among all: [DisplayInfo], hasBuiltIn: Bool) -> Bool {
    guard !target.isBuiltin, target.isActive else { return false }
    if hasBuiltIn { return true }
    let activeExternals = all.filter { !$0.isBuiltin && $0.isActive }
    return activeExternals.count > 1
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "🛡️ 实现机型感知的关闭保护规则"
```

---

### Task 5: SystemDisplayService 协议 + DisplayController

**Files:**
- Create: `Sources/DisplaySwitchCore/SystemDisplayService.swift`
- Create: `Sources/DisplaySwitchCore/DisplayController.swift`
- Create: `Tests/DisplaySwitchCoreTests/DisplayControllerTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`、`displayLabel`、`canDisable`、`externalDisplays`(Task 2-4)
- Produces:
  - `protocol SystemDisplayService`:`func activeExternalDisplays() -> [DisplayInfo]`、`func hasBuiltInDisplay() -> Bool`、`func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool`。
  - `struct DisplayMenuItem: Equatable, Sendable`:`id: CGDirectDisplayID`、`label: String`、`isOn: Bool`、`canToggleOff: Bool`。
  - `final class DisplayController`:`init(service: SystemDisplayService)`、`func menuItems() -> [DisplayMenuItem]`、`@discardableResult func toggle(id: CGDirectDisplayID) -> Bool`、`func restoreAll()`。

- [ ] **Step 1: 写失败测试(含 Mock)**

`Tests/DisplaySwitchCoreTests/DisplayControllerTests.swift`:
```swift
import Testing
import CoreGraphics
@testable import DisplaySwitchCore

/// 可控的假系统服务:维护一份「全集」与「当前活跃」,模拟开关后的活跃变化。
final class MockService: SystemDisplayService {
    private var known: [CGDirectDisplayID: DisplayInfo]
    private var activeIDs: Set<CGDirectDisplayID>
    var builtIn: Bool
    var setResult = true
    private(set) var setCalls: [(id: CGDirectDisplayID, on: Bool)] = []

    init(all: [DisplayInfo], builtIn: Bool) {
        known = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        activeIDs = Set(all.filter { $0.isActive }.map { $0.id })
        self.builtIn = builtIn
    }

    func activeExternalDisplays() -> [DisplayInfo] {
        known.values
            .filter { !$0.isBuiltin && activeIDs.contains($0.id) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
    }
    func hasBuiltInDisplay() -> Bool { builtIn }
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        setCalls.append((id, on))
        guard setResult else { return false }
        if on { activeIDs.insert(id) } else { activeIDs.remove(id) }
        return true
    }
}

private func twoExternals() -> [DisplayInfo] {
    [makeInfo(id: 2, main: true, x: 0), makeInfo(id: 3, x: 1920)]
}

@Test("关闭一块外接屏会调用 setEnabled(false) 并记入已关闭")
func toggleOffRecordsDisabled() {
    let svc = MockService(all: twoExternals(), builtIn: false)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 3) == true)
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == false })
    let item = ctrl.menuItems().first { $0.id == 3 }
    #expect(item?.isOn == false)
}

@Test("无内建屏关到最后一块被拒绝,不调用 setEnabled")
func toggleOffLastExternalRejected() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: false)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 2) == false)
    #expect(svc.setCalls.isEmpty)
}

@Test("有内建屏可把唯一外接屏关掉")
func toggleOffLastExternalAllowedWithBuiltIn() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: true)
    let ctrl = DisplayController(service: svc)
    #expect(ctrl.toggle(id: 2) == true)
    #expect(svc.setCalls.contains { $0.id == 2 && $0.on == false })
}

@Test("重新打开已关闭的屏会调用 setEnabled(true) 并移出已关闭")
func toggleOnRestores() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)              // 关
    #expect(ctrl.toggle(id: 3) == true) // 开
    #expect(svc.setCalls.last?.on == true)
    #expect(ctrl.menuItems().first { $0.id == 3 }?.isOn == true)
}

@Test("menuItems 合并活跃与已关闭,均出现")
func menuItemsMergeActiveAndDisabled() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3) // 关掉 3
    let items = ctrl.menuItems()
    #expect(items.count == 2)
    #expect(items.first { $0.id == 2 }?.isOn == true)
    #expect(items.first { $0.id == 3 }?.isOn == false)
}

@Test("restoreAll 把所有已关闭的屏重新打开并清空")
func restoreAllReenables() {
    let svc = MockService(all: twoExternals(), builtIn: true)
    let ctrl = DisplayController(service: svc)
    _ = ctrl.toggle(id: 3)
    ctrl.restoreAll()
    #expect(svc.setCalls.contains { $0.id == 3 && $0.on == true })
    #expect(ctrl.menuItems().allSatisfy { $0.isOn })
}

@Test("无内建屏时唯一活跃屏的菜单项 canToggleOff 为 false")
func canToggleOffFalseForLastExternal() {
    let svc = MockService(all: [makeInfo(id: 2, x: 0)], builtIn: false)
    let ctrl = DisplayController(service: svc)
    let item = ctrl.menuItems().first { $0.id == 2 }
    #expect(item?.canToggleOff == false)
    #expect(item?.isOn == true)
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test`
Expected: 编译失败(`SystemDisplayService`、`DisplayController`、`DisplayMenuItem` 未定义)。

- [ ] **Step 3: 实现协议与控制器**

`Sources/DisplaySwitchCore/SystemDisplayService.swift`:
```swift
import CoreGraphics

/// 把所有与系统显示子系统的副作用交互藏在协议后,便于注入测试。
public protocol SystemDisplayService {
    /// 当前活跃(在线且启用)的外接屏。
    func activeExternalDisplays() -> [DisplayInfo]
    /// 这台机器是否具备内建屏(基于机器具备性,而非当前是否激活)。
    func hasBuiltInDisplay() -> Bool
    /// 启用/断开某块屏,返回是否成功。
    func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool
}
```

`Sources/DisplaySwitchCore/DisplayController.swift`:
```swift
import CoreGraphics

/// 渲染给菜单的一行。
public struct DisplayMenuItem: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let label: String
    public let isOn: Bool
    public let canToggleOff: Bool
}

/// 组合纯逻辑(命名/保护)与系统服务,维护「被本 app 关闭的屏」状态。
public final class DisplayController {
    private let service: SystemDisplayService
    /// 被本 app 关掉的屏(关闭前捕获的快照),用于在菜单里仍能显示并恢复。
    private var disabled: [CGDirectDisplayID: DisplayInfo] = [:]

    public init(service: SystemDisplayService) {
        self.service = service
    }

    public func menuItems() -> [DisplayMenuItem] {
        let active = service.activeExternalDisplays()
        let hasBuiltIn = service.hasBuiltInDisplay()
        // 合并:当前活跃 + 已关闭(去重,活跃优先),按 x 排序稳定显示。
        var byID: [CGDirectDisplayID: DisplayInfo] = [:]
        for d in disabled.values { byID[d.id] = d }
        for d in active { byID[d.id] = d }
        let ordered = byID.values.sorted { $0.bounds.minX < $1.bounds.minX }

        return ordered.map { d in
            let on = disabled[d.id] == nil
            let canOff = on ? canDisable(d, among: active, hasBuiltIn: hasBuiltIn) : false
            return DisplayMenuItem(id: d.id,
                                   label: displayLabel(for: d, among: ordered),
                                   isOn: on,
                                   canToggleOff: canOff)
        }
    }

    @discardableResult
    public func toggle(id: CGDirectDisplayID) -> Bool {
        // 当前关着 → 打开
        if disabled[id] != nil {
            guard service.setEnabled(id, true) else { return false }
            disabled[id] = nil
            return true
        }
        // 当前开着 → 尝试关闭(带保护校验)
        let active = service.activeExternalDisplays()
        guard let target = active.first(where: { $0.id == id }) else { return false }
        guard canDisable(target, among: active, hasBuiltIn: service.hasBuiltInDisplay()) else { return false }
        guard service.setEnabled(id, false) else { return false }
        disabled[id] = target
        return true
    }

    /// 恢复所有被本 app 关闭的屏(用于 app 退出兜底)。
    public func restoreAll() {
        for id in disabled.keys {
            _ = service.setEnabled(id, true)
        }
        disabled.removeAll()
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "🎛️ 实现 SystemDisplayService 协议与 DisplayController"
```

---

### Task 6: CGDisplayService 真实系统实现 + 手动 smoke

**Files:**
- Create: `Sources/DisplaySwitchCore/CGDisplayService.swift`
- Create: `spike/service_check.swift`(临时手动验证脚本)

**Interfaces:**
- Consumes: `DisplayInfo`、`SystemDisplayService`(Task 2、5)
- Produces: `final class CGDisplayService: SystemDisplayService`,额外暴露 `var isSupported: Bool`(私有符号是否解析成功)。`setEnabled` 内部用 `CGBeginDisplayConfiguration` + 私有 `CGSConfigureDisplayEnabled` + `CGCompleteDisplayConfiguration(_, .forAppOnly)`。

> 说明:本 target 真实调用系统/私有 API,无法用 swift-testing 自动断言(有硬件副作用),改为手动 smoke。逻辑正确性已由 Task 2-5 的纯逻辑/Mock 测试覆盖。

- [ ] **Step 1: 实现 CGDisplayService**

`Sources/DisplaySwitchCore/CGDisplayService.swift`:
```swift
import CoreGraphics
import ColorSync
import IOKit.ps
import AppKit

/// SystemDisplayService 的真实实现。封装 CoreGraphics 枚举、私有断开符号、内建屏检测。
public final class CGDisplayService: SystemDisplayService {
    private typealias ConfigEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
    private let cgsConfigureDisplayEnabled: ConfigEnabledFn?

    public init() {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        let sym = dlsym(handle, "CGSConfigureDisplayEnabled")
        cgsConfigureDisplayEnabled = sym.map { unsafeBitCast($0, to: ConfigEnabledFn.self) }
    }

    /// 私有断开符号是否可用;不可用时应禁用开关功能。
    public var isSupported: Bool { cgsConfigureDisplayEnabled != nil }

    public func activeExternalDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let mainID = CGMainDisplayID()
        return ids.compactMap { id in
            guard CGDisplayIsBuiltin(id) == 0 else { return nil }
            return DisplayInfo(
                id: id,
                uuid: Self.uuid(for: id),
                name: Self.name(for: id),
                bounds: CGDisplayBounds(id),
                isMain: id == mainID,
                isBuiltin: false,
                isActive: true
            )
        }
    }

    public func hasBuiltInDisplay() -> Bool {
        // 1) 在线列表里有内建屏 → 有。
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        if count > 0 {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            CGGetOnlineDisplayList(count, &ids, &count)
            if ids.contains(where: { CGDisplayIsBuiltin($0) != 0 }) { return true }
        }
        // 2) 便携机(有内建电池)→ 有内建屏(合盖时内建屏不在在线列表)。
        // 3) 都不满足 → 保守判定为「无内建屏」。
        return Self.hasInternalBattery()
    }

    public func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        guard let fn = cgsConfigureDisplayEnabled else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        let e = fn(cfg, id, on)
        // 首选 .forAppOnly:进程退出由系统自动回滚,天然防死锁。
        // 若 Step 2 实测断开不全局生效,改成 .forSession(见 Step 3 兜底)。
        let c = CGCompleteDisplayConfiguration(cfg, .forAppOnly)
        return e == .success && c == .success
    }

    private static func uuid(for id: CGDirectDisplayID) -> String {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, ref) as String? ?? ""
    }

    private static func name(for id: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? CGDirectDisplayID, num == id {
                return screen.localizedName
            }
        }
        return ""
    }

    private static func hasInternalBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
               let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 2: 手动 smoke —— 验证枚举/检测 + forAppOnly 是否全局生效**

写临时验证脚本 `spike/service_check.swift`:
```swift
import Foundation
// 复用源码:直接把 CGDisplayService 逻辑跑一遍。运行方式见下方命令。
import CoreGraphics

// 最小内联版断开测试,确认 .forAppOnly 是否让断开「全局生效」(活跃屏减少)。
let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
typealias Fn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let fn = unsafeBitCast(dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled")!, to: Fn.self)

func activeCount() -> UInt32 { var c: UInt32 = 0; CGGetActiveDisplayList(0, nil, &c); return c }
func setEnabled(_ id: CGDirectDisplayID, _ on: Bool, _ opt: CGConfigureOption) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    let e = fn(cfg, id, on)
    return e == .success && CGCompleteDisplayConfiguration(cfg, opt) == .success
}

var count: UInt32 = 0
CGGetActiveDisplayList(0, nil, &count)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
CGGetActiveDisplayList(count, &ids, &count)
let main = CGMainDisplayID()
guard count >= 2, let target = ids.first(where: { $0 != main }) else {
    print("需要至少 2 块屏且存在非主屏,跳过。"); exit(0)
}
print("forAppOnly 测试:断开非主屏 \(target),当前活跃=\(count)")
_ = setEnabled(target, false, .forAppOnly)
Thread.sleep(forTimeInterval: 2)
let afterOff = activeCount()
print("断开后活跃=\(afterOff) → \(afterOff < count ? "✅ forAppOnly 全局生效" : "❌ forAppOnly 不生效,需改用 .forSession")")
_ = setEnabled(target, true, .forAppOnly)
CGRestorePermanentDisplayConfiguration()
Thread.sleep(forTimeInterval: 2)
print("恢复后活跃=\(activeCount())")
```

Run(需用户在场、保存好副屏工作后执行):
```bash
swift /Users/bianzhiwen/projects/display-swich/spike/service_check.swift
```
Expected:打印 `✅ forAppOnly 全局生效` 且恢复后活跃屏回到原数量。

- [ ] **Step 3: 按 smoke 结果定配置选项**

- 若上一步是 `✅ forAppOnly 全局生效`:保持 `CGDisplayService.setEnabled` 用 `.forAppOnly`,无需改动。
- 若是 `❌ 不生效`:把 `CGCompleteDisplayConfiguration(cfg, .forAppOnly)` 改为 `.forSession`。这种情况下退出/启动恢复由 Task 8 的 `restoreAll()` 与启动兜底承担(Task 8 已包含)。

- [ ] **Step 4: 确认整体仍可构建,Core 测试仍通过**

Run: `swift build && swift test`
Expected:构建成功,Task 2-5 测试全 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplaySwitchCore/CGDisplayService.swift spike/service_check.swift
git commit -m "🖥️ 实现 CGDisplayService 真实系统层并完成 forAppOnly 实测"
```

---

### Task 7: 菜单栏 UI(StatusMenuController)

**Files:**
- Create: `Sources/DisplaySwitchApp/StatusMenuController.swift`

**Interfaces:**
- Consumes: `DisplayController`、`DisplayMenuItem`(Task 5)
- Produces: `final class StatusMenuController: NSObject`,`init(controller: DisplayController)`;内部持有 `NSStatusItem`,菜单通过 `menuNeedsUpdate` 每次打开时按 `controller.menuItems()` 重建(自然反映热插拔/状态变化)。

> 说明:UI 层用 AppKit,自动化测试价值低,采用手动验证;开关与保护逻辑已被 Core 测试覆盖。

- [ ] **Step 1: 实现 StatusMenuController**

`Sources/DisplaySwitchApp/StatusMenuController.swift`:
```swift
import AppKit
import CoreGraphics
import DisplaySwitchCore

/// 管理菜单栏图标与下拉菜单。每次菜单打开时重建,反映最新显示器状态。
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: DisplayController

    init(controller: DisplayController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display.2",
                                   accessibilityDescription: "显示器开关")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = controller.menuItems()

        if items.isEmpty {
            let empty = NSMenuItem(title: "未检测到外接显示器", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for item in items {
                let mi = NSMenuItem(title: item.label,
                                    action: #selector(toggleItem(_:)),
                                    keyEquivalent: "")
                mi.target = self
                mi.state = item.isOn ? .on : .off
                mi.representedObject = item.id
                // 开着但不允许关(无内建屏的最后一块)→ 禁用该项,避免误关。
                mi.isEnabled = !(item.isOn && !item.canToggleOff)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID else { return }
        controller.toggle(id: id)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: 确认编译通过**

Run: `swift build`
Expected:构建成功(此时 `main.swift` 仍是占位 print,未装配 UI,属正常)。

- [ ] **Step 3: Commit**

```bash
git add Sources/DisplaySwitchApp/StatusMenuController.swift
git commit -m "📊 实现菜单栏下拉菜单与点击切换"
```

---

### Task 8: 应用入口装配 + 退出恢复

**Files:**
- Create: `Sources/DisplaySwitchApp/AppDelegate.swift`
- Modify: `Sources/DisplaySwitchApp/main.swift`(替换占位为真正启动)

**Interfaces:**
- Consumes: `CGDisplayService`、`DisplayController`(Task 5、6)、`StatusMenuController`(Task 7)
- Produces: 可运行的 `.accessory`(无 Dock 图标)菜单栏 app;`applicationWillTerminate` 调 `controller.restoreAll()`;启动时做一次兜底恢复。

- [ ] **Step 1: 实现 AppDelegate**

`Sources/DisplaySwitchApp/AppDelegate.swift`:
```swift
import AppKit
import DisplaySwitchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = CGDisplayService()
    private lazy var controller = DisplayController(service: service)
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 只在菜单栏,不进 Dock

        // 启动兜底:若上次以 .forSession 关屏后异常退出,残留的断开屏在此恢复。
        // .forAppOnly 模式下本调用无副作用(配置已随上次进程退出回滚)。
        CGRestorePermanentDisplayConfiguration()

        menuController = StatusMenuController(controller: controller)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAll()
    }
}
```

- [ ] **Step 2: 替换 main.swift 为真正启动**

`Sources/DisplaySwitchApp/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: 确认编译通过**

Run: `swift build`
Expected:构建成功。

- [ ] **Step 4: 手动 smoke —— 直接运行**

Run: `swift run DisplaySwitchApp`
Expected:菜单栏出现 `display.2` 图标;点开能看到两块小米屏(带左/右·主屏标签);点副屏那行能断开(副屏变黑、窗口迁移)、再点能恢复;退出时被关的屏自动恢复。验证后 `Ctrl-C` 或点「退出」结束。

- [ ] **Step 5: Commit**

```bash
git add Sources/DisplaySwitchApp/AppDelegate.swift Sources/DisplaySwitchApp/main.swift
git commit -m "🚀 装配菜单栏应用入口与退出自动恢复"
```

---

### Task 9: 打包成 .app(菜单栏专用)

**Files:**
- Create: `scripts/package.sh`

**Interfaces:**
- Consumes: `DisplaySwitchApp` 可执行产物
- Produces: `build/DisplaySwitch.app`,含 `LSUIElement = true` 的 Info.plist 与 ad-hoc 签名,可双击运行为菜单栏程序。

- [ ] **Step 1: 写打包脚本**

`scripts/package.sh`:
```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DisplaySwitch.app"

swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/DisplaySwitchApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DisplaySwitch"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DisplaySwitch</string>
  <key>CFBundleDisplayName</key><string>显示器开关</string>
  <key>CFBundleIdentifier</key><string>com.local.displayswitch</string>
  <key>CFBundleExecutable</key><string>DisplaySwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "已生成 $APP"
```

- [ ] **Step 2: 赋可执行权限并运行打包**

Run:
```bash
chmod +x /Users/bianzhiwen/projects/display-swich/scripts/package.sh
/Users/bianzhiwen/projects/display-swich/scripts/package.sh
```
Expected:打印 `已生成 .../build/DisplaySwitch.app`,无报错。

- [ ] **Step 3: 手动 smoke —— 打开 .app**

Run: `open /Users/bianzhiwen/projects/display-swich/build/DisplaySwitch.app`
Expected:菜单栏出现图标(Dock 无图标);功能与 Task 8 一致。

- [ ] **Step 4: Commit**

```bash
git add scripts/package.sh
git commit -m "📦 添加打包脚本生成菜单栏 .app"
```

---

## 完成标准

- `swift test` 全绿(DisplayInfo/筛选/命名/保护/控制器逻辑)。
- `swift run DisplaySwitchApp` 或打包后的 `.app` 能在菜单栏列出外接屏、断开/恢复副屏、退出时自动恢复。
- 机型保护生效:无内建屏时最后一块外接屏不可关(菜单项灰显);有内建屏时可全关。
