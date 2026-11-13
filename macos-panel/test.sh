#!/bin/bash
# 端到端自检：只使用当前目录内的模拟库，不启动 GUI、不访问真实会议库。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
mkdir -p "$ROOT/证据"

echo "== 1/4 生成模拟库 =="
python3 fixtures/make_fixture.py | tee 证据/fixture-generate.log

echo "== 2/4 独立校验模拟库 =="
python3 fixtures/verify_fixture.py | tee 证据/fixture-verify.log

echo "== 3/4 编译 .app =="
./build.sh | tee 证据/build.log

echo "== 4/4 Swift 状态与刷新自测 =="
.build/MeetingVaultPanel --self-test --vault fixtures/vault | tee 证据/self-test.log

echo "== 附加：只读库自测（chmod a-w 后仍可扫描） =="
READONLY="$ROOT/.build/readonly-vault"
case "$READONLY" in
  "$ROOT/.build/"*) ;;
  *) echo "refuse to remove unexpected path: $READONLY" >&2; exit 1 ;;
esac
rm -rf "$READONLY"
cp -Rp fixtures/vault "$READONLY"
chmod -R a-w "$READONLY"
set +e
.build/MeetingVaultPanel --self-test --vault "$READONLY" > 证据/self-test-readonly.log 2>&1
READONLY_STATUS=$?
set -e
chmod -R u+w "$READONLY"
rm -rf "$READONLY"
tail -1 证据/self-test-readonly.log
if [ "$READONLY_STATUS" -ne 0 ]; then
  echo "read-only vault self-test failed; see 证据/self-test-readonly.log" >&2
  exit "$READONLY_STATUS"
fi

echo "ALL PASS"
