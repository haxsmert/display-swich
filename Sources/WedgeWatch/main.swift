import AppKit
import IOKit.ps
import UserNotifications

// 雷雳显示驱动卡死的菜单栏监视器(安装与背景见 scripts/wedge-watch.sh)。
//
// 与 DisplaySwitch 完全分开:不链接它的任何代码,不碰显示器——
// 2026-10-26 起他停用 DisplaySwitch 做对照实验,监视器不能成为新的变量。
// 判断卡没卡只读系统日志;唤醒和插拔坞只被动收系统通知;发现卡住之后才去抓现场(见 Evidence)。
// 图标常驻菜单栏(他:「要放个图标让我知道,不要偷偷摸摸」)。
// 每 4 小时查一次(他定的),外加屏幕唤醒、插拔坞之后各查(2026-10-28 他同意加):
// 卡死的起点都在唤醒重连时,而卡着时插回坞约 60 秒就崩溃——10-27、10-28 两次都是在 4 小时的空档里照常插拔才崩的。
// 刚卡上时要过 1 分钟才开始刷报错(报错原文是「evaluating for > 1m」,推断),所以事件后 75 秒那次才看得见刚起的卡死。

/// 这次检查是怎么触发的,记进检查记录和现场说明。
enum Trigger: String {
    case launch = "启动", timer = "定时", wake = "唤醒后", dock = "插拔坞后", manual = "手动"
}

enum Command {
    /// 跑一个命令取标准输出;起不来、超时被掐或非 0 退出时为 nil。会阻塞,只能在后台线程调。
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return data
    }
}

/// 判据:卡死时内核每秒刷 10 条 `evaluating for > 1m ... DPO [...]`,健康时 0 条,实时采 3 秒就够。
/// 三个环境变量只供验证用(换成一个必有输出的谓词、记到另一份文件、缩短间隔),平时不设。
enum Probe {
    private static let env = ProcessInfo.processInfo.environment
    static let isTest = env["WEDGE_WATCH_PREDICATE"] != nil
    private static let predicate = env["WEDGE_WATCH_PREDICATE"]
        ?? #"process == "kernel" AND eventMessage CONTAINS "evaluating for > 1m""#
    static let logURL = URL(fileURLWithPath: env["WEDGE_WATCH_LOG"]
        ?? NSHomeDirectory() + "/Library/Logs/DisplaySwitch-wedge-watch.log")
    /// 每 4 小时查一次(他定的)。
    static let interval = env["WEDGE_WATCH_INTERVAL"].flatMap(TimeInterval.init) ?? 4 * 3600

    /// 3 秒里卡死特征的条数;读不到日志(命令失败或卡住)时为 nil。要阻塞约 3 秒,只能在后台线程调。
    static func sample() -> Int? {
        // 用 log 自带的 --timeout 正常退出:从外面用信号掐断会丢掉还没写出的输出(2026-10-26 实测漏数)。
        guard let data = Command.run("/usr/bin/log", ["stream", "--timeout", "3s", "--predicate", predicate, "--style", "compact"],
                                     timeout: 15) else { return nil }
        // 表头那行带着谓词原文,所以数报错正文里才有的 `DPO [`。
        return String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.contains("DPO [") }.count
    }

    /// 每次结果记一行,对照实验收尾时按它看每段时间的状态。只留最近一段:平时每天十来行,2000 行够半年。
    static func record(_ count: Int?, _ trigger: Trigger) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = count.map { "卡死特征 \($0) 条 / 3 秒" } ?? "读不到系统日志"
        let line = "[\(stamp.string(from: Date()))] \(isTest ? "【测试】" : "")\(text)（\(trigger.rawValue)）\n"
        var lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 3000 { lines = lines.suffix(2000) }
        let kept = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? (kept + line).write(to: logURL, atomically: true, encoding: .utf8)
    }
}

