# DisplaySwitch · 显示器开关

一个极简的 macOS 菜单栏小工具,**软件层面"真·断开 / 重连"任意一块显示器**——做到 BetterDisplay「断开/重连」的核心效果,但零配置、零依赖、不付费。

> 「关闭」= **虚拟断开**:让 macOS 以为该显示器被拔掉(从活跃列表消失、窗口自动迁到另一块屏、菜单栏/Dock 重排),「打开」再让它干净地回来。**不是**熄背光、**不是**镜像切换。

<p align="center">
  <img src="Resources/icon.png" width="96" alt="DisplaySwitch 图标">
</p>

## 功能

- 点菜单栏图标 → 列出**当前所有显示器(含内建屏)**,✓ 表示开启,点一行即开/关。
- 显示名 = **系统名 + 稳定编号 +(主)**。同型号多块屏按 UUID 稳定编号 `(1)(2)`,关/开/移动都不漂移。
- **绝不把你置于"无法恢复的全黑"**(见下「安全模型」)。
- 退出 app(菜单「退出 ⌘Q」)或进程结束 → **自动恢复所有被关的屏**。

## 系统要求

- **Apple Silicon(M 系列)** + **macOS 13+**(开发/验证于 M5 Pro · macOS 26)。
- 非 Apple Silicon 或私有接口缺失时,app 自动**只读不可切换**并在菜单顶部提示——绝不在未验证平台上动显示器。

## 构建与安装

```bash
# 构建 + 跑测试
swift build
swift test

# 打包成 .app(生成 build/DisplaySwitch.app,ad-hoc 签名)
./scripts/package.sh

# 安装:把 build/DisplaySwitch.app 拖进「应用程序」即可
```

它是菜单栏常驻应用(无 Dock 图标、无窗口),启动后看屏幕**右上角菜单栏**的图标。

### 分发给别人(过 Gatekeeper)

本地 ad-hoc 签名、未做公证,拷给别人首次打开会提示"无法验证开发者"。最省事:

```bash
xattr -dr com.apple.quarantine /Applications/DisplaySwitch.app
```

或:右键 App →「打开」→ 系统设置 → 隐私与安全性 → 拉到底点「仍要打开」。

## 安全模型(为何不会把你卡死在全黑)

核心规则:**绝不把用户置于"无法恢复的全黑"**。`canDisable` 在关屏前校验:

- 关后仍剩 ≥1 块活跃屏 → 允许;
- 关后会全黑 → 仅当存在**可开盖恢复的内建屏**兜底才允许:
  - **笔记本**(合盖也算,靠电池检测)→ 允许关到全黑,**开盖即恢复内建屏**;
  - **无内建屏的台式机**(Mac mini 等)→ 必须留 ≥1 块活跃屏。
- **死锁加固**:内建屏被本 app 软件关掉后不再算兜底;也禁止把内建屏自己关成全黑。

兜底恢复链:

- 全程 `.forAppOnly`(**绝不** `.permanently`)→ 进程退出/崩溃/被杀,系统**自动回滚**所有被关的屏。
- **永不开机自启**(硬约束)→ 万一遇到物理拔屏导致的全黑边界,**强制重启**后必为「所有屏正常、app 未运行」的干净状态。

## 说明

- 用到 macOS 私有符号 `CGSConfigureDisplayEnabled`(经 `dlsym` 动态解析,无链接期硬依赖),因此**无法上架 App Store**,仅本地/自分发。
- 不关 SIP、不需特殊 entitlement、不申请任何权限。
- 设计细节见 [`docs/superpowers/specs/2026-06-18-display-switch-design.md`](docs/superpowers/specs/2026-06-18-display-switch-design.md)。
