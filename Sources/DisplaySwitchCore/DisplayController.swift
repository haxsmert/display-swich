import CoreGraphics

/// 渲染给菜单的一行。
public struct DisplayMenuItem: Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let label: String
    public let isOn: Bool
    public let canToggleOff: Bool
    public let isBuiltin: Bool
    /// 说明行,如「外接 · 3840×2160 · 60Hz」「内建 · 已关闭」。
    public let detail: String
    /// 开关被锁住(亮着却不能关)时的原因;能关、或本来就关着时为 nil。
    public let lockReason: String?
    /// 这一行可能出现的最长写法,界面按它预留宽度——开关屏、主屏转移时面板不变宽(他不要任何跳动)。
    /// 标签:任何一块亮着的屏都可能成为主屏,所以都带上主屏标记。
    public let sizingLabel: String
    /// 说明行亮着时的写法:关着的屏写「已关闭」,开回来会写分辨率,界面把它与当前写法一起排、取宽的那个。
    /// 见过它亮着才知道;没见过就是当前写法。
    public let sizingDetail: String
}

/// 需要救援、但此刻下指令注定失败时,在等什么。
public enum RescueDeferral: Equatable, Sendable {
    case lidClosed
    case displaysAsleep
}

/// 组合纯逻辑(命名/保护)与系统服务,维护「被本 app 关闭的屏」状态。
public final class DisplayController {
    private let service: SystemDisplayService
    /// 被本 app 关掉的屏(关闭前捕获的快照),用于在菜单里仍能显示并恢复。
    private var disabled: [CGDirectDisplayID: DisplayInfo] = [:]
    /// 每块屏最近一次取到的名字(键见 `key(of:)`)。见 `activeDisplays()`。
    private var knownNames: [String: String] = [:]
    /// 每块屏最近一次亮着时的说明行,给关着的屏预留宽度用(见 `DisplayMenuItem.sizingDetail`)。
    private var knownLitDetails: [String: String] = [:]

    /// 一块屏的稳定键:UUID,取不到时用 display ID。
    private func key(of d: DisplayInfo) -> String { d.uuid.isEmpty ? "id-\(d.id)" : d.uuid }

    public init(service: SystemDisplayService) {
        self.service = service
    }

    /// 当前活跃的屏;名字暂时取不到的,沿用这块屏上次的名字。
    ///
    /// 屏名来自 AppKit 的屏幕列表,它比 CoreGraphics 的活跃列表更新得晚:实测(2026-10-22)点亮一块外接屏后,
    /// 活跃列表立刻就有它,屏幕列表 1.8 秒后仍没有,这期间名字是空的。空名会退成「显示器」——标签变了,
    /// 按名字排序还会把它排到最后,几毫秒后名字到了又跳回原位:面板那一行先跳走再跳回,
    /// 行首图标的动画把这一跳播了出来(他看到的「从上面滑下来」)。屏的名字不会变,空名只说明「还没取到」。
    private func activeDisplays() -> [DisplayInfo] {
        service.activeDisplays().map { d in
            if !d.name.isEmpty { knownNames[key(of: d)] = d.name; return d }
            guard let name = knownNames[key(of: d)] else { return d }
            return DisplayInfo(id: d.id, uuid: d.uuid, name: name, bounds: d.bounds,
                               isMain: d.isMain, isBuiltin: d.isBuiltin, isActive: d.isActive)
        }
    }

    /// 系统是否支持开关(私有符号存在)。不支持时 UI 应只读并提示,各项 canToggleOff 亦为 false。
    public var isSupported: Bool { service.isSupported }

    /// 把「已被本 app 关闭」的记录与系统真相对账。每次读状态前跑一遍即可自愈,不依赖任何回调。
    ///
    /// **正向**:任何当前活跃的屏一律视为「开」并从 disabled 剔除。远程会话重配置 / 睡眠唤醒 /
    /// 重新插拔会在 app 之外把被关的屏重新点亮;不对齐的话,菜单会把一块活跃屏显示成「关」,
    /// 且因 app 误以为它仍关着、再点会被当成「开」,于是永远勾不上。
    ///
    /// **反向**:已被物理拔走的屏要从 disabled 剔除,否则它会像幽灵一样长期赖在菜单里
    /// (点它只是对一个已失效的 display ID 调开屏,毫无效果)。难点在于 CoreGraphics 分不出
    /// 「被我软件关掉」和「被拔掉」——两种情况下该屏都从 online 列表消失、UUID 也解析不出;
    /// 只有 IOKit 还留着那条物理连接,故改用它的物理外接屏数来对账。
    private func reconcileDisabled(active: [DisplayInfo]) {
        let activeIDs = Set(active.map { $0.id })
        disabled = disabled.filter { !activeIDs.contains($0.key) }
        // 反向对账**不再删除记录**,改由 `canShowDisabledExternals` 在渲染时过滤,原因见那里。
    }

