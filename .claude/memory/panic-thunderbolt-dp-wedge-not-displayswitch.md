---
name: panic-thunderbolt-dp-wedge-not-displayswitch
description: macOS 27 起约每周一次的雷雳显示驱动卡死(唤醒重连后带宽申请的握手卡在 Mac 自己这头、驱动无限等,拔坞后残影屏或崩溃;判断是 Mac 的问题、不是坞);能查到起点的几次本 app 都没动过屏。他曾认为是 app 没处理好,10-26 起停用 app 对照,第 2 天照样卡死并崩溃:app 不是必要条件。再遇先按这里的特征和查法判定
metadata:
  type: project
---

**是什么**(2026-10-22 关机卡住报告里带符号的内核栈,`spindump -i <报告> -o <txt>` 可读):
① 刷 `evaluating for > 1m` 的线程卡在
`AppleThunderboltDPConnectionManager::evaluateConnections → DPOutAdapterCM::doSynchronousEvaluation → sleepGate`;
② 它在等 `processBandwidthAllocationRequest → IOThunderboltController::configPollDWordWithMask`
——**同步轮询「DPTX 请求」位、等它清零**(9/29 日志 `processBandwidthAllocationRequest - ERROR: got an error polling DPTX Req! dptx_poll_status = 0xe00002d6`,即超时),超时后接着等、不放弃。
按 USB4 规范,这一位在**主机这头的 DP IN 适配器**里,由出图的一方(Mac 的显示引擎)在连接管理器确认分配后清掉——
卡住的握手两头都在 Mac 里,不在坞上(推断:依据是规范的寄存器布局,Linux `drivers/thunderbolt/tb_regs.h` 标明 `ADP_DP_CS_8` 只属 DP IN;
`usb4_dp_port_wait_and_clear_cm_ack` 等同一位,500 ms 不清就放弃)。10-27 之前我一直写成「坞那路不回应」,是把日志里的对象名 `DPO [0:0x1:0x13]` 当成了被等的一方;
③ 拔坞的拆除线程 `IOThunderboltConnectionManager::rescan → terminateInvalidClientsOnPort → DPOutAdapter::requestTerminate`
也卡在同一把门上 → 拆不掉旧坞(残影屏)、不处理新插入(插回不亮、坞上鼠标失灵),开盖唤醒约 60 秒后
`busy timeout[0], (60s) ... 'IOThunderboltPort'` 内核崩溃(watchdogd 触发)。只有重启能解。
卡住期间照常能用,要等某块屏需要重连、或拔坞要拆除时才出事。
现场设备树(2026-10-26,`ioreg -l -w0` 里的 `AppleThunderboltDPOutAdapterOS2`;坞是 USB4 v2、80 Gb/s,固件 64.64):
坞上三路 DP 输出,两路在用,都开着带宽分配模式(`DPI BWAM Support = Yes`)、同属 `Group ID = 1`;卡住那路
`Evaluation In Progress = Yes`、`Next HPD State = Yes` 待处理;**还亮着的那路也排着** `Need Evaluation = Yes`、
`Need To Process Connection Up Message = Yes`——它下次唤醒若也掉线重连,同样回不来(推断),合着盖时就全黑了。

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
- **10-26 停用 app 后第一次:10-27 13:53 崩溃**(同一崩溃文本,27.0.1)。app 全程没运行(它的进程日志 0 条,崩溃报告里也没有)。
  监视器 16:55 正常、20:56 起每次都报卡(每 3 秒 22–24 条);17:45、17:48 两次唤醒两块屏都掉线又回来了,17:54 屏幕睡下,
  之后到 20:56 没有任何唤醒或插拔——起点就在这段里,具体哪一刻查不到。10-27 13:51 唤醒后他 13:52 连着拔插坞三次,约一分钟后崩溃。
