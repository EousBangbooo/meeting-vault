#!/bin/bash
# install.sh — 把 clip2file 装成登录自启的后台服务（macOS LaunchAgent）。
#
# 用法：
#   ./bin/install.sh                 # 默认会议库 ~/MeetingVault
#   ./bin/install.sh /path/to/vault  # 指定会议库
set -euo pipefail

command -v pbpaste >/dev/null || { echo "macOS only"; exit 1; }
PYTHON_BIN=$(command -v python3) || { echo "Python 3 is required"; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
KB="${1:-${MEETING_KB:-$HOME/MeetingVault}}"
BIN_DIR="$HOME/Library/Application Support/meeting-vault"
PLIST="$HOME/Library/LaunchAgents/com.meeting-vault.clip2file.plist"
LABEL="com.meeting-vault.clip2file"

mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$KB/inbox"
cp "$DIR/clip2file.sh" "$BIN_DIR/clip2file.sh"
cp "$DIR/review.py" "$BIN_DIR/review.py"
chmod +x "$BIN_DIR/clip2file.sh"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$BIN_DIR/clip2file.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MEETING_KB</key><string>$KB</string>
    <key>PATH</key><string>$(dirname "$PYTHON_BIN"):/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$BIN_DIR/stdout.log</string>
  <key>StandardErrorPath</key><string>$BIN_DIR/stderr.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/$LABEL" 2>/dev/null || true

echo "installed: $LABEL"
echo "inbox:  $KB/inbox"
echo "log:    $BIN_DIR/clip2file.log"
echo "test:   复制一段转写，打开 $KB/会议处理.md 查看待判断状态"
