#!/bin/bash
# clip2file.sh — 监听 macOS 剪贴板，把会议转写自动落盘。
#
# 用法：
#   clip2file.sh            常驻，每秒检查一次剪贴板
#   clip2file.sh --once     只检查一次（调试）
#   clip2file.sh --stdin    从标准输入读一段文本（测试，不碰剪贴板）
#
# 环境变量：
#   MEETING_KB        会议库根目录（默认 ~/MeetingVault）
#   CLIP2FILE_STATE   状态/日志目录（默认 ~/Library/Application Support/meeting-vault）

set -uo pipefail

# launchd 启动时没有 LANG，pbcopy/pbpaste 在 C locale 下会丢非 ASCII 字符。
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

KB="${MEETING_KB:-$HOME/MeetingVault}"
DIR="$(cd "$(dirname "$0")" && pwd)"
INBOX="$KB/inbox"
STATE="${CLIP2FILE_STATE:-$HOME/Library/Application Support/meeting-vault}"
LOG="$STATE/clip2file.log"
HASHES="$STATE/hashes.txt"
MAX_BYTES=$((8 * 1024 * 1024))

mkdir -p "$INBOX" "$STATE" || { echo "cannot create $INBOX / $STATE" >&2; exit 1; }
touch "$HASHES"

ts() { date '+%Y-%m-%d %H:%M:%S'; }

notify() {
  [ -x /usr/bin/osascript ] || return 0
  /usr/bin/osascript -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title "Meeting Vault"' \
    -e 'end run' -- "$1" >/dev/null 2>>"$LOG" || true
}

# 判断一段文本像不像转写稿：
#   - 至少 3 行「说话人 + 时间码」
#   - 正文 ≥ 400 字符
# 时间码可以是 00:12 或 01:02:03，说话人最多 40 字符，中间至少两个空格或一个制表符。
is_transcript() {
  local f="$1" n chars
  n=$(grep -cE '^[^[:space:]].{0,40}[[:space:]]{2,}[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?[[:space:]]*$' "$f" 2>/dev/null)
  chars=$(wc -m < "$f" | tr -d ' ')
  [ "${n:-0}" -ge 3 ] && [ "${chars:-0}" -ge 400 ]
}

handle() {
  local src="$1" size h when name dest staged i=2
  size=$(wc -c < "$src" | tr -d ' ')
  [ "${size:-0}" -eq 0 ] && return 1
  [ "$size" -gt "$MAX_BYTES" ] && return 1
  is_transcript "$src" || return 1

  h=$(shasum -a 256 "$src" | awk '{print $1}')
  if grep -qx "$h" "$HASHES" 2>/dev/null; then
    echo "$(ts) skip duplicate $h" >> "$LOG"
    return 3
  fi

  when=$(date '+%Y-%m-%d_%H%M')
  name="${when}_clipboard.txt"
  dest="$INBOX/$name"
  while [ -e "$dest" ]; do
    dest="$INBOX/${when}_clipboard-$i.txt"
    i=$((i + 1))
  done

  # 统一成 LF 换行后落盘
  staged=$(mktemp "$INBOX/.capture.XXXXXX") || return 1
  if ! tr -d '\r' < "$src" > "$staged" || ! mv "$staged" "$dest"; then
    rm -f "$staged"
    return 1
  fi
  echo "$h" >> "$HASHES"
  echo "$(ts) saved $name ($(wc -l < "$dest" | tr -d ' ') lines)" >> "$LOG"
  if python3 "$DIR/review.py" --root "$KB" status >>"$LOG" 2>&1; then
    [ "${2:-}" = quiet ] || notify "已保存，等待判断。打开会议库中的「会议处理.md」。"
  else
    [ "${2:-}" = quiet ] || notify "转写已保存，处理页刷新失败。请查看本机日志。"
  fi
  return 0
}

run_once() {
  local tmp rc
  tmp=$(mktemp)
  pbpaste > "$tmp" 2>/dev/null
  handle "$tmp"
  rc=$?
  rm -f "$tmp"
  return $rc
}

case "${1:-}" in
  --stdin)
    tmp=$(mktemp)
    cat > "$tmp"
    handle "$tmp" quiet
    rc=$?
    rm -f "$tmp"
    exit "$rc"
    ;;
  --once)
    run_once
    exit $?
    ;;
esac

echo "$(ts) started, watching clipboard -> $INBOX" >> "$LOG"
next_reminder=0
while true; do
  run_once
  if [ "$SECONDS" -ge "$next_reminder" ]; then
    reminder=$(python3 "$DIR/review.py" --root "$KB" remind 2>>"$LOG") || reminder=""
    [ -z "$reminder" ] || notify "$reminder"
    next_reminder=$((SECONDS + 300))
  fi
  sleep 1
done
