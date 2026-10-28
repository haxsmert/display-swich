---
name: preserve-live-fault-evidence
description: 故障现场能安全保持时先留证再重启;系统报告一周内会被清、scratchpad 重启即空,证据当场拷到 ~/Library/Logs/DisplaySwitch-wedge-evidence
metadata:
  type: feedback
---

遇到能安全保持的故障现场(如雷雳驱动卡住、但屏还亮、没人动线),**先收完整诊断,再建议重启**:
- 系统自带组合键 Control-Option-Command-Shift-Period 收 sysdiagnose(`man sysdiagnose` 有写;不要密码,几分钟,存 `/private/var/tmp`);
  或在反馈助理里打开对应反馈 →「添加附件 → 设备诊断信息」。
- 相关的 `/Library/Logs/DiagnosticReports` 文件(`.panic`、`.shutdownStall`)当场拷到 `~/Library/Logs/DisplaySwitch-wedge-evidence/`。

**Why:** 2026-10-28 他问:「你以前为什么不把卡住的诊断信息保留下来,还要我等待下次?」
卡住的现场我碰到过两次(10-26 发现时;10-27 15:31 我亲手查出变红),两次都只顾着建议重启。
10-22、10-26 仅有的两份带函数名的关机卡住报告,和 10-27 13:54 的崩溃文件,一周内被系统清掉了;
10-26 的设备树快照存在 scratchpad,重启就丢了。最后报给 Apple(FB25346775)时,只剩我抄下来的几行。

**How to apply:** 「先恢复再汇报」([[restore-visibility-before-reporting]])管的是他看不见屏的情形;
屏还亮、只要不动线就安全时,先留证再恢复。证据别只放 scratchpad,也别只抄进文字。
参见 [[panic-thunderbolt-dp-wedge-not-displayswitch]]。
