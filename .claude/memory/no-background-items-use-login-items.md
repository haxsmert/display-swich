---
name: no-background-items-use-login-items
description: 给他装的常驻小工具用普通「登录时打开」,别注册 LaunchAgent——macOS 会弹「App 后台活动:可在后台运行」,他视为偷偷摸摸
metadata:
  type: feedback
---

给他机器装需要开机自启的小工具时,用普通登录项(System Events `make login item`,系统设置里归在「登录时打开」),
**不要注册 LaunchAgent**。

**Why:** 2026-10-28 重装「雷雳驱动监视」时,LaunchAgent 让系统弹「App 后台活动:“WedgeWatch”可在后台运行」(每次重装都弹,
`BackgroundTaskManagementAgent` 日志里是 `Posting advisory notification`)。他看到后说「不行,我不想做成后台的」;
我起初没问他看到了什么,误以为说的是取证方式,白改了一版,直到他贴出通知截图。
改成登录项后,系统后台项目记录(`sfltool dumpbtm`)里只剩一条 `Type: app`;加登录项那一次系统也发了一条提示。
macOS 27 的「后台 App 活动」列表仍把它和 AlDente 等菜单栏 app 一起标成「正在后台运行」——推断是菜单栏 app 的统一显示。
重装时会不会再弹还没验证;记录已标 `notified`、按 bundle id 认,推断不会。

**How to apply:** 自启动一律走登录项;卸载时同样从登录项删掉。他对一个动作突然否定、话又很短时,
先问清他看到了什么(通知、弹窗、截图),再动手。参见 [[panic-thunderbolt-dp-wedge-not-displayswitch]]、[[preserve-live-fault-evidence]]。
