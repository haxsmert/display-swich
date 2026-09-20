---
name: release-needs-real-machine-acceptance
description: DisplaySwitch 发 release 必须先真机验收;commit/push 随时做,tag 可多打,但 release 是对外承诺
metadata:
  type: feedback
---

DisplaySwitch 的三层动作门槛不同:**commit + push** 随时做(工作记录,允许中间态)、
**tag** 可以多打(不对外承诺什么)、**release 必须真机验收通过**才发。

**Why:** 2026-09-18 我一天发了 6 个 release、57 分钟内发了 4 个,其中一个是从不触发的死代码、
一个引入了比原 bug 更隐蔽的回归、两个根本没修好。根子是我把「发 release」当成了
**完成的仪式**——发出去才觉得交付完——于是这个公开、带永久记录、会被人下载的动作,
门槛降到了零。他当场质疑:「你为什么每一次急急忙忙打 tag、发布 release?」

注意 CLAUDE.md 那条「做完直接推,别逐步问」指的是**别停下来确认**,
不是「每次改动都发一个正式版本」。我曾把两者混为一谈。

**How to apply:** 发 release 前先问一句——**这个版本我是否已经在真机、按他的真实动线验证过?**
没有就只 commit。修 bug 尤其要守:「我以为修好了」和「真的修好了」之间可能隔着好几个版本。
参见 [[displayswitch-real-usage-dock-workflow]](按那条动线验收)。