查得到接口的四次(09-22、09-29、10-22、10-24)都是 `DPO [0:0x1:0x13]`。
- **10-27 升级 27.2(26B123)后照样卡**:15:19 开机,15:22:32 第一次屏幕唤醒两块屏掉线又回来,适配器就卡上了(悄悄卡住型,
  两块屏都亮着;报错变成 `NPHPDS=0 ... HPDS=1 NHPDS=0`,只剩带宽申请挂着)。监视器 15:21 刚查过、4 小时后才会再查,
  是我手动点了「立即检查」才变红——4 小时的空档是真实存在的。15:34 卡着时坞被拔下又插回,15:36 崩溃(同一崩溃文本);
  之后 15:42、15:53 两次关机卡住报告里没有这组死等栈。
- **10-28 14:38:50 崩溃(27.2,同一崩溃文本,断电后第一次开机里)**:12:40 唤醒两块屏都掉线重连(一块晚 6 秒才回),13:16 唤醒只有一块掉线重连;
  14:01:37 拔坞,**系统一块屏都没拆**(健康时 5 秒内拆完)→ 最晚此刻已卡;14:37:48 他换了个口插回,62 秒后崩溃。
  起点在 11:07(监视器 0)到 14:01 之间,多半是 12:40 或 13:16 那次唤醒,也不能排除是拔坞那一下。监视器 11:06 查过、下次 15:07,又错过了。
  拔坞只留残影屏、不崩;**崩溃总在之后插回或唤醒约 60 秒**(10-14、10-27 两次、10-28 都是这样)。
**官方发布说明里的线索**(2026-10-27 读原文:`https://developer.apple.com/tutorials/data/documentation/macos-release-notes/<slug>.json`,
网页版是脚本渲染、抓不到正文):macOS 27.0 的 **Thunderbolt** 小节 Resolved Issues 有一条「两块相同的显示器(同型号、同序列号)
连上时,第一块正常、第二块可能不亮(176292156)」——正是他这套:两块同型号屏 EDID 里的数字序列号相同(见
[[same-model-displays-identity-is-edid-serial-text]])。27 在雷雳这一层专门改过这种配置的处理,而我们的问题恰好从 27 开始;
是否同一处只是推断。27.2 的 Known Issues 里外接屏相关的只有「显示设置可能恢复不对、排列可能变」(188643179),与卡死无关。
~~可做的差分:让坞上只走一块屏(另一块改插机身 HDMI)~~——10-28 他拒绝:「我为什么要改我的链接屏幕的方法?」,别再提,见 [[dont-ask-user-to-change-setup-for-platform-bugs]]。
**网上有没有同样的人(2026-10-27 搜过一轮,中英文:Apple 社区、开发者论坛、MacRumors、V2EX、GitHub)**:没找到同一特征
(唤醒后带宽申请卡住、`evaluating for > 1m`、拔坞后 `IOThunderboltPort` busy timeout)。MacRumors 抓取被拒(403),Reddit 搜不进来,
27 才出 6 周,没搜到不等于没有。最接近的是开发者论坛 814201:M5 / M4 Pro MacBook Pro 接两块相同的屏只亮一块,
Apple DTS 说根子是显示管线分配(高刷屏占两条管线、先认到的那块全拿走),27 做了改动「应该有改善」,27.0.1 仍有人复现——
症状和我们不同,但机型、同款双屏、27 改动的区域都对得上;已写进反馈草稿的「可能相关」。
**他确认(2026-10-26):升级前也是这个坞带两块屏,从没遇到过**——同一套硬件和用法,只有系统变了。
这台 Mac 的安装记录里没有坞的固件更新(10-27 查);坞是否在别的电脑上刷过固件没核实。

