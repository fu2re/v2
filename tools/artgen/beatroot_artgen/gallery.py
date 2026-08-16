"""Последняя ступень: страница для ревью всей графики глазами.

Одна самодостаточная HTML-страница — картинки внутри неё, а не рядом. Так её
можно открыть где угодно и отправить кому угодно, ничего не потеряв по дороге.

Что показывается и почему именно это:

* **1x рядом с 4x.** Увеличенный кандидат врёт: в HD-пикселе половина брака
  видна только в честном размере, а половина — только в увеличенном.
* **Три фона.** Тёмный, светлый и притемнённый фон боя. Ассет, читаемый на
  одном, регулярно пропадает на другом, и в игре встречаются все три.
* **Squint-тест.** Уменьшено до 30% и размыто — проверка из GDD §11.1.1.
  Если на нём силуэт исчез, в бою на телефоне его тоже не будет.
* **Что сказали ворота и что сказал Клод.** Решение принимается зная обе оценки,
  а не вместо них.

Страница ничего не пишет на диск: браузер не имеет на это права. Она собирает
готовую команду `artgen promote`, которую остаётся скопировать и выполнить.
"""

from __future__ import annotations

import base64
import html
import io
import json
from pathlib import Path

from PIL import Image, ImageFilter

from . import review
from .manifest import Asset, display_names
from .metrics import battle_backdrop
from .palette import ENVIRONMENT
from .color import hex_to_rgb


