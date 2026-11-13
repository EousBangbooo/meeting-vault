"""Generate an offline browser view of the meeting review queue."""

from html import escape
from urllib.parse import quote


LABELS = {
    "pending": "未启动判断",
    "started": "已启动，等结果",
    "confirmation": "待你确认",
    "conflict": "判断有分歧",
    "done": "已处理",
}


def render_opinion(review, accepted=None):
    reviewer = escape(review["reviewer"])
    model = escape(review.get("model", "模型未注明"))
    reason = escape(review["reason"])
    parts = [f"<p><strong>{reviewer}</strong> · {model}</p><p>{reason}</p>"]
    if not review["items"]:
        parts.append("<p>这份判断没有提出候选。</p>")
    for number, item in enumerate(review["items"], 1):
        label = "" if accepted is None else " · 已沉淀" if number in accepted else " · 未采纳"
        parts.append(
            f"<p><strong>{number}. {escape(item['kind'])}{label}</strong> "
            f"{escape(item['statement'])}</p><blockquote>{escape(item['evidence'])}</blockquote>"
        )
    return "".join(parts)


def render_meeting(root, entry):
    name = entry["name"]
    status = entry["status"]
    path = "inbox/" + quote(name)
    detail = [f'<p><a href="{path}">打开转写</a></p>']
    if status in {"pending", "started"}:
        if status == "started":
            detail.append(f"<p>接单时间 {escape(entry['started'])}。等待审阅记录返回。</p>")
            detail.append("<p>如果上次审阅已中断，可以用同一条指令继续。</p>")
        instruction = (
            "按 docs/review-guide.md 审阅这 1 场会议。"
            f"会议库：{root}。文件：inbox/{name}"
        )
        detail.append(
            '<p>在 Meeting Vault 仓库打开能读取本地文件的 AI，发送这句指令。</p>'
            f'<textarea readonly rows="2" aria-label="AI 审阅指令">{escape(instruction)}</textarea>'
            '<button type="button" data-copy>复制审阅指令</button><span role="status"></span>'
        )
    else:
        if entry["second"]:
            detail.append("<h4>第一份判断</h4>")
            detail.append(render_opinion(
                entry["review"],
                entry["review"].get("accepted") if entry["resolution"] != 2 else None,
            ))
            detail.append("<h4>第二份判断</h4>")
            detail.append(render_opinion(
                entry["second"],
                entry["review"].get("accepted") if entry["resolution"] == 2 else None,
            ))
            if status == "conflict":
                detail.append("<p>请对照原文选择采用第 1 或第 2 份判断，再确认要沉淀的候选。</p>")
            elif entry["resolution"]:
                detail.append(f"<p>已选择第 {entry['resolution']} 份判断。</p>")
        else:
            detail.append(render_opinion(entry["active"], entry["review"].get("accepted")))
        if entry["review"].get("accepted"):
            url = f"knowledge/{quote('已确认')}/{entry['sha']}.md"
            detail.append(f'<p><a href="{url}">打开已沉淀内容</a></p>')
    opened = " open" if status in {"pending", "conflict"} else ""
    return (
        f'<details{opened}><summary>{escape(name)}</summary>'
        f'<div class="detail">{"".join(detail)}</div></details>'
    )


def render_html(root, entries, counts, statuses, has_preferences):
    metrics = "".join(
        f'<a class="metric {key}" href="#{key}"><strong>{counts[key]}</strong>'
        f'<span>{LABELS[key]}</span></a>' for key in statuses
    )
    sections = []
    for key in statuses:
        meetings = [render_meeting(root, entry) for entry in entries if entry["status"] == key]
        sections.append(
            f'<section id="{key}"><h2>{LABELS[key]} <span>{counts[key]}</span></h2>'
            f'{"".join(meetings) or "<p>暂无会议</p>"}</section>'
        )
    preferences = (
        f'<p><a href="{quote("审阅偏好.md")}">查看我的审阅偏好</a>。可随时修改。</p>'
        if has_preferences else
        "<p><strong>第一次用？</strong> 从下方选一场试审。看完候选再指出"
        "「哪条值得以后提醒，哪条可以跳过」。确认过的偏好会保存在自己的会议库。</p>"
    )
    return f"""<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>会议处理 · Meeting Vault</title>
<style>
:root {{ color-scheme: light; font-family: system-ui, sans-serif; background: #f4f6f9; color: #182331; }}
body {{ max-width: 920px; margin: 0 auto; padding: 24px; }}
h1 {{ font-size: 2.3rem; margin: .25em 0; }}
p {{ line-height: 1.65; overflow-wrap: anywhere; }}
header p {{ color: #475569; }}
a {{ color: #1559a4; }}
nav {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; margin: 24px 0; }}
.metric {{ border: 1px solid #ced8e3; border-radius: 12px; background: white; padding: 14px;
  text-decoration: none; color: #182331; border-top: 4px solid #677b92; }}
.metric strong, .metric span {{ display: block; }}
.metric strong {{ font-size: 2rem; }}
.metric.pending {{ border-top-color: #2768a8; }}
.metric.conflict, .metric.confirmation {{ border-top-color: #b66b18; }}
.metric.done {{ border-top-color: #288054; }}
section {{ margin: 24px 0; }}
h2 {{ font-size: 1.15rem; }}
h2 span {{ color: #475569; margin-left: 5px; }}
details {{ border: 1px solid #ced8e3; border-radius: 10px; background: white; margin: 8px 0; }}
summary {{ cursor: pointer; padding: 12px 16px; overflow-wrap: anywhere; }}
.detail {{ padding: 0 16px 14px; }}
blockquote {{ margin: 0 0 12px; padding: 8px 12px; border-left: 3px solid #9bacc0; background: #f4f6f9; overflow-wrap: anywhere; }}
textarea {{ box-sizing: border-box; display: block; width: 100%; font: inherit; padding: 9px; color: inherit; background: #f4f6f9; border: 1px solid #a4b2c2; border-radius: 6px; }}
button {{ font: inherit; cursor: pointer; border: 1px solid #2768a8; color: #1559a4; background: white; border-radius: 6px; padding: 5px 10px; margin: 8px 8px 0 0; }}
:focus-visible {{ outline: 3px solid #2768a8; outline-offset: 2px; }}
</style>
<header><h1>会议处理</h1><p>查看还有多少场需要启动判断，以及哪些判断需要你确认。文件有更新时，可刷新页面。</p>
{preferences}
<button type="button" id="reload">刷新</button> <a href="{quote('会议处理.md')}">Markdown 版</a></header>
<nav aria-label="会议状态">{metrics}</nav>
<main>{"".join(sections)}</main>
<script>
document.querySelector('#reload').addEventListener('click', () => location.reload());
for (const button of document.querySelectorAll('[data-copy]')) {{
  button.addEventListener('click', async () => {{
    const field = button.previousElementSibling;
    const status = button.nextElementSibling;
    try {{
      await navigator.clipboard.writeText(field.value);
      status.textContent = '已复制';
    }} catch {{
      field.select();
      status.textContent = '请按系统复制快捷键';
    }}
  }});
}}
</script>
</html>
"""
