---
name: release-needs-real-machine-acceptance
description: DisplaySwitch 发 release 必须先真机验收,且界面 / 文案 / 交互类改动要等他明确说「没问题」才发;commit/push 随时做,tag 可多打
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

**2026-10-22 补:「真机验收通过」要由他说,不由我判。** v1.0.17(菜单改成弹出面板)我请他配合点了几步、
自己截图看过,就判定通过、直接发了 release;他原话:「你没等我确认没问题你就打包推送生产了」。
发布后他用了才发现首次点击开关没反应、锁住原因文案含义不对——**这正是只有他用了才知道的东西**。
**How to apply(补):** 凡他会直接看到、用到的改动(界面、文案、交互),发 release 前必须等他一句明确的
「没问题 / 可以发」;我自己的截图核验只是发给他验收之前的前置检查。commit / push / tag 照旧随时。

**2026-10-23 补:版本可能是另一台机器发的,本机也要换上。** 他在 Mac mini 上发了 v1.0.19,我在 MacBook 上拉下代码、
做完待办核对,却没把本机运行的 1.0.18 换掉;他在 1.0.18 上验了 HDMI,原话「但是是在1.0.18版本上看的,你没帮我换成1.0.19版本」。
**How to apply(补):** `git pull` 拉到新的版本标签时,对一下 `/Applications/DisplaySwitch.app` 的版本与最新 release;
落后就用发布的 zip 换上并换掉运行实例(换前按 [[swapping-running-instance-relights-screens]] 记下关着的屏),
之后再请他在本机验东西。
