#!/usr/bin/env python3
"""生成隔离模拟会议库，仅供本源型目录内测试。

不读取真实会议库。所有文本均为虚构样例。
"""
from __future__ import annotations

import hashlib
import json
import shutil
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VAULT = ROOT / "vault"
PERMISSION_VAULT = ROOT / "permission-vault"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_inbox(name: str, text: str, age_seconds: int) -> str:
    path = VAULT / "inbox" / name
    path.write_text(text, encoding="utf-8")
    stamp = time.time() - age_seconds
    import os

    os.utime(path, (stamp, stamp))
    return sha256_text(text)


def write_started(digest: str, age_seconds: int) -> None:
    import os

    path = VAULT / ".meeting-review" / f"{digest}.started"
    path.write_text("started\n", encoding="utf-8")
    stamp = time.time() - age_seconds
    os.utime(path, (stamp, stamp))


def write_receipt(digest: str, payload: object, malformed: bool = False) -> None:
    path = VAULT / ".meeting-review" / f"{digest}.json"
    if malformed:
        path.write_text('{"items":[', encoding="utf-8")
    else:
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if VAULT.exists():
        shutil.rmtree(VAULT)
    (VAULT / "inbox").mkdir(parents=True)
    (VAULT / ".meeting-review").mkdir(parents=True)

    scenarios = {}

    def scenario(name: str, status: str, **extra: object) -> None:
        scenarios[name] = {"status": status, **extra}

    # 1. 待审：无 started、无回执。
    digest = write_inbox(
        "待审-产品周会.txt",
        "# 产品周会\n议题：11 月版本范围与发布节奏。\n决议：周五前确认灰度名单。\n",
        300,
    )
    scenario("待审-产品周会", "pending")

    # 2. 审核中：有 started、无回执；started 超过阈值。
    digest = write_inbox(
        "审核中-客户回访.txt",
        "# 客户回访\n客户关注导出速度与权限分级，需补充两次现场反馈。\n",
        700,
    )
    write_started(digest, 3600)
    scenario("审核中-客户回访", "reviewing", waitingLong=True)

    # 3. 待决定：有候选，旧回执缺 accepted。
    digest = write_inbox(
        "待决定-技术评审.txt",
        "# 技术评审\n方案 A 与方案 B 的缓存策略仍需取舍。\n",
        120,
    )
    write_started(digest, 600)
    write_receipt(
        digest,
        {
            "items": [
                {"id": "A", "summary": "方案 A 缓存"},
                {"id": "B", "summary": "方案 B 缓存"},
                {"id": "C", "summary": "回滚预案"},
            ],
            "followups": [],
            "schema": "v0",
            "note": "legacy receipt without accepted",
        },
    )
    (VAULT / ".meeting-review" / f"{digest}.html").write_text(
        "<!doctype html><meta charset='utf-8'><title>模拟详情</title><p>模拟会议详情，仅用于原型测试。</p>",
        encoding="utf-8",
    )
    scenario("待决定-技术评审", "awaitingDecision", candidates=3, retained=None, hasHTML=True)

    # 4. 已处理：accepted 覆盖全部候选。
    digest = write_inbox(
        "已处理-季度复盘.txt",
        "# 季度复盘\n本季度交付与延期原因复盘。\n",
        900,
    )
    write_receipt(
        digest,
        {
            "items": [{"id": "a"}, {"id": "b"}],
            "accepted": ["a", "b"],
            "followups": [],
            "status": "confirmed",
        },
    )
    scenario("已处理-季度复盘", "processed", candidates=2, retained=2)

    # 5. 冲突：主审与复核保留项不同；status 已确认也不能掩盖分歧。
    digest = write_inbox(
        "冲突-设计对齐.txt",
        "# 设计对齐\n导航层级有两种判断，主审与复核保留项不同。\n",
        200,
    )
    write_started(digest, 300)
    write_receipt(
        digest,
        {
            "items": [{"id": "nav-a"}, {"id": "nav-b"}],
            "accepted": ["nav-a"],
            "review": {
                "items": [{"id": "nav-a"}, {"id": "nav-b"}],
                "accepted": ["nav-a"],
            },
            "recheck": {
                "items": [{"id": "nav-a"}, {"id": "nav-b"}],
                "accepted": ["nav-b"],
            },
            "status": "confirmed",
        },
    )
    scenario("冲突-设计对齐", "awaitingDecision", conflict=True, candidates=2, retained=1)

    # 6. 重复：同内容两个文件，只计一场会议。
    duplicate_text = "# 重复转写\n同一条转写被复制了两次，只应计一场。\n"
    write_inbox("重复-新.txt", duplicate_text, 180)
    write_inbox("重复-旧.txt", duplicate_text, 3600)
    scenario("重复-新", "pending", duplicateCount=1, duplicateFiles=["重复-新.txt", "重复-旧.txt"])

    # 7. 旧回执缺 accepted。
    digest = write_inbox(
        "旧回执-缺字段.txt",
        "# 旧流程回执\n旧版回执只有候选，没有 accepted。\n",
        1200,
    )
    write_receipt(digest, {"items": [{"id": "x"}, {"id": "y"}], "schema": "v0"})
    scenario("旧回执-缺字段", "awaitingDecision", candidates=2, retained=None)

    # 8. 仅有备注的旧回执：阶段与计数均未知。
    digest = write_inbox(
        "旧回执-仅备注.txt",
        "# 更旧的回执\n只有备注字段，无法推出阶段。\n",
        1500,
    )
    write_receipt(digest, {"note": "早期人工记录", "reviewed_by": "legacy"})
    scenario("旧回执-仅备注", "unknown", candidates=None, retained=None)

    # 9. AI 判断无候选。
    digest = write_inbox(
        "无候选.txt",
        "# 例行同步\n本次转写没有可保留候选。\n",
        1800,
    )
    write_receipt(digest, {"items": [], "accepted": [], "status": "done", "no_candidates": True})
    scenario("无候选", "processed", candidates=0, retained=0)

    # 10. 已处理但仍有业务跟进。
    digest = write_inbox(
        "已处理-带跟进.txt",
        "# 预算沟通\n保留两项行动，预算额度仍待业务核实。\n",
        2100,
    )
    write_receipt(
        digest,
        {
            "items": [{"id": "p1"}, {"id": "p2"}],
            "accepted": ["p1", "p2"],
            "followups": [{"id": "f1", "text": "核实预算"}],
            "status": "confirmed",
        },
    )
    scenario("已处理-带跟进", "processed", candidates=2, retained=2, followups=1)

    # 11. 仅 followups 的旧回执：待补充但仍待决定。
    digest = write_inbox(
        "待补充-仅有followups.txt",
        "# 参会人补充\n回执只记录待补充项。\n",
        2400,
    )
    write_receipt(digest, {"followups": ["补充参会人名单"]})
    scenario("待补充-仅有followups", "awaitingDecision", candidates=None, retained=None, followups=1)

    # 12. 损坏回执：状态未知，不得使整个读取失败。
    digest = write_inbox(
        "坏回执.txt",
        "# 损坏回执\n回执 JSON 被截断。\n",
        2700,
    )
    write_receipt(digest, {}, malformed=True)
    scenario("坏回执", "unknown", candidates=None, retained=None, parseError=True)

    # 权限故障库：正常权限，测试脚本会临时 chmod 000。
    if PERMISSION_VAULT.exists():
        shutil.rmtree(PERMISSION_VAULT)
    (PERMISSION_VAULT / "inbox").mkdir(parents=True)
    (PERMISSION_VAULT / ".meeting-review").mkdir(parents=True)
    (PERMISSION_VAULT / "inbox" / "模拟-无权读取.txt").write_text(
        "# 模拟权限故障\n仅用于 chmod 000 测试。\n", encoding="utf-8"
    )

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

    expected = {
        "description": "隔离模拟库，全部内容为虚构样例，仅用于本地测试",
        "inboxFiles": 13,
        "meetings": len(scenarios),
        "counts": counts,
        "scenarios": scenarios,
    }
    (ROOT / "expected.json").write_text(
        json.dumps(expected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"fixture written: {VAULT}")
    print(json.dumps({k: v for k, v in expected.items() if k != "scenarios"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
