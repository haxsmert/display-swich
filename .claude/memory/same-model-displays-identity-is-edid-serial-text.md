---
name: same-model-displays-identity-is-edid-serial-text
description: 同型号屏分清是哪一台要用 EDID 的序列号文本;系统的数字序列号可以两台相同,UUID 与 display ID 都随接法变
metadata:
  type: project
---

他的两台同型号外接屏:数字序列号(`CGDisplaySerialNumber`、EDID 字节 12–15)两台都是 19,EDID 只差 0xFF 描述块
「序列号文本」的末位。这一项每台不同、换口不变,是唯一能分清两台的标识;控制器节点上的
`DisplayAttributes.ProductAttributes.AlphanumericSerialNumber` 就是它。UUID 不行:显示偏好
`/Library/Preferences/com.apple.windowserver.displays.plist` 的 `DisplayUUIDMappings_v3` 里,这一型号同一个键下累计 10 个 UUID
(副键看着像连接位置);display ID 同一天先后给了两台不同的屏。

**Why:** 2026-10-23 他换接口后说「之前的主外接屏原来是 (2),现在成了 (1)」,还问「EDID 一样但应该有唯一 ID 吧」。
编号原按 UUID 排,设计文档写着「同型号 serial 完全相同、UUID 重连后稳定」——只看了数字序列号、从没在换口时核对过 UUID。
他的直觉是对的,逐字节比两个物理口上的 EDID 就找到了。

**How to apply:**
- 显示名 = 显示器自己的名字,同型号屏**不编号**,靠说明行的序列号尾号区分(他 2026-10-23 拍板,中间改过三轮:
  UUID 自编号 → 序列号自编号(与系统设置对不上)→ 照抄系统 (N)(随开关忽有忽无)→ 去掉编号)。
  「这是哪一台」的判断(行序、记住某台的状态)一律按 `identityKey(of:)`:序列号文本优先,没有才 UUID。
- 完整序列号是设备标识,**不进日志、诊断、提交**;界面只露尾号,终端里看也只印末位。
- 验证对应关系:序列号把「屏幕编号 → 控制器 → 物理口上的 EDID」端到端串起来,比改模式的差分更直接
  (做法见 [[hardware-description-differs-per-mac]])。HDMI 口给的 EDID 与 DP 口不同(数字序列号报 274),
  同一台屏走 HDMI 时序列号文本是否不变**尚未核对**。
