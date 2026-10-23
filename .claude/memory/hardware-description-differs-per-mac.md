---
name: hardware-description-differs-per-mac
description: 同一 macOS 版本下,不同芯片 / 机型的设备树(IOKit 里的硬件描述)形态不同;读这类数据的功能要在 MacBook 与 Mac mini 两种形态上都核对,且验证布置要能区分对错
metadata:
  type: project
---

他有两台机器跑 DisplaySwitch:MacBook(`AppleT605xIO`,有内建屏,外接屏走 `dispext0~7`,HDMI 在 `atc3`)与
Mac mini M4(2026-10-23 起,`t8132`,无内建屏,机身 HDMI 由主协处理器 `dcp` 经 `disp0`、`dptx-phy` 输出)。
两台 macOS 版本相同,**设备树不同**:设备树是每种芯片 / 机型的固件给出的硬件描述,macOS 照着它驱动硬件——
系统版本统一的是驱动代码,不是这份描述。本 app 直接读这份描述,所以机型一换,数据形态就可能变。

**Why:** 2026-10-23 的「接在 Mac 哪个口」只在 MacBook 上写、上验,把那台机器上的巧合当成了规则:
交换器 `ufp-endpoints` 名单序号当上游口编号、外接屏只认 `dispextN`(测试里还断言 `disp0` 读不出)、domain / port 字段当必有。
验证时两块屏都插在 1 号雷雳口,换口也是一起换,任何把屏对错的实现都读出同样的字——「同型号也不会对错」从没被验证过,
却写进了注释、提交、README 和设计文档。到 Mac mini 上整条链一步都没认上,而「读不到就不写」让它静默失败,只剩说明行少一个词。

**How to apply:**
1. 读设备树 / IOKit 内部数据,一台机器 = 一个样本。找**声明这个值的节点**和内核对缺省的规矩(如 `dp-switch-*` 没写按 0),
   别靠位置、命名或「这台机器上恰好有」。
2. 对应关系类功能(哪块屏 ↔ 哪个口 / 哪个控制器)用能区分对错的布置验证:两块屏插**不同**的口;只插同一个口的结果不作数。
3. 两种机型各留一份原样夹具进测试,都在 `MacPortTests.swift`(MacBook 的上游口 2026-10-23 已补抄:`dcpext0~3` 声明 0~3 号口,
   与名单前 4 项碰巧对齐;5、6 号口是只走 AUX 的口,名单却写 dispext5、6)。
   MacBook 机身 HDMI 已真机验(2026-10-23,一块屏):路由 `0:ufp0,0-dfp3,0`,1.0.18(他看)与 1.0.19(我截图)都写「HDMI」。
   两块屏分插不同口已证实(2026-10-23,MacBook:一块直插 1 号口、一块经 3 号口上的坞,写「雷雳 1」「雷雳 3」,他目视也正常)。
   **屏幕编号 ↔ 控制器的因果验法**:用 `.forAppOnly` 把一块屏换成同尺寸的 30Hz 模式,看哪个 `dispextN` 的
   `DPTimingModeId` / `M3TimingParameters` 变,再换回(进程退出也自动恢复)。坑:`.forAppOnly` 关屏不改任何 IOKit 字段,不能当因;
   命令行探针等待时要跑 RunLoop,`Thread.sleep` 会让配置根本不生效;别对走雷雳隧道的屏改模式(带宽重分配正是卡死那类操作)。
4. 拔线通知等安全相关机制同理:Mac mini 机身 HDMI 走 `dptx-phy` + DP 转 HDMI 芯片,与 MacBook 的 HDMI 硬件路径不同,
   要在 Mac mini 上单独验。2026-10-23 已验(一块屏、三轮拔插、等 10 / 2 / 3 秒):每次拔出都来「节点重新登记」通知,
   到达时物理外接屏数已是 0;睡眠判断一直是 false(CoreGraphics 拔线期间仍报那块屏在线,是陈旧值,方向安全);
   插回后口重新读出 HDMI。**两块屏、关一块再拔另一块的完整救援仍未在 Mac mini 上跑过。**

参见 [[displayswitch-real-usage-dock-workflow]]、[[release-needs-real-machine-acceptance]]、[[probabilistic-bugs-need-many-varied-trials]]。