    /// 被本 app 关掉的外接屏,物理上是否还有位置容纳它们 —— 决定它们**显不显示**,而不是删不删。
    ///
    /// 拔走后物理数减少 → 返回 false → 菜单里不出现(不留幽灵项,这是 v1.0.3 的目标);
    /// 线插回来后物理数恢复 → 返回 true → 重新出现,用户点一下就能开回来。
    ///
    /// ⚠️ 为什么不能像以前那样直接删记录:**被关闭的状态是跟着显示器走的,不跟着线走**。
    /// 那块屏在 WindowServer 里仍然是关闭状态,线插回来时它不会自己亮;记录一删,
    /// app 就忘了它,菜单里看不到、也点不开 → 彻底失联。
    /// 2026-09-18 真实发生过:一块外接屏插回来后从菜单里消失,最后是靠私有接口
    /// `CGSGetDisplayList` 枚举出「被禁用的屏」才捞回来的。
    ///
    /// 查不到物理连接(`nil`)时一律显示:宁可多显示一项(点了无效、实测不阻塞),
    /// 也不能让用户开不回一块还连着的屏。
    ///
    /// ⚠️ 判据必须是 `liveExternalCount`(带 EDID 的传输节点)。曾经有过一个 framebuffer 判据
    /// (数 `DisplayWidth` 键),屏一被禁用该键就消失,于是它**数不到被关掉的屏**——
    /// 正是这里要找的那一类。实测(2026-09-18)两块外接屏关掉其一时它报 1、EDID 判据报 2,
    /// 用它算出「没有位置」,那块还连着的屏就被从菜单里藏了起来。那个判据已被删除。
    private func canShowDisabledExternals(active: [DisplayInfo]) -> Bool {
        guard let physical = service.liveExternalCount() else { return true }
        return physical - active.filter { !$0.isBuiltin }.count > 0
    }

    /// 是否存在「可开盖恢复的内建屏」兜底:机器有内建屏面板,且内建屏当前未被本 app 软件关闭。
    /// (被软件关掉的内建屏开盖救不回,不算兜底。)
    private func builtInFallbackAvailable() -> Bool {
        let builtInDisabledByUs = disabled.values.contains { $0.isBuiltin }
        return service.hasBuiltInDisplay() && !builtInDisabledByUs
    }

    public func menuItems() -> [DisplayMenuItem] {
        let active = activeDisplays()
        reconcileDisabled(active: active)
        var byID: [CGDirectDisplayID: DisplayInfo] = [:]
        // 被关掉的外接屏若已被物理拔走就不显示(不留幽灵),插回来则重新显示(不失联)。
        // 内建屏不受此限:它不会被拔走,合盖也只是暂时不活跃。
        let showDisabledExternals = canShowDisabledExternals(active: active)
        for d in disabled.values {
            guard d.isBuiltin || showDisabledExternals else { continue }
            // 已被本 app 断开的屏不可能是主屏:显示时清除 isMain,
            // 否则关掉主屏后(主屏角色转移给另一块)会出现两块都标「主屏」的错乱。
            byID[d.id] = DisplayInfo(id: d.id, uuid: d.uuid, name: d.name, bounds: d.bounds,
                                     isMain: false, isBuiltin: d.isBuiltin, isActive: false)
        }
        for d in active { byID[d.id] = d }
        // 按稳定键(基名+UUID)排序:同名屏相邻、与编号同序,不随位置漂移。
        let ordered = byID.values.sorted {
            (baseName($0.name), $0.uuid, $0.id) < (baseName($1.name), $1.uuid, $1.id)
        }
        // 整组(活跃+已关闭)一起算标签:同名屏按 UUID 稳定编号,关掉其一不丢号、重开不漂移。
        let labels = displayLabels(for: ordered)
        let fallback = builtInFallbackAvailable()
        return ordered.map { d in
            let on = disabled[d.id] == nil
            let canOff = (service.isSupported && on) ? canDisable(d, among: active, builtInFallback: fallback) : false
            let label = labels[d.id] ?? displayLabel(for: d)
            let detail = detailLine(for: d, isOn: on)
            if on { knownLitDetails[key(of: d)] = detail }
            return DisplayMenuItem(id: d.id, label: label, isOn: on, canToggleOff: canOff,
                                   isBuiltin: d.isBuiltin, detail: detail,
                                   lockReason: (service.isSupported && on && !canOff) ? lockReason : nil,
                                   sizingLabel: label.hasSuffix(mainMarker) ? label : label + mainMarker,
                                   sizingDetail: knownLitDetails[key(of: d)] ?? detail)
        }
    }

