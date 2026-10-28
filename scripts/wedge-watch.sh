#!/bin/bash
# 雷雳显示驱动卡死的监视器:菜单栏小 app「雷雳驱动监视」(源码 Sources/WedgeWatch)。
# 独立于 DisplaySwitch:判断只读系统日志,不碰显示器;只有已经卡住时才读设备树存现场。
#
# 为什么需要:驱动卡死有时是悄悄的——两块屏照常亮着,一拔坞才出残影屏、插回或开盖约 60 秒就内核崩溃。
# 2026-10-26 起他停用 DisplaySwitch 做对照实验,面板上的卡死提示也跟着没了,这里补一个不依赖它的探测。
# 正因为要做对照,它不调 DisplaySwitch 用来操作显示器的任何接口;唤醒和插拔坞只被动收系统通知。
# 图标常驻菜单栏,不在后台悄悄跑(他:「要放个图标让我知道,不要偷偷摸摸」)。
# 什么时候查:每 4 小时一次(他定的),外加屏幕唤醒后 1 分钟、插拔坞后 10 秒各一次(2026-10-28 他同意加)。
#
# 判据:卡死时内核每秒刷 10 条 `evaluating for > 1m ... DPO [...]`,健康时 0 条——实时采 3 秒就够。
# 不用 `log show` 回看:本机内核日志不落盘,内存里只留约 1 分钟,卡死时能回看到的只剩几条。
# 开销(实测):每次约 3 秒,几乎不占 CPU,约 4 MB 内存。
#
# 卡住时自动存现场到 ~/Library/Logs/DisplaySwitch-wedge-evidence(之前几次的现场没留下,报给 Apple 时只剩抄录):
# 当时的内核日志、设备树里 DP 适配器的状态、近 24 小时的唤醒与屏幕插拔、睡眠与充电记录;
# 每次检查还把系统新出现的崩溃 / 关机卡住报告(原件约一周被清)和他按 ⌃⌥⇧⌘. 收的完整诊断拷过去。
#
# 用法:bash scripts/wedge-watch.sh install     编译、装进 /Applications、登录时自动打开,并立刻打开
#       bash scripts/wedge-watch.sh uninstall   退出并卸掉(检查记录和现场留着)
#       bash scripts/wedge-watch.sh status      是否在跑 + 最近几次结果
#       bash scripts/wedge-watch.sh check       在终端里手动查一次(结果同样记进检查记录)
#       bash scripts/wedge-watch.sh build       只编译出 build/ 下的 app,不安装(验证用)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.local.displayswitch.wedge-watch"
APP_NAME="雷雳驱动监视"
APP="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# 早先的纯脚本版(每 30 分钟、无图标)装在这里,装新版时一并清掉。
OLD_SCRIPT_DIR="$HOME/Library/Application Support/DisplaySwitch-wedge-watch"
# 三个覆盖项只供验证用(换成一个必有输出的谓词、记到另一份文件、现场存到另一处);平时不设。
PREDICATE="${WEDGE_WATCH_PREDICATE:-process == \"kernel\" AND eventMessage CONTAINS \"evaluating for > 1m\"}"
LOG="${WEDGE_WATCH_LOG:-$HOME/Library/Logs/DisplaySwitch-wedge-watch.log}"
EVIDENCE="${WEDGE_WATCH_EVIDENCE:-$HOME/Library/Logs/DisplaySwitch-wedge-evidence}"
TEST_MARK="${WEDGE_WATCH_PREDICATE:+【测试】}"

check() {
    local n
    # 与 app 同一判据。`log stream` 先打印的表头带着谓词原文,所以数报错正文里才有的 `DPO [`。
    # 用它自带的 --timeout 正常退出:从外面用信号掐断会丢掉还没写出的输出(2026-10-26 实测漏数)。
    n=$(/usr/bin/log stream --timeout 3s --predicate "$PREDICATE" --style compact 2>/dev/null \
        | grep -c 'DPO \[' || true)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${TEST_MARK}卡死特征 ${n} 条 / 3 秒（终端）" >> "$LOG"
    echo "$n"
}

build() {
    swift build -c release --product WedgeWatch --package-path "$ROOT" >&2
    local out="$ROOT/build/$APP_NAME.app"
    rm -rf "$out"
    mkdir -p "$out/Contents/MacOS"
    cp "$ROOT/.build/release/WedgeWatch" "$out/Contents/MacOS/WedgeWatch"
    cat > "$out/Contents/Info.plist" <<INFO
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleExecutable</key><string>WedgeWatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
INFO
    codesign --force --deep --sign - "$out" >&2
    echo "$out"
}

install() {
    local built
    built="$(build)"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    pkill -x WedgeWatch 2>/dev/null || true
    rm -rf "$APP" "$OLD_SCRIPT_DIR"
    cp -R "$built" "$APP"
    mkdir -p "$(dirname "$PLIST")"
    # 只在登录时打开一次(RunAtLoad),不设 KeepAlive:他从菜单里退出,就一直退着,直到下次登录。
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$APP/Contents/MacOS/WedgeWatch</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "已装上并打开:$APP(菜单栏图标),每 4 小时、屏幕唤醒后、插拔坞后各查一次,结果记在 $LOG"
}

uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    pkill -x WedgeWatch 2>/dev/null || true
    rm -rf "$PLIST" "$APP" "$OLD_SCRIPT_DIR"
    echo "已退出并卸掉;检查记录留着:$LOG,现场留着:$EVIDENCE"
}

status() {
    if pgrep -x WedgeWatch >/dev/null; then echo "在跑(菜单栏「${APP_NAME}」)"; else echo "没在跑"; fi
    [ -f "$LOG" ] && tail -n 5 "$LOG" || true
    if [ -d "$EVIDENCE" ]; then echo "现场:$EVIDENCE($(find "$EVIDENCE" -maxdepth 1 -name 'wedge-*' | wc -l | tr -d ' ') 份卡住现场)"; fi
}

case "${1:-}" in
    build) build ;;
    install) install ;;
    uninstall) uninstall ;;
    status) status ;;
    check) check ;;
    *) echo "用法:bash $0 build | install | uninstall | status | check" >&2; exit 2 ;;
esac
