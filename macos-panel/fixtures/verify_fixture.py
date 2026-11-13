#!/usr/bin/env python3
"""独立校验模拟库布局与期望计数，不依赖 Swift 自测代码。"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VAULT = ROOT / "vault"
EXPECTED = json.loads((ROOT / "expected.json").read_text(encoding="utf-8"))

failures: list[str] = []
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if condition:
        print(f"PASS  {message}")
    else:
        failures.append(message)
        print(f"FAIL  {message}")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    inbox = VAULT / "inbox"
    review = VAULT / ".meeting-review"
    files = sorted(p for p in inbox.glob("*.txt") if p.is_file())
    check(len(files) == EXPECTED["inboxFiles"], f"inbox 文件数 {len(files)} == {EXPECTED['inboxFiles']}")

    groups: dict[str, list[Path]] = {}
    for path in files:
        groups.setdefault(digest(path), []).append(path)

    scenarios = EXPECTED["scenarios"]
    check(len(groups) == EXPECTED["meetings"], f"按 SHA 分组 {len(groups)} 场 == {EXPECTED['meetings']}")

    seen: set[str] = set()
    for sha, paths in groups.items():
        paths.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        name = paths[0].stem
        seen.add(name)
        check(name in scenarios, f"{name} 在 expected.json 中有场景")
        item = scenarios.get(name, {})
        expected_dup = int(item.get("duplicateCount", 0))
        check(len(paths) - 1 == expected_dup, f"{name} 重复副本 {len(paths) - 1} == {expected_dup}")
        if len(paths) > 1:
            check(len({digest(p) for p in paths}) == 1, f"{name} 重复文件内容一致")

        receipt = review / f"{sha}.json"
        if item.get("parseError"):
            check(receipt.exists(), f"{name} 存在坏回执文件")
            try:
                json.loads(receipt.read_text(encoding="utf-8"))
                check(False, f"{name} 坏回执应无法解析")
            except json.JSONDecodeError:
                check(True, f"{name} 坏回执按预期无法解析")
        elif item.get("status") in {"awaitingDecision", "processed", "unknown"}:
            check(receipt.exists(), f"{name} 存在回执")
            if receipt.exists():
                try:
                    json.loads(receipt.read_text(encoding="utf-8"))
                    check(True, f"{name} 回执 JSON 合法")
                except json.JSONDecodeError:
                    check(False, f"{name} 回执 JSON 应合法")
        else:
            check(not receipt.exists(), f"{name} 无回执")

        if item.get("hasHTML"):
            check((review / f"{sha}.html").exists(), f"{name} 存在详情 HTML")

    check(seen == set(scenarios), "场景名集合与文件分组一致")

    counts = {
        "pending": 0,
        "reviewing": 0,
        "awaitingDecision": 0,
        "processed": 0,
        "unknown": 0,
        "duplicateExtras": 0,
        "conflicts": 0,
        "waitingLong": 0,
    }
    for item in scenarios.values():
        counts[item["status"]] += 1
        counts["duplicateExtras"] += int(item.get("duplicateCount", 0))
        counts["conflicts"] += int(bool(item.get("conflict")))
        counts["waitingLong"] += int(bool(item.get("waitingLong")))
    check(counts == EXPECTED["counts"], "场景状态汇总与 expected.counts 一致")

    # 真实 POSIX 权限故障：chmod 000 后列目录必须失败，恢复后成功。
    permission_inbox = ROOT / "permission-vault" / "inbox"
    check(permission_inbox.is_dir(), "权限故障模拟库存在")
    os.chmod(permission_inbox, 0o000)
    permission_denied = False
    try:
        os.listdir(permission_inbox)
    except PermissionError:
        permission_denied = True
    finally:
        os.chmod(permission_inbox, 0o755)
    check(permission_denied, "chmod 000 后 inbox 不可列举（权限故障可复现）")
    check(len(os.listdir(permission_inbox)) == 1, "权限恢复后可正常列举")

    print(f"SUMMARY {json.dumps(EXPECTED['counts'], ensure_ascii=False)}")
    if failures:
        print(f"RESULT: FAIL {checks - len(failures)}/{checks}")
        return 1
    print(f"RESULT: PASS {checks}/{checks}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
