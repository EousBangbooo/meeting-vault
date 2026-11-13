#!/bin/bash
# uninstall.sh — 停止并移除剪贴板监听。已归档的文件不受影响。
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.meeting-vault.clip2file.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "stopped. script and logs kept at ~/Library/Application Support/meeting-vault"
