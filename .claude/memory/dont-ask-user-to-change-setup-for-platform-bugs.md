---
name: dont-ask-user-to-change-setup-for-platform-bugs
description: 系统缺陷别让他改自己的接法 / 用法去做对照;他要的是报给厂商、照常用,诊断只走被动取证
metadata:
  type: feedback
---

确认是平台 / 系统的缺陷后,**别建议他改自己的真实接法或用法来做对照或绕开**(如「一块屏改插机身 HDMI」)。
诊断只用不打扰他的手段:读日志、崩溃快照、设备树,或我自己能做的检查。

**Why:** 2026-10-28 雷雳显示驱动卡死([[panic-thunderbolt-dp-wedge-not-displayswitch]])已判断是 macOS 的问题,
我连着几次建议他把一块屏改插 HDMI 做对照,他回:「我为什么要改我的链接屏幕的方法?我不去做这个对照,毫无意义,你帮我反馈给苹果公司吧」。
他的接法就是需求本身(见 [[displayswitch-real-usage-dock-workflow]]),该修的是厂商。

**How to apply:** 归因到平台后,下一步默认是「替他把反馈报上去 + 减轻出事的代价(如监视器早提醒)」,
不是给他布置实验。真需要他动手的差分,先说清它能改变什么决定;改变不了就别提。