**是坞还是 Mac(10-27 他问,我的判断:Mac 的问题)**:① 前后对照只有系统变了;② 卡住的握手按规范两头都在 Mac 里(上面 ②,推断);
③ 无限等、拆除被挡、崩溃,全在 macOS 的驱动里(栈亲见)——外接设备再怎么不回,驱动也该超时放弃;④ 27 恰好改过这一块(下面的发布说明和论坛帖)。
坞唯一沾边的是:唤醒后屏掉线又重连(`hot plug 0 → 1`)要经过坞传上来,是诱因,但这是正常事件。
还没做的差分:换一个坞或另一台 Mac 接同一个坞——能把「只有这个坞才触发」排除掉,目前排除不了。

**坞断电对照:不成立(10-28 有了结果)**:断电后同一次开机里照样卡死并崩溃,先后好了 4–6 次唤醒重连,和 10-26 只重启 Mac 那次差不多。
「坞内部状态是诱因、断电能清」排除;判断回到「Mac 的问题」。原始记录如下。
10-27 15:41–15:56 他把坞和 Mac 都关了几分钟再接上(`pmset` 15:41:29 Batt → 15:56:35 AC)。
此前每次出事后的重启坞都带着电(10-26 11:57、10-27 13:54 / 15:20 / 15:36 开机那一刻都是 AC),这是第一次连坞一起断电。
到 10-28 11:13:唤醒 7 次,其中 4 次两块屏掉线重连,全部回来,驱动健康。但 10-26 只重启 Mac 后也连好了 6 次重连才卡;
按此前每次重连约 15–25% 出事粗算,4 次全好的机会有 35–50%,要连着 12–20 次全好(按他的作息约 4–6 天)才算数——结果没撑到。

**对照实验(10-26 起,10-27 有了结果:停用 app 照样卡死 → app 不是必要条件)**:他不认同是系统的问题——「几天内连续出问题,从概率上不对」,
认为是 app 没处理好(类比 Java 里线程没释放)。10-26 11:57 重启后他**完全不开 app**,计划 7–8 天(到 11-02 前后)看还卡不卡。
- 监视:菜单栏小 app「雷雳驱动监视」(`Sources/WedgeWatch`,`bash scripts/wedge-watch.sh install|uninstall|status|check`),
  装在 /Applications,登录时打开一次、他退出就一直退着;每 4 小时实时采 3 秒,卡住时图标变红三角并发通知。
  **10-28 起(他同意)**:另在屏幕唤醒后 1 分钟、插拔坞(供电方切换,IOPS 通知)后 10 秒各查一次,检查记录行尾标(启动 / 定时 / 唤醒后 / 插拔坞后 / 手动);
  卡住时自动存现场到 `~/Library/Logs/DisplaySwitch-wedge-evidence/wedge-<时间>/`(内核日志、DP 适配器设备树、24 小时唤醒与插拔、pmset),
  每次检查把新的 `.panic` / `.shutdownStall` 拷到 `reports/`、他按 ⌃⌥⇧⌘. 收的诊断拷到 `sysdiagnose/`。模拟卡住的测试实例验证过存现场、拷报告、菜单;
  **唤醒和插拔两条触发还没经真实事件验证**(不能为测它去睡屏或拔坞),下次先看检查记录里有没有「唤醒后」「插拔坞后」。
  他的要求:**要有图标、不要偷偷摸摸**,看图标变化就够,通不通知不重要;间隔 4 小时就够(先装的每 30 分钟纯后台脚本被他否了,嫌勤、嫌看不见)。
  它只用 `log` 命令、不链接 DisplaySwitch 的代码,不污染对照。每次结果记在 `~/Library/Logs/DisplaySwitch-wedge-watch.log`,
  收尾时按它看各时段的状态;实验结束问他留不留。
- `swift test` 里有真机单测(读真实设备树和显示器),实验期间也别跑;只 `swift build`。
- 实验期间**别跑任何 app 代码**(selfcheck、PanelSnapshots、候选版,以及调 CoreDisplay、读设备树的脚本),只用 `log stream` / `log show` 看日志,否则污染对照。
- 判读:停用期间卡一次 → app 不是必要条件。8 天不卡只算倾向:按升级后的平均频率,纯靠运气不卡的概率约 38%,按最近两周的频率约 16%;
  要更有把握就延长到两周,再开回 app 看会不会复现。