    /// 说明行:内建 / 外接 → 分辨率与刷新率(亮着时)或「已关闭」。不写接法,原因见 PanelText。
    private func detailLine(for d: DisplayInfo, isOn: Bool) -> String {
        var parts = [d.isBuiltin ? "内建" : "外接"]
        if !isOn {
            parts.append("已关闭")
        } else if let mode = service.currentMode(d.id) {
            parts.append(modeText(mode))
        }
        return parts.joined(separator: " · ")
    }

    /// 亮着却不能关时,说清为什么。`canDisable` 判否只有一种情形:关掉后一块亮着的屏都不剩
    /// (且没有可开盖恢复的内建屏兜底),所以原因只有一条,措辞取他本人的说法(2026-10-22)。
    /// 曾按「内建屏被关」另给一句「先打开它才能关这块」,他指出含义不对:规则是保底,不是开内建屏的前提。
    private var lockReason: String { lockReasonText }

    /// 残影屏块数:在线的外接屏比物理连着的多出来的块数;查不到物理连接时为 0,不猜。
    /// 雷雳显示驱动卡死后拔坞,拆不掉已拔走的屏,系统仍当它们在线(2026-10-22 实测:物理 0、在线 2)。
    /// 被本 app 关掉的屏物理上还连着、只是不在线,不会被算进来。
    /// 注意:插回时在线数会比物理数早约 1 秒恢复,判残影要隔几秒复核(调用方负责)。
    public func ghostScreenCount() -> Int {
        guard let physical = service.liveExternalCount() else { return 0 }
        let activeExternal = service.activeDisplays().filter { !$0.isBuiltin }.count
        return max(0, activeExternal - physical)
    }

    @discardableResult
    public func toggle(id: CGDirectDisplayID) -> Bool {
        // 私有符号缺失:开关不可用,直接拒绝(恢复走 restoreAll/启动兜底,不受此限)。
        guard service.isSupported else { return false }
        // 先与系统真实活跃状态对账:被系统在 app 之外重新点亮的屏要从 disabled 剔除,
        // 否则一块已经活跃的屏会被误当成「关着」而走进开屏分支。
        let active = activeDisplays()
        reconcileDisabled(active: active)
        // 当前关着 → 打开
        if disabled[id] != nil {
            guard service.setEnabled(id, true) else { return false }
            disabled[id] = nil
            return true
        }
        // 当前开着 → 尝试关闭(带保护校验)
        guard let target = active.first(where: { $0.id == id }) else { return false }
        guard canDisable(target, among: active, builtInFallback: builtInFallbackAvailable()) else { return false }
        guard service.setEnabled(id, false) else { return false }
        disabled[id] = target
        return true
    }

