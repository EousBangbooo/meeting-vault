#!/usr/bin/env python3
"""Track transcript reviews and user-approved findings in a local vault."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import tempfile
from datetime import date
from pathlib import Path
from urllib.parse import quote


KINDS = {"决策", "待办", "经验候选", "待确认"}
BOARD = "会议处理.md"


def atomic_write(path, text):
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as output:
        temporary = Path(output.name)
        try:
            output.write(text)
            output.close()
            temporary.replace(path)
        finally:
            if temporary.exists():
                temporary.unlink()


def markdown_text(text):
    text = " ".join(text.split())
    return re.sub(r"([\\`*_{}\[\]()#+.!<>|&])", r"\\\1", text)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_path(inbox, name):
    if Path(name).name != name or not name.endswith(".txt"):
        raise ValueError("请指定 inbox 中的 .txt 文件名")
    path = inbox / name
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"未找到转写 {name}")
    return path


def read_review(path):
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return None


def required_text(obj, key):
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{key} 必须是非空文字")
    return value.strip()


def validate_review(data, transcript):
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        raise ValueError("判断记录需要 reviewer、reason 和 items")
    items = []
    for item in data["items"]:
        if not isinstance(item, dict):
            raise ValueError("每条候选需要 kind、statement 和 evidence")
        kind = required_text(item, "kind")
        statement = required_text(item, "statement")
        evidence = required_text(item, "evidence")
        if kind not in KINDS or evidence not in transcript:
            raise ValueError("候选类型无效，或依据不是转写中的连续原文")
        items.append({"kind": kind, "statement": statement, "evidence": evidence})
    return {
        "reviewer": required_text(data, "reviewer"),
        "reason": required_text(data, "reason"),
        "items": items,
    }


def render_board(root, inbox, state):
    counts = {"pending": 0, "confirmation": 0, "done": 0}
    sections = {key: [] for key in counts}
    for source in sorted(inbox.glob("*.txt"), reverse=True):
        if source.is_symlink() or not source.is_file():
            continue
        review = read_review(state / (digest(source) + ".json"))
        link = f"[{markdown_text(source.name)}](inbox/{quote(source.name)})"
        if review is None:
            status = "pending"
            lines = [f"- {link} · 已保存，等你指定 AI 或人工判断"]
        else:
            accepted = review.get("accepted")
            status = "confirmation" if accepted is None else "done"
            if not review["items"]:
                status = "done"
            outcome = (
                "已判断，无可沉淀"
                if not review["items"]
                else "候选待你确认" if accepted is None
                else f"已确认，沉淀 {len(accepted)} 条"
            )
            lines = [
                f"- {link} · {outcome}",
                f"  - 判断人：{markdown_text(review['reviewer'])}",
                f"  - 判断：{markdown_text(review['reason'])}",
            ]
            if accepted:
                lines.append(
                    f"  - [打开已沉淀内容](knowledge/{quote('已确认')}/{digest(source)}.md)"
                )
            for i, item in enumerate(review["items"], start=1):
                label = "待确认"
                if accepted is not None:
                    label = "已沉淀" if i in accepted else "未采纳"
                lines.extend([
                    f"  - {i}. **{item['kind']} · {label}**：{markdown_text(item['statement'])}",
                    f"    - 原文依据：{markdown_text(item['evidence'])}",
                ])
        counts[status] += 1
        sections[status].extend(lines)
    lines = [
        "# 会议处理", "",
        "这里显示剪贴板转写的处理进度、判断人、原文依据和你确认采纳的内容。",
        "候选由你指定的 AI 或人工生成。需要你确认的条目留在下方，确认采纳后才标为已沉淀。",
        "",
    ]
    for key, title in (
        ("pending", "待判断"),
        ("confirmation", "待你确认"),
        ("done", "已处理"),
    ):
        lines.extend([f"## {title}（{counts[key]}）", "", *(sections[key] or ["暂无"]), ""])
    board = root / BOARD
    content = "\n".join(lines)
    if not board.is_file() or board.read_text(encoding="utf-8") != content:
        atomic_write(board, content)
    return counts


def run(args):
    root = Path(args.root).expanduser()
    inbox = root / "inbox"
    state = root / ".meeting-review"
    inbox.mkdir(parents=True, exist_ok=True)
    state.mkdir(mode=0o700, exist_ok=True)
    with (state / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.command in {"record", "confirm"}:
            source = source_path(inbox, args.transcript)
            original = source.read_bytes()
            receipt = state / (hashlib.sha256(original).hexdigest() + ".json")
            existing = read_review(receipt)
            if args.command == "record":
                review = validate_review(
                    json.loads(Path(args.review).read_text(encoding="utf-8")),
                    original.decode("utf-8-sig"),
                )
                if existing is not None and any(
                    existing[key] != value for key, value in review.items()
                ):
                    raise ValueError("该转写已有判断记录，请先查看会议处理页")
                if existing is None:
                    atomic_write(receipt, json.dumps(review, ensure_ascii=False, indent=2))
            elif existing is None or not existing["items"]:
                raise ValueError("该转写没有待确认候选")
            else:
                accepted = sorted(set(args.items))
                if any(i < 1 or i > len(existing["items"]) for i in accepted):
                    raise ValueError("候选编号超出范围")
                if any(existing["items"][i - 1]["kind"] == "待确认" for i in accepted):
                    raise ValueError("待确认项缺少确定结论，不能采纳")
                if "accepted" in existing and existing["accepted"] != accepted:
                    raise ValueError("该转写已完成确认")
                existing["accepted"] = accepted
                if accepted:
                    knowledge = root / "knowledge" / "已确认"
                    knowledge.mkdir(parents=True, exist_ok=True)
                    lines = [
                        "# 已确认的会议判断", "",
                        f"来源：[转写](../../inbox/{quote(source.name)})",
                        f"判断人：{markdown_text(existing['reviewer'])}", "",
                    ]
                    for i in accepted:
                        item = existing["items"][i - 1]
                        lines.extend([
                            f"## {item['kind']}", "",
                            markdown_text(item["statement"]), "",
                            f"原文依据：{markdown_text(item['evidence'])}", "",
                        ])
                    atomic_write(knowledge / (receipt.stem + ".md"), "\n".join(lines))
                atomic_write(receipt, json.dumps(existing, ensure_ascii=False, indent=2))
        counts = render_board(root, inbox, state)
        summary = f"{counts['pending']} 场待判断，{counts['confirmation']} 场待你确认"
        if args.command == "remind":
            marker = state / "last-reminder"
            today = date.today().isoformat()
            if (counts["pending"] or counts["confirmation"]) and (
                not marker.exists() or marker.read_text(encoding="utf-8") != today
            ):
                atomic_write(marker, today)
                print(f"{summary}。打开会议库中的「{BOARD}」。")
        else:
            print(f"{summary}。查看 {root / BOARD}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=os.environ.get("MEETING_KB") or "~/MeetingVault")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="刷新并显示会议处理页")
    commands.add_parser("remind", help="每日本机第一次有待处理会议时输出提醒")
    record = commands.add_parser("record", help="保存 AI 或人工的判断记录")
    record.add_argument("transcript", help="inbox 内转写文件名")
    record.add_argument("review", help="判断 JSON 文件路径")
    confirm = commands.add_parser("confirm", help="确认采纳选中的候选")
    confirm.add_argument("transcript", help="inbox 内转写文件名")
    confirm.add_argument("items", nargs="*", type=int, help="采纳的编号，留空表示全部跳过")
    args = parser.parse_args()
    try:
        run(args)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"会议处理失败：{exc}\n")


if __name__ == "__main__":
    main()
