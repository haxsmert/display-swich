#!/bin/bash
# 雷雳显示驱动卡死的后台提醒。独立于 app:只读系统日志,不碰显示器、不读设备树。
#
# 为什么需要:驱动卡死有时是悄悄的——两块屏照常亮着,一拔坞才出残影屏、或开盖后内核崩溃(2026-10-22)。
# 2026-10-26 起他停用 app 做对照实验,面板上的卡死提示也跟着没了,这里补一个不依赖 app 的探测。
# 正因为要做对照,它只用 `log` 命令,不调 app 用到的任何显示 / IOKit 接口。
#
# 判据:卡死时内核每秒刷 10 条 `evaluating for > 1m ... DPO [...]`,健康时 0 条——实时采 3 秒就够。
# 不用 `log show` 回看:本机内核日志不落盘,内存里只留约 1 分钟,卡死时能回看到的只剩几条。
# 开销(实测):每次约 3 秒,几乎不占 CPU,约 4 MB 内存;每 30 分钟一次,以后台优先级跑。
#
# 用法:bash scripts/wedge-watch.sh install     装上(登录后自动跑,装完立刻查一次)
#       bash scripts/wedge-watch.sh uninstall   卸掉(记录文件留着,实验收尾要看)
#       bash scripts/wedge-watch.sh status      是否在跑 + 最近几次结果
#       bash scripts/wedge-watch.sh check       手动查一次
set -euo pipefail

LABEL="com.local.displayswitch.wedge-watch"
INTERVAL=1800
INSTALLED="$HOME/Library/Application Support/DisplaySwitch-wedge-watch/wedge-watch.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# 三个覆盖项只供验证提醒能弹出来(换成一个必有输出的谓词);平时不设。
PREDICATE="${WEDGE_WATCH_PREDICATE:-process == \"kernel\" AND eventMessage CONTAINS \"evaluating for > 1m\"}"
MATCH="${WEDGE_WATCH_MATCH:-DPO \\[}"
LOG="${WEDGE_WATCH_LOG:-$HOME/Library/Logs/DisplaySwitch-wedge-watch.log}"
TEST_MARK="${WEDGE_WATCH_PREDICATE:+【测试】}"

check() {
    local n
    # `log stream` 自己会先打印一行带着谓词原文的表头,所以数的是报错正文里才有的 `DPO [`,不数谓词里的字。
    # 用它自带的 --timeout 正常退出;用信号从外面掐断会丢掉还没写出的输出(2026-10-26 实测漏数)。
    n=$(/usr/bin/log stream --timeout 3s --predicate "$PREDICATE" --style compact 2>/dev/null \
        | grep -c "$MATCH" || true)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${TEST_MARK}卡死特征 ${n} 条 / 3 秒" >> "$LOG"
    # 只留最近一段:每天 48 行,2000 行约一个半月。
    if [ "$(wc -l < "$LOG")" -gt 3000 ]; then
        tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    if [ "$n" -gt 0 ]; then
        osascript -e "display notification \"存好东西,接着坞重启。卡住时拔坞会出残影屏,或开盖后内核崩溃。\" with title \"${TEST_MARK}雷雳显示驱动卡住了\" sound name \"Basso\"" || true
    fi
    echo "$n"
}

install() {
    mkdir -p "$(dirname "$INSTALLED")" "$(dirname "$PLIST")"
    # 拷一份出去再挂:不依赖仓库的位置,仓库挪了、切了分支也照跑。
    cp "$0" "$INSTALLED"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$INSTALLED</string><string>check</string></array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Background</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "已装上:每 $((INTERVAL / 60)) 分钟查一次,结果记在 $LOG"
}

uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$INSTALLED"
    rmdir "$(dirname "$INSTALLED")" 2>/dev/null || true
    echo "已卸掉;记录文件留着:$LOG"
}

status() {
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "在跑($LABEL)"; else echo "没装"; fi
    [ -f "$LOG" ] && tail -n 5 "$LOG" || true
}

case "${1:-}" in
    install) install ;;
    uninstall) uninstall ;;
    status) status ;;
    check) check ;;
    *) echo "用法:bash $0 install | uninstall | status | check" >&2; exit 2 ;;
esac