- 收尾时回查:WindowServer 日志里每次唤醒两块屏是否都回来(谓词见下)、`pmset -g log` 的唤醒次数与插拔、DiagnosticReports 里新的崩溃 / 关机卡住报告。
- 支持他假设的事实也要记着:10-22、10-24 两次都紧跟密集测试日(10-22、10-23 大量拔插、开关屏、换实例)。
  10-26 审过代码:申请的 IOKit 对象、通知端口、显示配置事务、子进程都有对应的释放或终止,没找到漏的——只说明没有明显泄漏。
- 10-26 重启时的关机卡住报告里仍是同一组死等栈(`evaluateConnections` / `doSynchronousEvaluation` / `processBandwidthAllocationRequest` / `configPollDWordWithMask`)。

**怎么查**(2026-10-26 实测):
- 现场判定用 `log stream` 采几秒:卡死时每秒 10 条 `evaluating for > 1m ... NPBWAR=1`,健康时 0 条。
  写 `/usr/bin/log stream --timeout 3s --predicate '...' --style compact`(zsh 里要写 `/usr/bin/log`)。
  别用 perl alarm 之类从外面用信号掐断:没写出的输出会丢,量少时整段丢光(10-26 阳性测试数成 0)。表头行带着谓词原文,数正文里的 `DPO [`。
- **内核日志查不到历史**:10-26 查这次与上次开机的内核日志一条都没有(含卡死前),WindowServer 的却留到两周前,原因不明;
  `log show` 只看得到内存里最近约 1 分钟,卡死刷屏时那里只剩几条。面板的卡死检查(`DriverLog`,`log show --last 2m`)靠的正是这几条,
  目前报得出,余量很小。所以「`log show` 查了 N 小时 0 条」只说明「此刻没卡」(卡死是持续刷),不说明这 N 小时里没卡过。
- 找起点看 WindowServer:`Display N hot plug 0` 之后没有 `Inserting hotplug event for state "out"`,此后各次唤醒再没有这块屏。
  **`Display N hot plug` 这类(coreanimation)比 SkyLight 的记录清得早**:10-28 查时 10-23 及以前的已一条不剩,拿它数会把掉线数成 0。
  数「唤醒时掉线重连」用 SkyLight 的 `for state "out"` / `Processing hotplug "out"`,看 `Broadcast: Did Wake` 前后 10 秒;
  掉线可能先于 `Did Wake` 记下。插拔坞引起的唤醒也带 out,要对照 `pmset` 的 AC / Batt 切换剔掉。
  谓词 `process == "WindowServer" AND (eventMessage CONTAINS "hot plug" OR eventMessage CONTAINS "Inserting hotplug" OR eventMessage CONTAINS "Broadcast: Did Wake")`。
- 本 app 有没有动过屏:它进程日志里 SkyLight 的 `SLSCompleteDisplayConfigurationWithOption`(每次开关屏必留,启动兜底也留);
  它在唤醒时何时收到通知:同一进程里的 `CGSDisplayNotifyProc`。
- 他有没有插拔坞:`pmset -g log` 里 `Using AC` / `Using Batt` 的切换(坞同时供电)。
- 崩溃快照取证:日志 `kernel[0:<十六进制 tid>]` 对应快照的十进制 tid;快照 `lastRunTime` 是「距快照多少秒」;
  `kmutil inspect -V release --show-kext-uuids` 把快照里的 UUID 映射到驱动名(UUID 在最后一列、带括号)。
  `spindump -i` 读不了 `panic-full-*.panic`(exit 65),要自己解析:文件是两段 JSON(第二段用 `raw_decode`),
  `binaryImages[i][0]` 是 UUID,`processByPid → threadById → kernelFrames` 是 `[镜像序号, 偏移]`,没有函数名。
  卡死崩溃的指纹(10-27 15:36、10-28 两份都是):kernel_task 里 3 条线程落在 AppleThunderboltDPOutAdapter / DPAdapterFamily / IOThunderboltFamily、
  全是 TH_WAIT;带 DPAdapterFamily 的那条一直在跑(累计 CPU 随卡的时长涨),另有一条 `lastRunTime` 正对着拔坞那一秒(10-28 是 2232.6 秒 = 14:01:37)。
