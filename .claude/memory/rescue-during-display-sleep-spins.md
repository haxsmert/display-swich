---
name: rescue-during-display-sleep-spins
description: 全黑救援若赶上 WindowServer 有未完成的重配置(如显示器睡眠中拔坞),点亮调用会在主线程忙等约 10 秒、刷出数十万行日志并返回失败
metadata:
  type: project
---

救援的点亮调用(`CGCompleteDisplayConfiguration`)若赶上 WindowServer 有未完成的重配置——
例如**显示器睡眠中拔坞**,屏幕的拔出事件会被延后到唤醒才处理——SkyLight 会在本 app 主线程上
忙等约 10 秒,每轮打一条 `Waiting for previous reconfig to complete`,最后返回失败。

**Why:** 2026-09-22 实测:显示器已睡眠约 18 分钟时拔坞,两次救援各卡约 10 秒,一分钟内刷出约 62 万行日志,
进程被系统以「日志量过大」隔离(之后的日志可能被丢弃,恰好伤到救援这条路径的诊断);期间主线程被占满。
与当天的内核崩溃是否有关未能证实(见 [[panic-thunderbolt-dp-wedge-not-displayswitch]])。

**已修(2026-09-29,v1.0.15):** 屏幕睡眠时不下指令,日志记「等唤醒」,交给「开盖 / 唤醒」触发源;
判定用 `CGDisplayIsAsleep`,在线屏全部报睡眠才算(误判成睡眠会把救援推迟到一次不会来的唤醒)。
真机实测过「睡眠时判为睡、唤醒触发那一刻已判为醒」;**接坞 · 睡眠中拔坞的完整动线尚待验收,验收前不发版**。

**How to apply:** 改救援时机、重试策略或唤醒触发源时,守住两件事:唤醒触发那一刻判定必须已是「醒」
(换判据就得重测这个时序),以及 `scripts/selfcheck.sh` 里「醒着不判为睡眠」那条必须绿。
