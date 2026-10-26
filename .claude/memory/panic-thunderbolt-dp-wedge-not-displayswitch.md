---
name: panic-thunderbolt-dp-wedge-not-displayswitch
description: macOS 27 起约每周一次的雷雳显示驱动卡死(拓展坞那路 DP 输出不回带宽申请、驱动无限等,拔坞后残影屏或开盖崩溃);能查到起点的几次本 app 都没动过屏。再遇先按这里的特征和查法判定
metadata:
  type: project
---

**是什么**(2026-10-22 关机卡住报告里带符号的内核栈,`spindump -i <报告> -o <txt>` 可读):
① 刷 `evaluating for > 1m` 的线程卡在
`AppleThunderboltDPConnectionManager::evaluateConnections → DPOutAdapterCM::doSynchronousEvaluation → sleepGate`;
② 它在等 `processBandwidthAllocationRequest → IOThunderboltController::configPollDWordWithMask`
——**同步轮询拓展坞那路 DP 适配器的寄存器,等一个永远不翻转的状态位**(9/29 日志里的 `polling DPTX Req ... 0xe00002d6`),不设超时;
③ 拔坞的拆除线程 `IOThunderboltConnectionManager::rescan → terminateInvalidClientsOnPort → DPOutAdapter::requestTerminate`
也卡在同一把门上 → 拆不掉旧坞(残影屏)、不处理新插入(插回不亮、坞上鼠标失灵),开盖唤醒约 60 秒后
`busy timeout[0], (60s) ... 'IOThunderboltPort'` 内核崩溃(watchdogd 触发)。只有重启能解。
卡住期间照常能用,要等某块屏需要重连、或拔坞要拆除时才出事。

**记录在案**(升级 macOS 27 是 2026-09-15,27.0.1 是 09-29):
- 09-22 崩溃,起点不明。**本 app 未能完全排除**:拔坞瞬间救援正在下点亮指令(两次各忙等约 10 秒、返回失败,推断未生效,
  见 [[rescue-during-display-sleep-spins]])。
- 09-28 起卡、09-29 崩溃。**已排除本 app**:始于合盖接坞时一次显示器唤醒(HDCP 协商超时 → 链路重训 →
  该路带宽释放后 132 ms 重新申请,再没完成),带病约 21 小时,拔坞、再开盖插坞时引爆;其间本 app 零次配置事务。
- 10-14 17:02 崩溃(同一崩溃文本,27.0.1):15:41 唤醒时两块屏都正常回来,16:35 拔坞,17:00 开盖唤醒,99 秒后崩溃。
  起点和本 app 的动作都查不到。原崩溃报告已被系统清走,摘要在 `/Library/Logs/DiagnosticReports/.contents.panic`。
- 10-22 拔坞后残影屏(未崩溃,重启)。适配器 10 分钟刷 5946 条,当时判断卡死至少 12 小时前就已开始;当天 16:03 拔坞前没有任何开关屏。
- 10-24 15:14 起卡,10-26 才发现。**已排除本 app**:屏幕唤醒时,坞上那块屏通电 2.6 秒后掉线,重连再没被处理,
  此后每次唤醒都只回来另一块。本 app 自 10-23 16:34 启动后、卡死前约 23 小时零配置调用,当时没关着任何屏(没关屏时拔线回调直接返回、不查系统),
  这次唤醒它第一次收到通知在掉线 3 秒后;期间没插拔(`pmset -g log` 无充电切换)。
查得到接口的四次(09-22、09-29、10-22、10-24)都是 `DPO [0:0x1:0x13]`。他说以前插拔从没遇到过。

**怎么查**(2026-10-26 实测):
- 现场判定用 `log stream` 采几秒:卡死时每秒 10 条 `evaluating for > 1m ... NPBWAR=1`,健康时 0 条。
  macOS 没有 `timeout`,写 `perl -e 'alarm 20; exec @ARGV' /usr/bin/log stream --predicate '...' --style compact`;zsh 里要写 `/usr/bin/log`。
