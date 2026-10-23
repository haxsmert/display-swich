---
name: panic-thunderbolt-dp-wedge-not-displayswitch
description: 2026-09-22 与 09-29 两次内核崩溃(IOThunderboltPort busy timeout)是 macOS 27.0 雷雳显示输出适配器卡死,09-29 已排除本 app、09-22 未能完全排除;再遇崩溃先按这里的特征和核查法判定
metadata:
  type: project
---

2026-09-22、09-29 两次内核崩溃(`busy timeout[0], (60s) ... 'IOThunderboltPort'`,由 watchdogd 触发)
是**同一个系统层卡死**:macOS 27.0(26A428)的 `AppleThunderboltDPOutAdapter` 处理一次 DP 带宽分配请求时
轮询超时(`processBandwidthAllocationRequest ... dptx_poll_status = 0xe00002d6`)、无限重试;
之后拔坞的拆除线程在该适配器里永久阻塞,**开盖唤醒约 60 秒后**崩溃(两次都是)。
两次崩溃快照里三个适配器线程的内核栈**逐帧相同**。

- **09-29:已排除本 app。** 卡死始于前一天合盖接坞时的一次显示器唤醒:HDCP 协商超时 → 链路完整性失败 →
  链路重训 → 该路带宽先释放、132 ms 后重新申请,申请再没完成;带病运行约 21 小时,拔坞、再开盖插坞时引爆。
  其间本 app 零次配置事务(阳性对照:同一日志通道在 09-22 记下了它的配置事务)。
- **09-22:未能完全排除。** 拔坞瞬间救援正在下点亮指令(两次各忙等约 10 秒、返回失败,推断未生效,
  见 [[rescue-during-display-sleep-spins]]);那天内核日志已轮换,无法确认卡死先于还是晚于这两次调用。

**Why:** 崩溃时本 app 总在运行、又直接操作显示器,最容易被当成嫌疑人;而归因很容易被带偏——
另一个 agent 把自己的查询窗口(崩溃前 10 分钟)当成了异常起点,还把「插回坞」读成了「断开」。
真起点在 21 小时前,要往前查到异常第一次出现为止。

**How to apply:** 再遇内核崩溃,先对特征:崩溃文本含 `IOThunderboltPort` busy timeout,
且统一日志里 `AppleThunderboltDPOutAdapter` 持续刷 `evaluating for > 1m ... NPBWAR=1`。
核查本 app 有没有动过屏:在它进程的日志里搜 SkyLight 的 `SLSCompleteDisplayConfigurationWithOption`
(每次开关屏必留)。取证方法:日志 `kernel[0:<十六进制 tid>]` 对应崩溃快照的十进制 tid;
快照 `lastRunTime` 是「距快照多少秒」;`kmutil inspect -V release --show-kext-uuids` 把快照里的 UUID
映射到驱动名;zsh 里要写 `/usr/bin/log`(`log` 是 zsh 内置命令)。
数 `evaluating for > 1m` 时谓词要加 `AND process != "log"`:`log` 命令自己的启动记录带着查询参数,会命中同一串字
(2026-10-23 拔插前自查,10 分钟「3 条」全是这种,排除后 2 小时内 0 条)。参见 [[displayswitch-real-usage-dock-workflow]]。

**2026-10-22 第三次撞见同一卡死(未崩溃,及时发现)**:拔坞后 `scripts/selfcheck.sh` 的「物理外接屏数 ≥ 活跃外接屏数」
一项报 ❌(物理 0、活跃外接 2),WindowServer 始终没处理这次拔出;适配器 10 分钟刷 5946 条 `evaluating for > 1m`,
卡死至少 12 小时前就已开始(近 12 小时日志里找不到它的起始记录),当天 40 分钟内没有任何程序对显示器做过配置调用。
**这项自检(以及真机单测 physicalCountCoversActiveExternals)兼作卡死探测器**:它报红时先别插回坞,先重启。
**卡死时本 app 的一个实际用途(他本人 10-22 的做法)**:拔坞后两块屏成了「残影」(系统仍当它们在线,
窗口困在上面拖不回来),他用 DisplaySwitch 把这两块关掉,窗口才回到内建屏。改断开 / 救援逻辑时别破坏这条路。
**卡死的确切位置(2026-10-22 重启时的 shutdown_stall 报告,带符号的内核栈,`spindump -i <报告> -o <txt>` 可读)**:
① 线程 `0x9a60a`(就是日志里刷 `evaluating for > 1m` 的那个)卡在
`AppleThunderboltDPConnectionManager::evaluateConnections → DPOutAdapterCM::doSynchronousEvaluation → sleepGate`;
② 它在等线程 `0x9a60e`:`processBandwidthAllocationRequest → IOThunderboltController::configPollDWordWithMask`
——**同步轮询拓展坞那路 DP 适配器的寄存器,等一个永远不翻转的状态位**(9/29 日志里的 `polling DPTX Req ... 0xe00002d6`);
③ 拔坞的拆除线程 `IOThunderboltConnectionManager::rescan → terminateInvalidClientsOnPort → DPOutAdapter::requestTerminate`
也卡在同一把门上 → 拆不掉旧坞(残影屏)、也不处理新插入(插回不亮、坞上鼠标失灵)。
即:拓展坞那路(三次都是 `DPO [0:0x1:0x13]`)不回应带宽分配请求,macOS 27.0 的驱动没有超时放弃,把整个雷雳配置线程拖住。
重启时本 app 并未运行(不在关机报告的进程里)。
**差分对照(10-22 16:41,重启后驱动健康,同样开盖当场拔坞)**:拔后 5 秒系统已正常拆掉两块外接屏(物理 0、活跃 0),
无残影;插回 1 秒内两块都回来。→ 残影屏是驱动卡死的后果,不是拔法。另:插回时活跃屏数会比物理计数早约 1 秒恢复,
「物理 ≥ 活跃」检查别在插线后头几秒里判。
