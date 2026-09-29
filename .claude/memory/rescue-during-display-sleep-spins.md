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

**How to apply:** 改救援时机、重试策略或主线程模型时把它算进去。设计文档 §7.3 的真机验收
没有覆盖「显示器睡眠中拔坞」,它的前提「拔线瞬间 WindowServer 尚未冻结」在这种情形下不成立。
