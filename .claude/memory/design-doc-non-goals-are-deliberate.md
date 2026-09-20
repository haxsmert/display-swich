---
name: design-doc-non-goals-are-deliberate
description: DisplaySwitch 设计文档的 §3 非目标与 §7 取舍记录了大量「故意不做」,代码里看似的缺口多半是有意为之,动手前必读全文
metadata:
  type: project
---

DisplaySwitch(`~/projects/display-swich`)的设计文档
`docs/superpowers/specs/2026-06-18-display-switch-design.md` 里,
§3「非目标(YAGNI)」与 §7「安全保护规则与死锁安全模型」记录了大量**故意不做**的决策。
其中「永不开机自启」「绝不 `.permanently`」是**硬安全约束**(重启逃生链条的一环),不是偏好。

**Why:** 2026-09-07 修全黑 bug 时,我 grep 到「全仓库零显示配置监听」,直接当成缺口开工并发了版;
事后才发现 §3 明确写着「拔屏自动恢复守护(已实验证伪)」,§7.2 还详述了取舍理由和证伪的两条路。
在一个成熟项目里,一个标准机制**完全缺席**本身就是信号,不是漏洞。

**How to apply:** 动手改这个项目前读 §3 和 §7 **全文**,不要只搜与当前 bug 相关的段落。
要推翻其中的取舍,先与他对齐方向再动手——那属于「语义/约定类大事」。
注意 §7.2 有一半依据已过期(`.forAppOnly` 进程退出回滚已被 2026-08-31 实测推翻),
读到旧结论时分清它的**观测事实**与**推论**。参见 [[displayswitch-real-usage-dock-workflow]]。