    /// 全黑兜底:拔线导致「一块能亮的屏都不剩」时,把本 app 关掉的屏开回来。返回是否执行了救援。
    ///
    /// 为什么 `canDisable` 不够:它只校验**按下开关那一刻**——关内建屏时外接屏还活跃,
    /// 判定合法、并没有错。错的是那之后世界会变:作兜底的那块活跃屏可能被物理拔走
    /// (拔拓展坞 / 拔线 / 外接屏断电),而 WindowServer 仍记着被本 app 关掉的屏
    /// (`.forAppOnly` 实测不因拔线回滚)→ 一块能亮的都不剩 → 全黑。
    /// 而本 app 其余的对账全挂在 `menuItems()` / `toggle()` 上,即**只有用户点开菜单才会跑**;
    /// 全黑时用户根本点不开菜单栏,死局无法自愈,只能强制重启。
    ///
    /// **判据完全不用 CoreGraphics 的活跃屏列表**,只用 IOKit 物理真相 + 本 app 自己的关闭记录。
    /// 实测(M 系列 · macOS 26 · 2026-09-07,拔拓展坞现场抓的日志):
    ///   - 拔线瞬间 IOKit 带 EDID 的显示节点已归零,而同一刻 `CGGetActiveDisplayList`
    ///     仍报拔线前的 3 块屏(陈旧缓存);
    ///   - 且拔线**根本不派发** `CGDisplayRegisterReconfigurationCallback`(全程 0 次)。
    ///   即 CoreGraphics 在拔线这件事上**既不通知、读数又陈旧**,不能作判据——
    ///   这也是 v1.0.6 那版救援实际上从不触发的原因。
    ///
    /// 判据(P = IOKit 物理外接屏数,D = 本 app 关掉的外接屏数):
    ///   `P ≤ D` → 物理还在的外接屏可能全是被本 app 关掉的那些,即外接屏可能一块都不亮;
    ///   再加上「内建屏也被本 app 关掉、或这台机器根本没有内建屏面板」→ 判定全黑。
    /// 该判据对「拔掉的到底是哪一块」不敏感,故不需要区分——而区分正是做不到的事。
    /// 当前是否处于「需要救援的全黑」。**纯读,不动手**,故可被高频事件源随意调用。
    public func needsBlackoutRescue() -> Bool {
        // 没关过任何屏 → 屏黑与本 app 无关,不动手也不查系统。
        guard !disabled.isEmpty else { return false }
        // 查不到物理连接就什么都不做:无法证明任何一块屏已被拔走。
        // 救援发生在拔线通知到达那一刻,判据必须当场准确(见协议注释)。
        guard let physical = service.liveExternalCount() else { return false }
        let disabledExternals = disabled.values.filter { !$0.isBuiltin }.count
        // 还有外接屏没被本 app 关掉 → 它亮着,不是全黑。
        guard physical <= disabledExternals else { return false }
        // 内建屏还能亮(有面板且没被本 app 关掉)→ 不是全黑,绝不擅自开屏。
        let builtinDisabledByUs = disabled.values.contains { $0.isBuiltin }
        guard !(service.hasBuiltInDisplay() && !builtinDisabledByUs) else { return false }
        return true
    }

    /// 需要救援、但此刻下指令注定失败时,在等什么;`nil` = 可以动手,或根本不需要救。纯读。
    ///
    /// 两种「等」性质不同,调用方要如实记录是哪一种:
    ///   - `.lidClosed`:只剩内建屏能救,而盖子合着——它物理上不可用,点亮会阻塞约 20 秒后失败
    ///     (2026-09-18 实测)。等开盖,那才是它重新可用的时刻。
    ///   - `.displaysAsleep`:屏幕在睡眠——WindowServer 把拔出事件推迟到唤醒再处理,
    ///     此刻的配置调用会在调用线程上忙等「上一次重配置完成」约 10 秒后失败
    ///     (2026-09-22 实测:两次各卡约 10 秒,一分钟刷出约 62 万行日志;屏幕醒着时同样的调用
    ///     9/22、9/23、9/24 三次都在 0.1 秒内完成)。它挡的是**任何一块屏**的点亮,等唤醒。
    /// 两者同时成立且只剩内建屏能救时报 `.lidClosed`:唤醒不等于开盖,开盖才是它能亮的时刻。
    ///
    /// 两种情况下记录都原样留着,`needsBlackoutRescue()` 依然成立,
    /// 「开盖 / 唤醒」触发源到来时救援会重新进行。
    public func rescueDeferral() -> RescueDeferral? {
        guard needsBlackoutRescue() else { return nil }
        return deferralReason()
    }

    /// `rescueDeferral` 的判定本身,前提是已确认需要救援。
    private func deferralReason() -> RescueDeferral? {
        if service.liveExternalCount() == 0, service.isClamshellClosed() == true { return .lidClosed }
        if service.isDisplaySystemAsleep() == true { return .displaysAsleep }
        return nil
    }

