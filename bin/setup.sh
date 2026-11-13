#!/bin/bash
# setup.sh — 初始化一个空的会议库。
#
# 用法：
#   ./bin/setup.sh                  # ~/MeetingVault
#   ./bin/setup.sh /path/to/vault   # 自定义
set -euo pipefail

KB="${1:-${MEETING_KB:-$HOME/MeetingVault}}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$KB"/{raw/meetings,inbox,index,knowledge}
for f in 方法论 问题清单 事件库 未完成 决策日志; do
  [ -e "$KB/knowledge/$f.md" ] || printf '# %s\n\n> 由 AI 按 docs/prompts.md 生成，可手工修订。\n' "$f" > "$KB/knowledge/$f.md"
done
[ -e "$KB/raw/_manifest.tsv" ] || printf '' > "$KB/raw/_manifest.tsv"
cp -n "$DIR/templates/meeting-card.md" "$KB/knowledge/_会议卡片模板.md" 2>/dev/null || true
python3 "$DIR/bin/review.py" --root "$KB" status

cat <<EOF
meeting vault ready: $KB

next:
  1. ./bin/install.sh "$KB"        # macOS: 剪贴板自动归档
  2. ./bin/archive.sh <file.txt>   # 或手动归档
  3. python3 bin/reindex.py --root "$KB" --out "$KB/index"
EOF