- 数 `evaluating for > 1m` 时限定 `process == "kernel"`(或加 `AND process != "log"`):`log` 命令自己的启动记录带着查询参数,会命中同一串字。

**未解的线索**:10-24 前三次唤醒,屏亮起约 2.5 秒后都掉线再重连了一次(WindowServer 的 `hot plug 0 → 1`),
10-12 到 10-23 的 62 次唤醒里一条 `hot plug` 都没有(10-28 更正:这是用会被提前清掉的 coreanimation 记录数的,不可靠;
改用 SkyLight 记录重数,10-14 / 21 / 22 尚存的 20 次唤醒里 2 次有掉线、可能是拔坞,10-23 起几乎每次唤醒都掉线——「掉线变多」大体还成立)。重连正要重新申请带宽,等于多一次中招机会。
时间上紧接 10-23 的换线测试(一块屏改插机身 HDMI 再插回、坞换口)和装 1.0.18–1.0.21;10-24 致命那次掉线发生在本 app
收到任何通知之前,所以不是它唤醒时的动作引起的。待查:显示器的输入源是否在换插时被改成了自动选择。

**Why:** 崩溃时本 app 总在运行、又直接操作显示器,最容易被当成嫌疑人;而归因很容易被带偏——
另一个 agent 把自己的查询窗口(崩溃前 10 分钟)当成了异常起点,还把「插回坞」读成了「断开」。要往前查到异常第一次出现为止。
2026-10-26 他问「这么容易卡死吗……我以前插拔应该很容易发现」:频率确实高(升级后 41 天至少 5 次),
而触发点是唤醒时的重连、不是插拔,插拔只是让它暴露出来。

**How to apply:** 遇到残影屏、某块屏醒不过来或内核崩溃,先 `log stream` 采几秒定性,再按上面的查法找起点和本 app 的动作,
别只拿 `log show` 回看下结论。卡住时**别拔坞**,也别等下一次屏幕睡眠:存好东西,接着坞尽快重启。
**已报给 Apple:FB25346775**(10-28,区域 USB/雷雳;我填表、他自己点的提交;描述框会吞换行,所以只放摘要,全文做成 txt 附上)。下次变红、重启前:反馈助理里打开 FB25346775 → 添加附件 → 设备诊断信息,补一份卡住现场的诊断,再重启。拔坞后 `scripts/selfcheck.sh` 的「物理外接屏数 ≥ 活跃外接屏数」
(及真机单测 physicalCountCoversActiveExternals)兼作探测器:报红时先别插回坞,先重启。参见 [[displayswitch-real-usage-dock-workflow]]。

**卡死时本 app 的一个实际用途(他本人 10-22 的做法)**:拔坞后两块屏成了「残影」(系统仍当它们在线,
窗口困在上面拖不回来),他用 DisplaySwitch 把这两块关掉,窗口才回到内建屏。改断开 / 救援逻辑时别破坏这条路。
**差分对照(10-22 16:41,重启后驱动健康,同样开盖当场拔坞)**:拔后 5 秒系统已正常拆掉两块外接屏(物理 0、活跃 0),
无残影;插回 1 秒内两块都回来。→ 残影屏是驱动卡死的后果,不是拔法。另:插回时活跃屏数会比物理计数早约 1 秒恢复,
「物理 ≥ 活跃」检查别在插线后头几秒里判。
