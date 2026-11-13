#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""reindex.py — 以 raw/meetings 为唯一事实源，重建会议索引。

用法:
    python3 bin/reindex.py --root ~/MeetingVault --out ~/MeetingVault/index
    python3 bin/reindex.py --root . --out ./index --no-split   # 面试不单独拆出

产出:
    会议索引.md / 会议索引.csv / 盘点报告.md / 非会议记录.md
"""
import argparse
import collections
import csv
import hashlib
import os
import re

SPK = re.compile(r'^\s*([^\s].{0,20}?)\s{2,}\d{1,2}:\d{2}(?::\d{2})?\s*$', re.M)

DATE_PATTERNS = [
    (re.compile(r'^(\d{4})-(\d{2})-(\d{2})'), lambda m: f"{m[1]}-{m[2]}-{m[3]}"),
    (re.compile(r'^(\d{4})\.(\d{1,2})\.(\d{1,2})'), lambda m: f"{m[1]}-{int(m[2]):02d}-{int(m[3]):02d}"),
    (re.compile(r'^(\d{4})-(\d{2})\.(\d{1,2})'), lambda m: f"{m[1]}-{m[2]}-{int(m[3]):02d}"),
    (re.compile(r'^(\d{1,2})\.(\d{1,2})[-_]'), lambda m: f"{__import__('datetime').date.today().year}-{int(m[1]):02d}-{int(m[2]):02d}"),
]

INTERVIEW_NAME = re.compile(r'面试|interview|candidate', re.I)
INTERVIEW_HEAD = re.compile(r'求职者|候选人|面试官|interviewer|applicant', re.I)


def parse_name(path):
    base = os.path.basename(path)
    for pat, build in DATE_PATTERNS:
        m = pat.match(base)
        if m:
            topic = base[m.end():].lstrip('-_ ')
            return build(m), re.sub(r'\.txt$', '', topic).strip()
    return None, re.sub(r'\.txt$', '', base).strip()


def scan(root):
    src = os.path.join(root, 'raw', 'meetings')
    if not os.path.isdir(src):
        raise SystemExit(f"not found: {src}")
    rows = []
    for name in sorted(os.listdir(src)):
        if not name.endswith('.txt'):
            continue
        path = os.path.join(src, name)
        raw = open(path, 'rb').read()
        text = raw.decode('utf-8-sig', 'ignore').replace('\r', '')
        date, topic = parse_name(path)
        head = text.strip().splitlines()[0][:60] if text.strip() else ''
        rows.append(dict(
            date=date, name=name, rel=os.path.relpath(path, root),
            topic=topic or '(untitled)',
            chars=len(text), lines=text.count('\n') + 1,
            speakers=len(set(SPK.findall(text))),
            sha=hashlib.sha256(raw).hexdigest(),
            head=head,
            interview=bool(INTERVIEW_NAME.search(name)) or bool(INTERVIEW_HEAD.search(head)),
        ))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True, help='vault root (contains raw/meetings)')
    ap.add_argument('--out', required=True, help='output directory')
    ap.add_argument('--no-split', action='store_true', help='keep interviews in the main index')
    a = ap.parse_args()

    scanned = scan(a.root)
    undated = [r for r in scanned if not r['date']]
    allrows = [r for r in scanned if r['date']]
    if a.no_split:
        rows, others = allrows, []
    else:
        rows = [r for r in allrows if not r['interview']]
        others = [r for r in allrows if r['interview']]
    rows.sort(key=lambda r: (r['date'], r['name']), reverse=True)
    others.sort(key=lambda r: (r['date'], r['name']), reverse=True)
    os.makedirs(a.out, exist_ok=True)

    with open(os.path.join(a.out, '会议索引.csv'), 'w', newline='', encoding='utf-8-sig') as fh:
        w = csv.DictWriter(fh, fieldnames=['date', 'topic', 'name', 'chars', 'lines', 'speakers', 'sha', 'rel'])
        w.writeheader()
        for r in rows:
            w.writerow({k: r[k] for k in w.fieldnames})

    md = ['# 会议索引', '',
          f'由 `raw/meetings` 自动生成，共 **{len(rows)}** 份。不要手工编辑——改完文件重跑 `reindex.py`。', '']
    if others:
        md += [f'> 另有 {len(others)} 份非会议记录（面试等），见 `非会议记录.md`。', '']
    md += ['| 日期 | 主题 | 字数 | 行数 | 说话人 | 指纹 | 文件 |',
           '|---|---|---:|---:|---:|---|---|']
    for r in rows:
        md.append(f"| {r['date']} | {r['topic']} | {r['chars']:,} | {r['lines']} | {r['speakers']} | `{r['sha'][:8]}` | `{r['name']}` |")
    open(os.path.join(a.out, '会议索引.md'), 'w', encoding='utf-8').write('\n'.join(md) + '\n')

    if others:
        od = ['# 非会议记录', '',
              '面试、候选人沟通等，**不进知识库、不做提炼**，只为留存和回查。', '',
              '| 日期 | 标题 | 字数 | 文件 |', '|---|---|---:|---|']
        od += [f"| {r['date']} | {r['topic']} | {r['chars']:,} | `{r['name']}` |" for r in others]
        open(os.path.join(a.out, '非会议记录.md'), 'w', encoding='utf-8').write('\n'.join(od) + '\n')

    else:
        with open(os.path.join(a.out, '非会议记录.md'), 'w', encoding='utf-8') as fh:
            fh.write('# 非会议记录\n\n本次未识别到非会议记录。自动识别可能遗漏，需人工复核。\n')

    by_month = collections.Counter(r['date'][:7] for r in rows)
    dups = collections.defaultdict(list)
    for r in rows:
        dups[r['sha']].append(r['name'])
    dup = {k: v for k, v in dups.items() if len(v) > 1}
    multi = {d: c for d, c in collections.Counter(r['date'] for r in rows).items() if c > 1}
    short = [r for r in rows if r['chars'] < 800]
    no_topic = [r for r in rows if r['topic'] == '(untitled)']
    bad_name = [r for r in rows if not re.match(r'^\d{4}-\d{2}-\d{2}-', r['name'])]

    rep = ['# 盘点报告', '',
           f'- 会议总数：**{len(rows)}**',
           f'- 非会议记录：**{len(others)}**',
           '- 月份分布：' + ('，'.join(f'{k} {v}' for k, v in sorted(by_month.items())) or '—'),
           f'- 内容重复：**{len(dup)}** 组',
           f'- 同一天多场：**{len(multi)}** 天，共 {sum(multi.values())} 场',
           f'- 疑似空转写（<800 字）：**{len(short)}**',
           f'- 文件名无主题：**{len(no_topic)}**',
           f'- 命名不规范：**{len(bad_name)}**',
           f'- 无法识别日期（未进入索引）：**{len(undated)}**',
           '']
    if undated:
        rep += ['## 无法识别日期', ''] + [f"- `{r['name']}`" for r in undated] + ['']
    if dup:
        rep += ['## 内容重复', ''] + [f"- `{v[0]}` = {v}" for v in dup.values()] + ['']
    if short:
        rep += ['## 疑似空转写', ''] + [f"- {r['date']} `{r['name']}`（{r['chars']} 字）" for r in short] + ['']
    if no_topic:
        rep += ['## 缺主题', ''] + [f"- `{r['name']}` → 首句：{r['head'] or '（空）'}" for r in no_topic] + ['']
    if bad_name:
        rep += ['## 命名不规范（建议 YYYY-MM-DD-主题.txt）', ''] + [f"- `{r['name']}`" for r in bad_name] + ['']
    open(os.path.join(a.out, '盘点报告.md'), 'w', encoding='utf-8').write('\n'.join(rep) + '\n')

    print(f"indexed {len(rows)} meetings -> {a.out}")
    print(f"dups {len(dup)}, short {len(short)}, no-topic {len(no_topic)}, bad-name {len(bad_name)}")


if __name__ == '__main__':
    main()
