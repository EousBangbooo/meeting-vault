#!/bin/bash
# 端到端冒烟测试：初始化、归档、去重、索引、剪贴板解析。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export MEETING_KB="$TMP/vault"
export CLIP2FILE_STATE="$TMP/state"

"$ROOT/bin/setup.sh" "$MEETING_KB" >/dev/null
[ -d "$MEETING_KB/raw/meetings" ] || { echo "FAIL: setup"; exit 1; }

# 一份最小的转写
cat > "$TMP/2026-11-12-样例会议.txt" <<'EOF'
小林  00:00
这是虚构的读书会示例。我们正在安排一次社区读书交流，大家可以提前选择一本喜欢的书，
在活动中介绍书里让自己印象深刻的一个片段，并分享为什么愿意把它推荐给其他读者。
为了让第一次参加的人也能轻松加入，我们需要提前说明活动流程，并准备足够的椅子和纸笔。

小周  00:37
我可以负责整理大家提交的书名，也会准备一张简单的签到表。活动开始前，我会检查桌椅摆放，
看看是否有足够的空间供参与者走动。如果有人不想发言，也可以只听其他人分享，不必勉强。

小林  01:12
那就这样安排。活动结束以后，我们再收集参加者对时间、地点和流程的意见，记录哪些地方方便，
哪些地方需要调整。下一次活动的安排应根据收集到的反馈决定，不要提前假定大家的偏好。
如果遇到场地时间变化，就及时通知参与者；相关信息以主办方最后确认的通知为准。
活动结束后，也请记得把借阅的图书放回指定位置，方便下次活动的参与者继续使用。
EOF

"$ROOT/bin/archive.sh" "$TMP/2026-11-12-样例会议.txt" >/dev/null
[ -f "$MEETING_KB/raw/meetings/2026-11-12-样例会议.txt" ] || { echo "FAIL: archive"; exit 1; }

# 同内容第二次应跳过
out=$("$ROOT/bin/archive.sh" "$TMP/2026-11-12-样例会议.txt")
echo "$out" | grep -q "duplicate" || { echo "FAIL: dedupe"; exit 1; }
[ "$(ls "$MEETING_KB/raw/meetings" | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: dup file created"; exit 1; }

# 索引
python3 "$ROOT/bin/reindex.py" --root "$MEETING_KB" --out "$MEETING_KB/index" >/dev/null
grep -q "样例会议" "$MEETING_KB/index/会议索引.md" || { echo "FAIL: index"; exit 1; }
grep -q "2026-11-12" "$MEETING_KB/index/会议索引.md" || { echo "FAIL: index date"; exit 1; }

# 剪贴板解析（stdin 模式，不依赖 macOS）
"$ROOT/bin/clip2file.sh" --stdin < "$TMP/2026-11-12-样例会议.txt"
[ "$(ls "$MEETING_KB/inbox" | wc -l | tr -d ' ')" = "1" ] || { echo "FAIL: clip2file"; exit 1; }

BOARD="$MEETING_KB/会议处理.md"
TRANSCRIPT=$(basename "$MEETING_KB"/inbox/*.txt)
grep -q '待判断（1）' "$BOARD"
review() { python3 "$ROOT/bin/review.py" "$@"; }
[[ $(review remind) == *'1 场待判断'* ]]
[[ -z $(review remind) ]]

cat > "$TMP/review.json" <<'EOF'
{"reviewer":"测试判断人","reason":"收集活动反馈是已商定的事项。","items":[{"kind":"待办","statement":"活动后收集意见","evidence":"我们再收集参加者对时间、地点和流程的意见"}]}
EOF
review record "$TRANSCRIPT" "$TMP/review.json"
grep -q '待你确认（1）' "$BOARD"
grep -q '测试判断人' "$BOARD"
grep -q '我们再收集参加者对时间、地点和流程的意见' "$BOARD"
test ! -d "$MEETING_KB/knowledge/已确认"
review confirm "$TRANSCRIPT" 1
review confirm "$TRANSCRIPT" 1
review record "$TRANSCRIPT" "$TMP/review.json"
grep -q '已确认，沉淀 1 条' "$BOARD"
grep -q '打开已沉淀内容' "$BOARD"
grep -q '活动后收集意见' "$MEETING_KB"/knowledge/已确认/*.md
[[ -z $(review remind) ]]

printf '虚构的例行同步，没有决策。\n' > "$MEETING_KB/inbox/sync.txt"
printf '{"reviewer":"测试判断人","reason":"例行同步","items":[]}\n' > "$TMP/review.json"
review record sync.txt "$TMP/review.json"
grep -q '已判断，无可沉淀' "$BOARD"

echo "OK"