- **内核日志查不到历史**:10-26 查这次与上次开机的内核日志一条都没有(含卡死前),WindowServer 的却留到两周前,原因不明;
  `log show` 只看得到内存里最近约 1 分钟,卡死刷屏时那里只剩几条。面板的卡死检查(`DriverLog`,`log show --last 2m`)靠的正是这几条,
  目前报得出,余量很小。所以「`log show` 查了 N 小时 0 条」只说明「此刻没卡」(卡死是持续刷),不说明这 N 小时里没卡过。
- 找起点看 WindowServer:`Display N hot plug 0` 之后没有 `Inserting hotplug event for state "out"`,此后各次唤醒再没有这块屏。
  谓词 `process == "WindowServer" AND (eventMessage CONTAINS "hot plug" OR eventMessage CONTAINS "Inserting hotplug" OR eventMessage CONTAINS "Broadcast: Did Wake")`。
- 本 app 有没有动过屏:它进程日志里 SkyLight 的 `SLSCompleteDisplayConfigurationWithOption`(每次开关屏必留,启动兜底也留);
  它在唤醒时何时收到通知:同一进程里的 `CGSDisplayNotifyProc`。
- 他有没有插拔坞:`pmset -g log` 里 `Using AC` / `Using Batt` 的切换(坞同时供电)。
- 崩溃快照取证:日志 `kernel[0:<十六进制 tid>]` 对应快照的十进制 tid;快照 `lastRunTime` 是「距快照多少秒」;
  `kmutil inspect -V release --show-kext-uuids` 把快照里的 UUID 映射到驱动名。
- 数 `evaluating for > 1m` 时限定 `process == "kernel"`(或加 `AND process != "log"`):`log` 命令自己的启动记录带着查询参数,会命中同一串字。

**未解的线索**:10-24 前三次唤醒,屏亮起约 2.5 秒后都掉线再重连了一次(WindowServer 的 `hot plug 0 → 1`),
10-12 到 10-23 的 62 次唤醒里一条 `hot plug` 都没有。重连正要重新申请带宽,等于多一次中招机会。
时间上紧接 10-23 的换线测试(一块屏改插机身 HDMI 再插回、坞换口)和装 1.0.18–1.0.21;10-24 致命那次掉线发生在本 app
收到任何通知之前,所以不是它唤醒时的动作引起的。待查:显示器的输入源是否在换插时被改成了自动选择。

**Why:** 崩溃时本 app 总在运行、又直接操作显示器,最容易被当成嫌疑人;而归因很容易被带偏——
另一个 agent 把自己的查询窗口(崩溃前 10 分钟)当成了异常起点,还把「插回坞」读成了「断开」。要往前查到异常第一次出现为止。
2026-10-26 他问「这么容易卡死吗……我以前插拔应该很容易发现」:频率确实高(升级后 41 天至少 5 次),
而触发点是唤醒时的重连、不是插拔,插拔只是让它暴露出来。

**How to apply:** 遇到残影屏、某块屏醒不过来或内核崩溃,先 `log stream` 采几秒定性,再按上面的查法找起点和本 app 的动作,
别只拿 `log show` 回看下结论。卡住时**别拔坞**:存好东西,接着坞重启。拔坞后 `scripts/selfcheck.sh` 的「物理外接屏数 ≥ 活跃外接屏数」
(及真机单测 physicalCountCoversActiveExternals)兼作探测器:报红时先别插回坞,先重启。参见 [[displayswitch-real-usage-dock-workflow]]。

**卡死时本 app 的一个实际用途(他本人 10-22 的做法)**:拔坞后两块屏成了「残影」(系统仍当它们在线,
窗口困在上面拖不回来),他用 DisplaySwitch 把这两块关掉,窗口才回到内建屏。改断开 / 救援逻辑时别破坏这条路。
**差分对照(10-22 16:41,重启后驱动健康,同样开盖当场拔坞)**:拔后 5 秒系统已正常拆掉两块外接屏(物理 0、活跃 0),
无残影;插回 1 秒内两块都回来。→ 残影屏是驱动卡死的后果,不是拔法。另:插回时活跃屏数会比物理计数早约 1 秒恢复,
「物理 ≥ 活跃」检查别在插线后头几秒里判。