/// 卡住时留现场,报给 Apple 时补交。2026-10-28 起:之前几次卡住的现场都没留下,
/// 带函数名的关机卡住报告也在一周内被系统清掉,最后报上去的只剩抄录的几行。全部只读、不要密码。
/// **只在发现卡住之后才抓**(他:「应该是触发式的,比如发现卡住了,再去抓信息」),平时什么都不读、不拷。
/// 每次卡住一个文件夹 `~/Library/Logs/DisplaySwitch-wedge-evidence/wedge-<时间>/`:
/// - 发现时当场存:内核日志、设备树里 DP 适配器的状态、近 24 小时的唤醒与屏幕插拔、睡眠与充电记录;
/// - 重启后补齐:这次卡住之后才写出来的崩溃 / 关机卡住报告(原件约一周就被清),和他按组合键收的完整诊断。
enum Evidence {
    /// 环境变量只供验证用(存到另一处),平时不设。
    static let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WEDGE_WATCH_EVIDENCE"]
        ?? NSHomeDirectory() + "/Library/Logs/DisplaySwitch-wedge-evidence")
    /// 已报给 Apple 的那份反馈,补交现场时加到它上面。
    static let feedbackID = "FB25346775"
    /// 现场里的「待补」标记,内容是发现卡住的时刻(Unix 秒);重启后补齐、过了时限就删掉。
    private static let pendingName = ".pending"

    /// 存一份卡住现场,返回它的文件夹;要跑一两分钟,只能在后台线程调。
    static func capture(_ trigger: Trigger, count: Int) -> URL {
        let now = Date()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folder = root.appendingPathComponent("wedge-\(stamp.string(from: now))\(Probe.isTest ? "-test" : "")")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? String(now.timeIntervalSince1970).write(to: folder.appendingPathComponent(pendingName), atomically: true, encoding: .utf8)
        func save(_ name: String, _ data: Data?) {
            try? (data ?? Data("（没取到）\n".utf8)).write(to: folder.appendingPathComponent(name))
        }
        // 先取内核日志:本机内核日志不落盘,内存里只留约 1 分钟,晚一步就没了。
        save("kernel-last-2m.txt", Command.run("/usr/bin/log", ["show", "--last", "2m", "--predicate", #"process == "kernel""#,
                                                                "--style", "compact"], timeout: 120))
        save("kernel-thunderbolt-10s.txt", Command.run("/usr/bin/log", ["stream", "--timeout", "10s", "--predicate",
                                                                        #"process == "kernel" AND eventMessage CONTAINS[c] "thunderbolt""#,
                                                                        "--style", "compact"], timeout: 30))
        var ioreg = Data()
        for name in ["AppleThunderboltDPOutAdapterOS2", "AppleThunderboltDPInAdapterOS2"] {
            ioreg.append(Data("===== \(name) =====\n".utf8))
            ioreg.append(Command.run("/usr/sbin/ioreg", ["-l", "-w0", "-r", "-c", name], timeout: 30) ?? Data("（没取到）\n".utf8))
        }
        save("ioreg-dp-adapters.txt", ioreg)
        save("windowserver-24h.txt", Command.run("/usr/bin/log", ["show", "--last", "24h", "--predicate",
                                                                  #"process == "WindowServer" AND (eventMessage CONTAINS "hot plug" OR eventMessage CONTAINS "hotplug" OR eventMessage CONTAINS "Did Wake")"#,
                                                                  "--style", "compact"], timeout: 300))
        save("pmset-log-tail.txt", Command.run("/usr/bin/pmset", ["-g", "log"], timeout: 60).map {
            Data(String(decoding: $0, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
                .suffix(3000).joined(separator: "\n").utf8)
        })
        save("README.txt", Data(readme(at: now, trigger, count: count).utf8))
        return folder
    }

    private static func readme(at date: Date, _ trigger: Trigger, count: Int) -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        雷雳显示驱动卡住了，这里是自动存下的现场。
        时间：\(stamp.string(from: date))
        怎么发现的：\(trigger.rawValue)检查，卡死特征 \(count) 条 / 3 秒

        文件：
        kernel-last-2m.txt          内存里最近约 2 分钟的内核日志（这台机器的内核日志不落盘，只有当场取得到）
        kernel-thunderbolt-10s.txt  10 秒里内核关于雷雳的记录
        ioreg-dp-adapters.txt       设备树里各路 DP 适配器的状态
        windowserver-24h.txt        近 24 小时的唤醒和屏幕插拔
        pmset-log-tail.txt          睡眠、唤醒和充电记录（坞给电脑供电，充电状态一切换就是插拔了坞）

        接下来：
        1. 卡住时别拔坞：拔了屏幕拆不掉，插回约 60 秒就崩溃。
        2. 同时按 ⌃⌥⇧⌘ 和句号键，收一份完整诊断（要几分钟）。
        3. 存好东西，接着坞重启。重启后，完整诊断和这次卡住之后的崩溃、关机卡住报告会自动补进这个文件夹（关机卡住报告可能要过几个小时才出来）。
        4. 把这个文件夹补交到 \(feedbackID)：在反馈助理里打开这份反馈，点「添加附件」。

        """
    }

    /// 给重启前存下的现场补齐卡住之后才出现的文件,拷过的跳过;没有待补的现场就什么都不读。只能在后台线程调。
    /// 系统的报告都是开机后才写出来的:崩溃报告在开机约 1.5 分钟后(10-28),关机卡住报告晚到几个小时(10-27 的两份晚了约 5 小时),
    /// 所以开机后每次检查都补一次,开机满一天才去掉待补标记。
    static func completePending() {
        let manager = FileManager.default
        guard let boot = bootTime(),
              let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders where folder.lastPathComponent.hasPrefix("wedge-") {
            let marker = folder.appendingPathComponent(pendingName)
            guard let text = try? String(contentsOf: marker, encoding: .utf8),
                  let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
            let found = Date(timeIntervalSince1970: seconds)
            // 还在发现卡住的那次开机里:没重启过,报告还没有,接着等。
            guard found < boot else { continue }
            // 跳过隐藏的 `.contents.panic`:它是最近一次崩溃的摘要,每次都被覆盖。
            copyNew(from: "/Library/Logs/DiagnosticReports", into: folder) { name, modified in
                !name.hasPrefix(".") && (name.hasSuffix(".panic") || name.hasSuffix(".shutdownStall")) && modified >= found
            }
            // 收诊断时最后才打包成 .tar.gz,一分钟没再改过才算收完,免得拷到半截。
            copyNew(from: "/private/var/tmp", into: folder) { name, modified in
                name.hasPrefix("sysdiagnose_") && name.hasSuffix(".tar.gz") && modified >= found && Date().timeIntervalSince(modified) > 60
            }
            if Date().timeIntervalSince(boot) > 24 * 3600 { try? manager.removeItem(at: marker) }
        }
    }

    private static func bootTime() -> Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
    }

    private static func copyNew(from source: String, into target: URL, where wanted: (String, Date) -> Bool) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: source) else { return }
        for name in names {
            let from = URL(fileURLWithPath: source).appendingPathComponent(name)
            let to = target.appendingPathComponent(name)
            guard !manager.fileExists(atPath: to.path),
                  let attributes = try? manager.attributesOfItem(atPath: from.path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let modified = attributes[.modificationDate] as? Date,
                  wanted(name, modified) else { continue }
            try? manager.createDirectory(at: target, withIntermediateDirectories: true)
            try? manager.copyItem(at: from, to: to)
        }
    }
}

final class WatchApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum State { case notYet, normal, wedged, unreadable }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var state = State.notYet
    private var checking = false
    private var lastCheck: Date?
    private var nextCheck = Date()
    private var tick: Timer?
    /// 当前由什么供电。坞给电脑供电,它一变就是插拔了坞。
    private var powerSource: String?
    private var savingEvidence = false
    private var lastEvidence: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // 按墙上时间判断到点:Timer 按开机时长计,机器睡着时不走,直接排 4 小时会被睡眠拖后。
        tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, Date() >= self.nextCheck else { return }
            self.check(.timer)
        }
        tick?.tolerance = 30
        // 屏幕醒来约 2.5 秒后两块屏会掉线重连,卡死就起在这一下,要再过 1 分钟才开始刷报错。
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.check(.wake, after: 75)
        }
        observeDock()
        check(.launch)
        // 若上次开机里卡住过:崩溃报告开机后一两分钟才写出来,过 3 分钟给那份现场补一次。没卡过就什么都不读。
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180) { Evidence.completePending() }
    }

    /// 插拔坞后查两次。10 秒那次看拔之前就已经卡着的(拔坞后系统正常 5 秒内就拆完外接屏):卡着时拔坞会留下拆不掉的屏,
    /// 插回约 60 秒就崩溃——拔完图标立刻变红,他才知道先重启、别插回;插回时卡着,也赶在崩溃前把现场存下。
    /// 75 秒那次看是不是这一下刚卡上的。
    private func observeDock() {
        powerSource = Self.currentPowerSource()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<WatchApp>.fromOpaque(context).takeUnretainedValue().powerSourceMayHaveChanged()
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?
            .takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func powerSourceMayHaveChanged() {
        let now = Self.currentPowerSource()
        // 电量每变一点也会回调,只认供电方的切换。
        guard now != powerSource else { return }
        powerSource = now
        check(.dock, after: 10)
        check(.dock, after: 75)
    }

    private static func currentPowerSource() -> String? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        return IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
    }

    private func check(_ trigger: Trigger, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.check(trigger) }
    }

    @objc private func checkNow() {
        check(.manual)
    }

    private func check(_ trigger: Trigger) {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let count = Probe.sample()
            Probe.record(count, trigger)
            DispatchQueue.main.async { self.finish(count, trigger) }
            // 重启前卡住过的现场,把之后才写出来的报告补进去;没有待补的就什么都不读。
            Evidence.completePending()
        }
    }

    private func finish(_ count: Int?, _ trigger: Trigger) {
        checking = false
        lastCheck = Date()
        nextCheck = Date().addingTimeInterval(Probe.interval)
        let wasWedged = state == .wedged
        switch count {
        case nil: state = .unreadable
        case 0?: state = .normal
        case _?: state = .wedged
        }
        updateIcon()
        guard state == .wedged, let count else { return }
        // 刚卡上就存现场;卡着时又插拔了坞再存一份,拆不掉的样子也是现场。
        if !wasWedged || trigger == .dock { saveEvidence(trigger, count: count) }
        // 卡着就每次都提醒:这个状态下拔坞会出事,4 小时提醒一次不算吵。
        notify()
    }

    private func saveEvidence(_ trigger: Trigger, count: Int) {
        guard !savingEvidence else { return }
        savingEvidence = true
        DispatchQueue.global(qos: .utility).async {
            let folder = Evidence.capture(trigger, count: count)
            DispatchQueue.main.async {
                self.savingEvidence = false
                self.lastEvidence = folder
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if state == .wedged {
            let image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "雷雳显示驱动卡住了")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
            image?.isTemplate = false
            button.image = image
        } else {
            let image = NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "雷雳驱动监视")
            image?.isTemplate = true
            button.image = image
        }
        // 还没查完第一次、或读不到日志时图标变灰:判断不了,不装作正常。
        button.appearsDisabled = state == .notYet || state == .unreadable
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mark = Probe.isTest ? "【测试】" : ""
        let headline: String
        switch state {
        case .notYet: headline = "正在检查雷雳显示驱动…"
        case .normal: headline = "雷雳显示驱动正常"
        case .wedged: headline = "雷雳显示驱动卡住了"
        case .unreadable: headline = "读不到系统日志，判断不了"
        }
        menu.addItem(info(mark + headline))
        if state == .wedged {
            if savingEvidence {
                menu.addItem(info("正在自动存现场…"))
            } else if lastEvidence != nil {
                menu.addItem(info("现场已自动存好"))
            }
            menu.addItem(info("重启前先同时按 ⌃⌥⇧⌘ 和句号键，收完整诊断（要几分钟）"))
            menu.addItem(info("存好东西，接着坞重启；卡住时别拔坞"))
        }
        if let lastCheck { menu.addItem(info("上次检查 \(Self.time(lastCheck)) · 下次 \(Self.time(nextCheck))")) }
        menu.addItem(.separator())
        let now = NSMenuItem(title: checking ? "正在检查…" : "立即检查", action: checking ? nil : #selector(checkNow), keyEquivalent: "")
        now.target = self
        menu.addItem(now)
        let log = NSMenuItem(title: "打开检查记录", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
        let evidence = NSMenuItem(title: "打开现场文件夹", action: #selector(openEvidence), keyEquivalent: "")
        evidence.target = self
        menu.addItem(evidence)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private static func time(_ date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        return format.string(from: date)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Probe.logURL)
    }

    /// 刚存过现场就打开那一份,否则打开总文件夹。
    @objc private func openEvidence() {
        let folder = lastEvidence ?? Evidence.root
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func notify() {
        let title = (Probe.isTest ? "【测试】" : "") + "雷雳显示驱动卡住了"
        let body = "正在自动存现场。重启前先同时按 ⌃⌥⇧⌘ 和句号键收完整诊断（要几分钟），再接着坞重启。卡住时别拔坞：拔了屏幕拆不掉，插回约 60 秒就崩溃。"
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            case .denied:
                break  // 他在系统设置里关了通知就尊重它,菜单栏的红色图标照样在。
            default:
                // 还没授权成功(如第一次的询问没弹出来):退回系统自带的脚本通知,别让这一次悄悄过去。
                let script = "display notification \"\(body)\" with title \"\(title)\" sound name \"Basso\""
                _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", script])
            }
        }
    }
}

let app = NSApplication.shared
let delegate = WatchApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
