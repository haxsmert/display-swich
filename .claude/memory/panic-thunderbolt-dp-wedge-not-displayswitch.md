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
映射到驱动名;zsh 里要写 `/usr/bin/log`(`log` 是 zsh 内置命令)。参见 [[displayswitch-real-usage-dock-workflow]]。

**2026-10-22 第三次撞见同一卡死(未崩溃,及时发现)**:拔坞后 `scripts/selfcheck.sh` 的「物理外接屏数 ≥ 活跃外接屏数」
一项报 ❌(物理 0、活跃外接 2),WindowServer 始终没处理这次拔出;适配器 10 分钟刷 5946 条 `evaluating for > 1m`,
卡死至少 12 小时前就已开始(近 12 小时日志里找不到它的起始记录),当天 40 分钟内没有任何程序对显示器做过配置调用。
**这项自检(以及真机单测 physicalCountCoversActiveExternals)兼作卡死探测器**:它报红时先别插回坞,先重启。
**卡死时本 app 的一个实际用途(他本人 10-22 的做法)**:拔坞后两块屏成了「残影」(系统仍当它们在线,
窗口困在上面拖不回来),他用 DisplaySwitch 把这两块关掉,窗口才回到内建屏。改断开 / 救援逻辑时别破坏这条路。
