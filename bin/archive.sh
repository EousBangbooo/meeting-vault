#!/bin/bash
# archive.sh — 把一份会议转写归档进会议库。
# 原则：先算指纹、再落盘；**永远不删除源文件**。
#
# 用法：
#   ./bin/archive.sh ~/Desktop/2026-11-12-读书会.txt          # 主题从文件名推断
#   ./bin/archive.sh ~/Desktop/meeting.txt "读书会"           # 显式指定主题
#   MEETING_KB=/path ./bin/archive.sh file.txt
set -uo pipefail
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

KB="${MEETING_KB:-$HOME/MeetingVault}"
DEST="$KB/raw/meetings"
MANIFEST="$KB/raw/_manifest.tsv"
mkdir -p "$DEST" || { echo "cannot create $DEST" >&2; exit 1; }
touch "$MANIFEST"

SRC="${1:-}"
TOPIC="${2:-}"
if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "usage: $0 <transcript.txt> [topic]" >&2
  exit 2
fi

BASE=$(basename "$SRC")
YEAR=$(date '+%Y')

# 日期：优先取文件名前缀，取不到用今天
DATE=""
if [[ "$BASE" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
  DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
elif [[ "$BASE" =~ ^([0-9]{4})\.([0-9]{1,2})\.([0-9]{1,2}) ]]; then
  DATE=$(printf "%s-%02d-%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
elif [[ "$BASE" =~ ^([0-9]{4})-([0-9]{2})\.([0-9]{1,2}) ]]; then
  DATE=$(printf "%s-%s-%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
elif [[ "$BASE" =~ ^([0-9]{1,2})\.([0-9]{1,2})[-_\.] ]]; then
  DATE=$(printf "%s-%02d-%02d" "$YEAR" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")
else
  DATE=$(date '+%Y-%m-%d')
fi

# 主题：优先用参数，否则从文件名去掉日期前缀
if [ -z "$TOPIC" ]; then
  TOPIC=$(echo "$BASE" | sed -E 's/^[0-9]{4}[-.][0-9]{1,2}[-.][0-9]{1,2}[-_ ]?//; s/^[0-9]{1,2}\.[0-9]{1,2}[-_ ]?//; s/\.txt$//')
fi
[ -z "$TOPIC" ] && TOPIC="untitled"

SHA=$(shasum -a 256 "$SRC" | awk '{print $1}')
if grep -q "$SHA" "$MANIFEST" 2>/dev/null; then
  echo "duplicate content, skipped: $SHA"
  exit 0
fi

SAFE=$(echo "$TOPIC" | tr '/' '-')
OUT="$DATE-$SAFE.txt"
i=2
while [ -e "$DEST/$OUT" ]; do OUT="$DATE-$SAFE-$i.txt"; i=$((i+1)); done

cp "$SRC" "$DEST/$OUT" || { echo "copy failed, source untouched" >&2; exit 1; }

CHARS=$(wc -m < "$DEST/$OUT" | tr -d ' ')
LINES=$(wc -l < "$DEST/$OUT" | tr -d ' ')
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$DATE" "$OUT" "$SHA" "$CHARS" "$LINES" "$(date '+%F %T')" >> "$MANIFEST"

echo "archived: raw/meetings/$OUT"
echo "  sha256 $SHA"
echo "  $CHARS chars / $LINES lines"
echo "source kept: $SRC"
