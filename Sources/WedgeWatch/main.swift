import AppKit
import UserNotifications

// 雷雳显示驱动卡死的菜单栏监视器(安装与背景见 scripts/wedge-watch.sh)。
//
// 与 DisplaySwitch 完全分开:不链接它的任何代码,只用 `log` 命令读系统日志,不碰显示器、不读设备树——
// 2026-10-26 起他停用 DisplaySwitch 做对照实验,监视器不能成为新的变量。
// 图标常驻菜单栏(他:「要放个图标让我知道,不要偷偷摸摸」),每 4 小时查一次(他定的),也能手动查。

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        // 用 log 自带的 --timeout 正常退出:从外面用信号掐断会丢掉还没写出的输出(2026-10-26 实测漏数)。
        process.arguments = ["stream", "--timeout", "3s", "--predicate", predicate, "--style", "compact"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        // 表头那行带着谓词原文,所以数报错正文里才有的 `DPO [`。
        return String(decoding: data, as: UTF8.self).split(separator: "\n").filter { $0.contains("DPO [") }.count
    }

    /// 每次结果记一行,对照实验收尾时按它看每段时间的状态。只留最近一段:每天 6 行,2000 行够一年。
    static func record(_ count: Int?) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let text = count.map { "卡死特征 \($0) 条 / 3 秒" } ?? "读不到系统日志"
        let line = "[\(stamp.string(from: Date()))] \(isTest ? "【测试】" : "")\(text)\n"
        var lines = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count >= 3000 { lines = lines.suffix(2000) }
        let kept = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? (kept + line).write(to: logURL, atomically: true, encoding: .utf8)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        // 按墙上时间判断到点:Timer 按开机时长计,机器睡着时不走,直接排 4 小时会被睡眠拖后。
        tick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, Date() >= self.nextCheck else { return }
            self.check()
        }
        tick?.tolerance = 30
        check()
    }

    @objc private func check() {
        guard !checking else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async {
            let count = Probe.sample()
            Probe.record(count)
            DispatchQueue.main.async { self.finish(count) }
        }
    }

    private func finish(_ count: Int?) {
        checking = false
        lastCheck = Date()
        nextCheck = Date().addingTimeInterval(Probe.interval)
        switch count {
        case nil: state = .unreadable
        case 0?: state = .normal
        case _?: state = .wedged
        }
        updateIcon()
        // 卡着就每次都提醒:这个状态下拔坞会出事,4 小时提醒一次不算吵。
        if state == .wedged { notify() }
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
        if state == .wedged { menu.addItem(info("存好东西，接着坞重启；卡住时别拔坞")) }
        if let lastCheck { menu.addItem(info("上次检查 \(Self.time(lastCheck)) · 下次 \(Self.time(nextCheck))")) }
        menu.addItem(.separator())
        let now = NSMenuItem(title: checking ? "正在检查…" : "立即检查", action: checking ? nil : #selector(check), keyEquivalent: "")
        now.target = self
        menu.addItem(now)
        let log = NSMenuItem(title: "打开检查记录", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)
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

    private func notify() {
        let title = (Probe.isTest ? "【测试】" : "") + "雷雳显示驱动卡住了"
        let body = "存好东西，接着坞重启。卡住时拔坞会出残影屏，或开盖后内核崩溃。"
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
