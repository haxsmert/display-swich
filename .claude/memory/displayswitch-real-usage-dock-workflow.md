---
name: displayswitch-real-usage-dock-workflow
description: DisplaySwitch 的真实动线是「接拓展坞办公、关内建屏、拔坞走人」,拔插相关场景是日常而非边缘情况
metadata:
  type: project
---

他用 DisplaySwitch 的真实动线:**接拓展坞 → 关掉内建屏用外接屏办公 → 拔坞走人 → 回来再插上**。
拓展坞上挂两块同型号 4K 外接屏。

**Why:** 设计文档 §7.2 曾把「关掉内建屏后拔走外接屏 → 全黑」判为**边缘场景**,
据此接受「需强制重启」的代价、不做守护。2026-09-07 这个场景真实发生了——
它根本不是边缘,而是他每天都走的路。判断一个显示器场景值不值得做,
要按这条动线衡量,别按「理论上罕见」衡量。

**How to apply:** 评估拔插、坞、多屏相关需求的优先级时,默认它会被高频触发。
同理,这类功能的验收必须在**真机 + 真动线**上做,Mock 和单测都不够。
参见 [[design-doc-non-goals-are-deliberate]]。
