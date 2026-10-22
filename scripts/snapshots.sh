#!/bin/bash
# 生成 README 里的面板截图(docs/screenshots/)。
#
# 截图用演示数据(通用屏名,不碰真实显示器)渲染**真实的面板视图**。
# 要包成 .app 再用 open 启动:原生开关只有在当前 app 的当前窗口里才画成强调色,
# 命令行直接跑的进程当不了当前 app,截出来开关全是灰的,与真机面板不符。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift build -c release --package-path "$ROOT" --product PanelSnapshots
APP="$TMP/PanelSnapshots.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/PanelSnapshots" "$APP/Contents/MacOS/PanelSnapshots"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.local.displayswitch.snapshots</string>
  <key>CFBundleExecutable</key><string>PanelSnapshots</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
LOG="$TMP/out.txt"
open -W -n "$APP" --stdout "$LOG" --stderr "$LOG" --args "$ROOT/docs/screenshots"
cat "$LOG"
grep -q "❌" "$LOG" && exit 1 || true