def _data_uri(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def _squint(img: Image.Image, backdrop: tuple[int, int, int]) -> Image.Image:
    """Тот же тест, что в воротах, но для глаза: после размытия возвращаем
    масштаб, иначе на странице получится марка размером с ноготь."""
    scene = Image.new("RGBA", img.size, backdrop + (255,))
    scene.alpha_composite(img.convert("RGBA"))
    small = scene.resize(
        (max(int(img.width * 0.3), 4), max(int(img.height * 0.3), 4)), Image.BOX
    ).filter(ImageFilter.GaussianBlur(radius=1.0))
    return small.resize(img.size, Image.NEAREST).convert("RGB")


def _asset_block(asset: Asset, report: dict | None, verdict: dict | None,
                 title: str, root: Path, decision: dict | None = None) -> str:
    backdrop = battle_backdrop()

    # Принятое человеком считается закрытым и по умолчанию не показывается.
    # Повторно предлагать одобренное — значит заставлять пересматривать одно
    # и то же на каждой итерации; в следующий круг попадает только несмотренное.
    settled = bool(decision and decision.get("status") == "принят")

    if report is None:
        reason = html.escape(asset.note) if asset.note else "кандидатов ещё нет"
        state = "handmade" if not asset.generated else "empty"
        return (
            f'<section class="asset {state}" data-id="{html.escape(asset.id)}" '
            f'data-kind="{html.escape(asset.kind.name)}" data-state="{state}">'
            f'<header><h2>{html.escape(title)}</h2>'
            f'<span class="id">{html.escape(asset.id)}</span>'
            f'<span class="kind">{html.escape(asset.kind.name)}</span></header>'
            f'<p class="empty-note">{reason}</p></section>'
        )

    directory = asset.candidates_dir(root)
    chosen = (verdict or {}).get("chosen")
    variants_html: list[str] = []

    # Принятый младший грейд идёт первой карточкой и не выбирается: он уже
    # в игре. Без него старший грейд не с чем сравнить, и «тот же зверь или
    # уже другой» решается на глаз без опоры.
    base = review.reference_image(asset, root)
    if base is not None:
        uri = _data_uri(base)
        zoom = min(4, max(1, 384 // max(base.width, base.height)))
        variants_html.append(f"""
        <div class="variant base" style="--img:url('{uri}')">
          <div class="shots">
            <div class="shot dark"><i style="width:{base.width * zoom}px;height:{base.height * zoom}px"></i></div>
            <div class="shot battle"><i style="width:{base.width * zoom}px;height:{base.height * zoom}px"></i></div>
            <div class="shot true"><i style="width:{base.width}px;height:{base.height}px"></i></div>
          </div>
          <div class="vmeta"><span class="baselabel">основа: {html.escape(asset.previous_grade_id() or "")}</span></div>
        </div>""")

    for v in report["variants"]:
        path = directory / v["image"]
        if not path.exists():
            continue
        img = Image.open(path).convert("RGBA")
        uri = _data_uri(img)
        squint = _data_uri(_squint(img, backdrop))

        failed = [c for c in v["checks"] if not c["ok"]]
        badges = "".join(
            f'<span class="badge {"fail" if c["severity"] == "провал" else "warn"}" '
            f'title="{html.escape(c["detail"])}">{html.escape(c["name"])}</span>'
            for c in failed
        ) or '<span class="badge ok">ворота пройдены</span>'

        is_chosen = "chosen" if v["variant"] == chosen else ""
        gate = "gate-pass" if v["passed"] else "gate-fail"
        zoom = min(4, max(1, 384 // max(img.width, img.height)))
        big = f"width:{img.width * zoom}px;height:{img.height * zoom}px"
        true = f"width:{img.width}px;height:{img.height}px"

        # Картинка вшивается в переменную CSS, а не в пять тегов <img>: один
        # и тот же ассет показан на трёх фонах и в двух масштабах, и пять копий
        # base64 раздували бы страницу впятеро. На полянах 480×480 это мегабайты.
        variants_html.append(f"""
        <div class="variant {is_chosen} {gate}" data-variant="{html.escape(v["variant"])}"
             style="--img:url('{uri}');--squint:url('{squint}')">
          <div class="shots">
            <div class="shot dark"><i style="{big}"></i></div>
            <div class="shot light"><i style="{big}"></i></div>
            <div class="shot battle"><i style="{big}"></i></div>
            <div class="shot true"><i style="{true}"></i></div>
            <div class="shot squint"><i class="sq" style="{big}"></i></div>
          </div>
          <div class="vmeta">
            <button class="pick" data-variant="{html.escape(v["variant"])}">вариант {html.escape(v["variant"])}</button>
            <div class="badges">{badges}</div>
          </div>
        </div>""")

    if verdict:
        status = verdict["status"]
        cls = {"принять": "ok", "принять с правкой": "warn"}.get(status, "fail")
        claude = (
            f'<div class="claude {cls}"><b>Клод: {html.escape(status)}</b>'
            f'<span>{html.escape(verdict.get("note", ""))}</span></div>'
        )
    else:
        claude = '<div class="claude none">Клод ещё не смотрел</div>'

    if settled:
        settled_mark = (
            f'<span class="settled">уже в игре — вариант '
            f'{html.escape(str(decision.get("variant", "?")))}</span>'
        )
    else:
        settled_mark = ""

    return f"""
    <section class="asset{' settled' if settled else ''}" data-id="{html.escape(asset.id)}"
             data-kind="{html.escape(asset.kind.name)}" data-state="ready"
             data-settled="{'1' if settled else '0'}">
      <header>
        <h2>{html.escape(title)}</h2>
        <span class="id">{html.escape(asset.id)}</span>
        <span class="kind">{html.escape(asset.kind.name)}</span>
        {settled_mark}
        <div class="decision">
          <button class="accept" data-act="accept">принять</button>
          <button class="reject" data-act="reject">переделать</button>
        </div>
      </header>
      {claude}
      <p class="prompt">{html.escape(report.get("prompt", ""))}</p>
      <div class="variants">{"".join(variants_html)}</div>
    </section>"""


def build(assets: list[Asset], root: Path, out: Path) -> Path:
    from .promote import load_decisions

    verdicts = review.load_verdicts(root)
    decisions = load_decisions(root)
    names = display_names(root)
    backdrop = battle_backdrop()
    paper = hex_to_rgb(ENVIRONMENT["warm"][4])

    blocks: list[str] = []
    for asset in assets:
        report = review.load_report(asset, root)
        # Имя игрока плюс грейд: `bass_bear_epic` ничего не говорит, а
        # «Топотун — Эпический» говорит сразу
        title = names.get(asset.base_id, asset.base_id)
        if asset.grade is not None:
            title = f"{title} — {asset.grade.name}"
        blocks.append(_asset_block(asset, report, verdicts.get(asset.id), title, root,
                                   decisions.get(asset.id)))

    ready = sum(1 for a in assets if review.load_report(a, root))
    settled = sum(1 for a in assets if decisions.get(a.id, {}).get("status") == "принят")
    counts = {
        "всего в игре": len(assets),
        "генерируется": sum(1 for a in assets if a.generated),
        "уже в игре": settled,
        "ждут решения": ready - settled,
    }
    stats = "".join(f"<span><b>{v}</b>{html.escape(k)}</span>" for k, v in counts.items())

    page = _TEMPLATE.format(
        stats=stats,
        blocks="".join(blocks),
        battle="rgb({},{},{})".format(*backdrop),
        paper="rgb({},{},{})".format(*paper),
        kinds=json.dumps(sorted({a.kind.name for a in assets}), ensure_ascii=False),
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page, encoding="utf-8")
    return out


_TEMPLATE = """<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BEATROOT — ревью графики</title>
<style>
  :root {{
    --bg: #16130f; --panel: #1f1b16; --line: #342d24; --ink: #e8ddcb;
    --muted: #9b8d78; --ok: #57C46A; --warn: #d8a13a; --fail: #e0604f;
    --battle: {battle}; --paper: {paper};
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--ink);
    font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }}
  header.top {{ position: sticky; top: 0; z-index: 10; background: var(--panel);
    border-bottom: 1px solid var(--line); padding: 12px 20px; }}
  h1 {{ margin: 0 0 8px; font-size: 18px; letter-spacing: .04em; }}
  .stats {{ display: flex; gap: 18px; flex-wrap: wrap; color: var(--muted); font-size: 13px; }}
  .stats b {{ color: var(--ink); margin-right: 6px; font-size: 15px; }}
  .controls {{ display: flex; gap: 8px; flex-wrap: wrap; margin-top: 10px; }}
  .controls button, .controls select {{ background: #2a241d; color: var(--ink);
    border: 1px solid var(--line); border-radius: 6px; padding: 5px 10px;
    font-size: 13px; cursor: pointer; }}
  .controls button.on {{ border-color: var(--ok); color: var(--ok); }}
  main {{ padding: 20px; display: flex; flex-direction: column; gap: 18px; }}
  .asset {{ background: var(--panel); border: 1px solid var(--line);
    border-radius: 10px; padding: 14px 16px; }}
  .asset.accepted {{ border-color: var(--ok); }}
  .asset.rejected {{ border-color: var(--fail); opacity: .65; }}
  .asset > header {{ display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }}
  .asset h2 {{ margin: 0; font-size: 16px; }}
  .id, .kind {{ font-size: 12px; color: var(--muted); }}
  .kind {{ border: 1px solid var(--line); border-radius: 999px; padding: 1px 8px; }}
  .decision {{ margin-left: auto; display: flex; gap: 6px; }}
  .decision button {{ border: 1px solid var(--line); background: #2a241d;
    color: var(--ink); border-radius: 6px; padding: 4px 12px; cursor: pointer; font-size: 13px; }}
  .decision button.on[data-act=accept] {{ background: var(--ok); color: #12200f; border-color: var(--ok); }}
  .decision button.on[data-act=reject] {{ background: var(--fail); color: #2a0f0b; border-color: var(--fail); }}
  .prompt {{ color: var(--muted); font-size: 12px; margin: 8px 0 10px; }}
  .claude {{ font-size: 13px; margin-top: 8px; padding: 6px 10px; border-radius: 6px;
    border-left: 3px solid var(--line); background: #241f19; }}
  .claude span {{ color: var(--muted); margin-left: 8px; }}
  .claude.ok {{ border-left-color: var(--ok); }}
  .claude.warn {{ border-left-color: var(--warn); }}
  .claude.fail {{ border-left-color: var(--fail); }}
  .claude.none {{ color: var(--muted); }}
  .variants {{ display: flex; gap: 14px; flex-wrap: wrap; }}
  .variant {{ border: 1px solid var(--line); border-radius: 8px; padding: 8px; }}
  .variant.chosen {{ border-color: var(--ok); box-shadow: 0 0 0 1px var(--ok) inset; }}
  .variant.gate-fail {{ opacity: .55; }}
  .variant.base {{ border-color: var(--warn); border-style: dashed;
    margin-right: 8px; border-right-width: 3px; }}
  .baselabel {{ font-size: 12px; color: var(--warn); }}
  .shots {{ display: flex; gap: 6px; align-items: flex-end; flex-wrap: wrap; max-width: 100%; }}
  .shot {{ display: flex; align-items: center; justify-content: center;
    border-radius: 4px; padding: 6px; }}
  .shot i {{ display: block; background-image: var(--img); background-size: 100% 100%;
    background-repeat: no-repeat; image-rendering: pixelated; max-width: 100%; }}
  .shot i.sq {{ background-image: var(--squint); }}
  .shot.dark {{ background: #14110d; }}
  .shot.light {{ background: var(--paper); }}
  .shot.battle {{ background: var(--battle); }}
  .shot.true {{ background: var(--battle); }}
  .shot.squint {{ background: var(--battle); }}
  .vmeta {{ display: flex; align-items: center; gap: 8px; margin-top: 6px; flex-wrap: wrap; }}
  .pick {{ background: #2a241d; color: var(--ink); border: 1px solid var(--line);
    border-radius: 6px; padding: 3px 10px; font-size: 12px; cursor: pointer; }}
  .variant.chosen .pick {{ border-color: var(--ok); color: var(--ok); }}
  .badges {{ display: flex; gap: 5px; flex-wrap: wrap; }}
  .badge {{ font-size: 11px; padding: 1px 7px; border-radius: 999px;
    border: 1px solid var(--line); color: var(--muted); cursor: help; }}
  .badge.fail {{ color: var(--fail); border-color: var(--fail); }}
  .badge.warn {{ color: var(--warn); border-color: var(--warn); }}
  .badge.ok {{ color: var(--ok); border-color: var(--ok); }}
  .empty-note {{ color: var(--muted); font-size: 13px; margin: 8px 0 0; }}
  .asset.handmade {{ opacity: .6; }}
  .asset.settled {{ opacity: .5; }}
  .settled {{ font-size: 12px; color: var(--ok); border: 1px solid var(--ok);
    border-radius: 999px; padding: 1px 8px; }}
  .nothing {{ color: var(--muted); text-align: center; padding: 40px 20px; margin: 0; }}
  .nothing code {{ color: var(--ink); }}
  footer.bar {{ position: sticky; bottom: 0; background: var(--panel);
    border-top: 1px solid var(--line); padding: 12px 20px; }}
  footer code {{ display: block; background: #14110d; border: 1px solid var(--line);
    border-radius: 6px; padding: 10px; font-size: 12px; white-space: pre-wrap;
    word-break: break-all; color: var(--ink); max-height: 130px; overflow: auto; }}
  footer .row {{ display: flex; gap: 10px; align-items: center; margin-bottom: 8px; }}
  footer button {{ background: var(--ok); color: #12200f; border: 0; border-radius: 6px;
    padding: 6px 14px; font-weight: 600; cursor: pointer; }}
  .hidden {{ display: none; }}
</style></head>
<body>
<header class="top">
  <h1>BEATROOT — ревью графики</h1>
  <div class="stats">{stats}</div>
  <div class="controls">
    <button data-filter="pending" class="on">ждут решения</button>
    <button data-filter="all">все, включая принятое</button>
    <button data-filter="gate-fail">с провалом ворот</button>
    <select id="kind"><option value="">любой вид</option></select>
  </div>
</header>
<main><p id="empty" class="nothing hidden">Всё решено — ждать нечего.
Перегенерируй отклонённое (<code>artgen batch</code>) или посмотри принятое кнопкой выше.</p>{blocks}</main>
<footer class="bar">
  <div class="row">
    <button id="copy">скопировать команду</button>
    <span id="tally" class="stats"></span>
  </div>
  <code id="cmd">решений пока нет</code>
</footer>
<script>
const KINDS = {kinds};
const kindSel = document.getElementById('kind');
KINDS.forEach(k => {{ const o = document.createElement('option'); o.value = k; o.textContent = k; kindSel.append(o); }});

const state = {{}};  // id -> {{act, variant}}

document.querySelectorAll('.asset[data-state=ready]').forEach(sec => {{
  const id = sec.dataset.id;
  // Карточка основы не выбирается: она уже в игре и служит только для сравнения
  const first = sec.querySelector('.variant.chosen') || sec.querySelector('.variant.gate-pass')
    || sec.querySelector('.variant:not(.base)');
  state[id] = {{ act: null, variant: first ? first.dataset.variant : null }};

  sec.querySelectorAll('.pick').forEach(btn => btn.addEventListener('click', () => {{
    sec.querySelectorAll('.variant').forEach(v => v.classList.remove('chosen'));
    btn.closest('.variant').classList.add('chosen');
    state[id].variant = btn.dataset.variant;
    render();
  }}));

  sec.querySelectorAll('.decision button').forEach(btn => btn.addEventListener('click', () => {{
    const act = btn.dataset.act;
    state[id].act = state[id].act === act ? null : act;
    sec.querySelectorAll('.decision button').forEach(b => b.classList.toggle('on', b.dataset.act === state[id].act));
    sec.classList.toggle('accepted', state[id].act === 'accept');
    sec.classList.toggle('rejected', state[id].act === 'reject');
    render();
  }}));
}});

function render() {{
  const picks = [], rejects = [];
  for (const [id, s] of Object.entries(state)) {{
    if (s.act === 'accept' && s.variant !== null) picks.push(`--pick ${{id}}=${{s.variant}}`);
    if (s.act === 'reject') rejects.push(`--reject ${{id}}`);
  }}
  const cmd = document.getElementById('cmd');
  cmd.textContent = (picks.length || rejects.length)
    ? ['uv run artgen promote', ...picks, ...rejects].join(' ')
    : 'решений пока нет';
  document.getElementById('tally').innerHTML =
    `<span><b>${{picks.length}}</b>принять</span><span><b>${{rejects.length}}</b>переделать</span>`;
}}

document.getElementById('copy').addEventListener('click', async () => {{
  const text = document.getElementById('cmd').textContent;
  try {{ await navigator.clipboard.writeText(text); }}
  catch {{
    // Буфер обмена недоступен без защищённого контекста — выделяем, копирует человек
    const r = document.createRange(); r.selectNode(document.getElementById('cmd'));
    getSelection().removeAllRanges(); getSelection().addRange(r);
  }}
}});

// По умолчанию показывается только то, что ещё не решено. Уже принятое лежит
// в игре, и пересматривать его на каждой итерации незачем — оно доступно
// отдельной кнопкой, если понадобится передумать.
let filter = 'pending';
function applyFilters() {{
  const kind = kindSel.value;
  let shown = 0;
  document.querySelectorAll('.asset').forEach(sec => {{
    const id = sec.dataset.id;
    let show = true;
    if (kind && sec.dataset.kind !== kind) show = false;
    if (filter === 'pending' && (sec.dataset.state !== 'ready'
        || sec.dataset.settled === '1' || (state[id] && state[id].act))) show = false;
    if (filter === 'gate-fail' && !sec.querySelector('.variant.gate-fail')) show = false;
    sec.classList.toggle('hidden', !show);
    if (show) shown++;
  }});
  document.getElementById('empty').classList.toggle('hidden', shown > 0);
}}
document.querySelectorAll('.controls button[data-filter]').forEach(b => b.addEventListener('click', () => {{
  document.querySelectorAll('.controls button[data-filter]').forEach(x => x.classList.remove('on'));
  b.classList.add('on'); filter = b.dataset.filter; applyFilters();
}}));
kindSel.addEventListener('change', applyFilters);
render();
// Обязательно на загрузке: фильтр по умолчанию не «все», и без этого вызова
// страница открылась бы со всем списком, включая уже принятое
applyFilters();
</script>
</body></html>
"""