    /// 执行救援。返回**是否真的对系统下了恢复指令**——
    /// `false` 有两种含义:不需要救(见 `needsBlackoutRescue`),或需要救但此刻注定失败
    /// (见 `rescueDeferral`)。调用方要区分二者,先问这两个。
    @discardableResult
    public func rescueFromBlackout() -> Bool {
        guard needsBlackoutRescue() else { return false }
        guard deferralReason() == nil else { return false }

        // 外接屏一块都不在了 → 这一轮只可能靠内建屏解除全黑,跳过那些屏的恢复调用。
        //
        // ⚠️ 但**绝不丢弃它们的记录**。被关闭的状态是跟着**显示器**走的,不是跟着线走的:
        // 那些屏在 WindowServer 里仍然是关闭状态,线插回来时它们不会自己亮。
        // 若 app 此时已经忘了它们,菜单里看不到、也点不开,就彻底失联了——
        // 这正是 v1.0.9/v1.0.10 的回归:一块外接屏插回来后从菜单里消失,
        // 只能靠私有接口 CGSGetDisplayList 枚举出被禁用的屏才捞回来。
        // 记录留着,插回来时菜单仍列得出它,用户点一下就能开。
        let onlyBuiltInCanHelp = (service.liveExternalCount() == 0)
        restoreAll(where: onlyBuiltInCanHelp ? { $0.isBuiltin } : { _ in true })
        return true
    }

    /// 救援判据的当前取值快照,供诊断日志记录。纯读,不产生任何副作用。
    /// 全黑时界面全无,失败现场会随强制重启消失——不记下每个判据的实际取值,
    /// 事后就只能靠推断分不清「判据否决了救援」和「压根没进判断」。
    public func blackoutDiagnostics() -> String {
        let all = disabled.values
        let ext = all.filter { !$0.isBuiltin }.count
        let live = service.liveExternalCount().map(String.init) ?? "查询失败"
        let asleep = service.isDisplaySystemAsleep().map(String.init) ?? "查询失败"
        // 连着哪些接口:拓展坞与机身 HDMI 的拔线机制不同(见 §7.3),事后靠它分清是哪条路径。
        let ports = service.liveExternalPorts().map { "[\($0.joined(separator: ", "))]" } ?? "查询失败"
        return "本app已关屏=\(all.count)(内建 \(all.count - ext) / 外接 \(ext))"
             + " | 瞬时外接屏=\(live) | 有内建面板=\(service.hasBuiltInDisplay()) | 屏幕睡眠=\(asleep)"
             + " | 外接屏连接=\(ports)"
    }

    /// 启动兜底:把系统里「上一次进程遗留的、还关着的屏」全部点亮。返回真正点亮的块数。
    ///
    /// 这一步**完全不依赖本 app 的记账**,直接问系统要真相 —— 因为记账恰恰在这种场景下是空的:
    /// 进程一死(崩溃 / 被强杀 / 注销)记录就没了,而被关闭的状态留在 WindowServer 里
    /// **不会自己恢复**。那块屏于是既不在活跃列表、也不在记账里,菜单上根本看不到 ——
    /// 彻底失联,用户只能重启整台机器。2026-09-18 真实发生过一次。
    ///
    /// 只在启动时做:此刻记账必然是空的,系统里任何「存在但没点亮」的屏都是上次的遗留,
    /// 点亮它们既安全、也符合「app 启动即回到干净状态」的既有语义(§7.2 的逃生链条依赖它)。
    /// 候选里混着空槽位,对它们的调用会立刻失败(实测 0.0 秒,不阻塞),无害。
    @discardableResult
    public func reviveOrphanedDisplays() -> Int {
        guard let candidates = service.inactiveDisplayIDs() else { return 0 }
        var revived = 0
        for id in candidates where service.setEnabled(id, true) { revived += 1 }
        return revived
    }

    /// 恢复所有被本 app 关闭的屏(app 退出兜底 / 全黑救援)。
    ///
    /// **只清掉真正恢复成功的那些**:系统调用失败却照样清记录,等于把失败谎报成成功——
    /// 屏还黑着,菜单里却连那块屏都没了,用户既看不见画面也点不回来(双重失联)。
    /// 记录留着,菜单仍列得出它,救援下一轮也还能重试。
    /// `shouldRestore` 限定这一轮恢复哪些屏(默认全部)。**被跳过的记录原样保留**——
    /// 跳过只是「这次先不试」,不是「这块屏不用管了」。
    public func restoreAll(where shouldRestore: (DisplayInfo) -> Bool = { _ in true }) {
        for d in Array(disabled.values) where shouldRestore(d) && service.setEnabled(d.id, true) {
            disabled[d.id] = nil
        }
    }
}
