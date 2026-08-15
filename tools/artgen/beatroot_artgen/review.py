"""Первая ступень ревью: контакт-листы и вердикты.

Ворота (`metrics.py`) отсеивают механический брак — невырезанный фон, обрезанный
силуэт, крошево. Дальше начинается то, что арифметикой не берётся: похож ли зверь
на медведя, добрый ли у него взгляд, годится ли это для семи лет, какой из четырёх
вариантов лучше. Это смотрит Клод по контакт-листу.

Лист собирается на фоне боя и увеличен вчетверо намеренно. Кандидат, разглядываемый
на белом и в стократном зуме, всегда выглядит лучше, чем в игре, — и решение,
принятое по такой картинке, приходится потом отменять.

Вердикт пишется командой, а не правкой JSON руками: `artgen verdict <id> ...`.
Ручная правка файла вердиктов рано или поздно ломает его синтаксис посреди
прогона на полсотни ассетов.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageDraw

from .manifest import Asset
from .metrics import battle_backdrop

REVIEW_DIRNAME = "review"
VERDICTS_NAME = "verdicts.json"

# Статусы вердикта. Строками, а не enum: они уходят в JSON и в галерею,
# и должны читаться человеком без словаря.
ACCEPT = "принять"
FIX = "принять с правкой"
REJECT = "переделать"
STATUSES = (ACCEPT, FIX, REJECT)

ZOOM = 4


def review_dir(root: Path) -> Path:
    return root / "art" / REVIEW_DIRNAME


def verdicts_path(root: Path) -> Path:
    return review_dir(root) / VERDICTS_NAME


@dataclass
class QueueItem:
    asset: Asset
    sheet: Path
    report: dict

    def variants(self) -> list[dict]:
        return self.report.get("variants", [])

    def summary(self) -> str:
        """Что Клод читает вместе с картинкой: результат ворот по каждому варианту."""
        lines = [f"{self.asset.id} ({self.asset.kind.name})",
                 f"промпт: {self.report.get('prompt', '—')}"]
        for v in self.variants():
            bad = [c for c in v["checks"] if not c["ok"]]
            state = "прошёл ворота" if v["passed"] else "ЗАВЁРНУТ"
            lines.append(f"  вариант {v['variant']}: {state}")
            for c in bad:
                lines.append(f"      {c['severity']}: {c['detail']}")
        return "\n".join(lines)


def load_report(asset: Asset, root: Path) -> dict | None:
    path = asset.candidates_dir(root) / "report.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def _label_font():
    from PIL import ImageFont

    try:
        return ImageFont.load_default(size=24)
    except TypeError:
        # Pillow до 10.1 не умеет размер у встроенного шрифта
        return ImageFont.load_default()


def reference_image(asset: Asset, root: Path) -> Image.Image | None:
    """Принятый предыдущий грейд — то, с чем кандидата надо сравнивать.

    Старший грейд обязан остаться тем же зверем, только богаче убранством.
    Судить об этом по одному кандидату нельзя: без исходника рядом любое
    отклонение выглядит нормальным.
    """
    from .promote import load_decisions

    previous = asset.previous_grade_id()
    if previous is None:
        return None

    decision = load_decisions(root).get(previous, {})
    if decision.get("status") != "принят":
        return None

    path = root / "art" / "candidates" / previous / f"{decision['variant']}.png"
    return Image.open(path).convert("RGBA") if path.exists() else None


def build_sheet(asset: Asset, root: Path) -> Path | None:
    """Собрать контакт-лист: все варианты рядом, на фоне боя, увеличенные.

    Если ассет — старший грейд, первой колонкой идёт принятый младший,
    подписанный как основа. Сравнение на лету — весь смысл листа.
    """
    report = load_report(asset, root)
    if not report or not report["variants"]:
        return None

    directory = asset.candidates_dir(root)
    images: list[tuple[str, Image.Image]] = []

    base = reference_image(asset, root)
    if base is not None:
        images.append(("ОСНОВА", base))

    for v in report["variants"]:
        path = directory / v["image"]
        if path.exists():
            images.append((v["variant"], Image.open(path).convert("RGBA")))
    if not images:
        return None

    cell_w = max(i.width for _, i in images) * ZOOM
    zoom_h = max(i.height for _, i in images) * ZOOM
    true_h = max(i.height for _, i in images)
    strip = 30  # полоса под номером варианта

    # Два ряда: увеличенный и настоящего размера. Судить только по увеличенному
    # нельзя — в HD-пикселе половина брака видна лишь в честном размере, и
    # наоборот. Кандидат, выбранный по зуму, в игре регулярно оказывается кашей.
    sheet = Image.new("RGB", (cell_w * len(images), zoom_h + true_h + strip),
                      battle_backdrop())
    draw = ImageDraw.Draw(sheet)
    font = _label_font()

    for n, (name, img) in enumerate(images):
        left = n * cell_w
        big = img.resize((img.width * ZOOM, img.height * ZOOM), Image.NEAREST)
        sheet.paste(big, (left + (cell_w - big.width) // 2,
                          (zoom_h - big.height) // 2), big)
        sheet.paste(img, (left + (cell_w - img.width) // 2,
                          zoom_h + (true_h - img.height) // 2), img)

        # Разделитель между вариантами: без него два похожих кандидата
        # сливаются в один и номер уезжает не туда
        if n:
            draw.line([(left, 0), (left, sheet.height)], fill=(255, 255, 255), width=1)

        # Колонку-основу отделяем двойной линией и подписываем латиницей:
        # встроенный шрифт PIL без кириллицы, русский даст квадратики
        if name == "ОСНОВА":
            draw.line([(left + cell_w - 2, 0), (left + cell_w - 2, sheet.height)],
                      fill=(255, 255, 255), width=3)
            label = "BASE (accepted)"
        else:
            label = f"#{name}"
        draw.text((left + 8, sheet.height - strip + 4), label,
                  fill=(255, 255, 255), font=font)

    out = review_dir(root) / f"{asset.id}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


def load_verdicts(root: Path) -> dict:
    path = verdicts_path(root)
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("verdicts", {})


def save_verdicts(verdicts: dict, root: Path) -> None:
    path = verdicts_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "verdicts": verdicts,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def record(asset_id: str, chosen: str, status: str, note: str, root: Path) -> None:
    if status not in STATUSES:
        raise ValueError(f"статус '{status}' неизвестен, годятся: {', '.join(STATUSES)}")
    verdicts = load_verdicts(root)
    verdicts[asset_id] = {
        "chosen": chosen,
        "status": status,
        "note": note,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    save_verdicts(verdicts, root)


def _verdict_is_stale(verdict: dict, report: dict) -> bool:
    """Вердикт устарел, если выбранного варианта больше нет среди кандидатов.

    Так бывает после перегенерации: отклонённый ассет уходит на новую попытку,
    и файлы становятся другими. Без этой проверки очередь отвечала бы «пусто»,
    хотя свежие кандидаты никто не смотрел.
    """
    return verdict.get("chosen") not in {v["variant"] for v in report.get("variants", [])}


def queue(assets: list[Asset], root: Path, include_reviewed: bool = False) -> list[QueueItem]:
    """Ассеты, ждущие взгляда Клода.

    Не попадают: без кандидатов, уже принятые человеком (решение окончательное,
    пересматривать одобренное на каждом круге незачем) и отсмотренные, чей
    вердикт всё ещё относится к текущим кандидатам.
    """
    from .promote import load_decisions

    verdicts = load_verdicts(root)
    decisions = load_decisions(root)
    items: list[QueueItem] = []

    for asset in assets:
        if not asset.generated:
            continue
        report = load_report(asset, root)
        if not report:
            continue
        if not include_reviewed:
            if decisions.get(asset.id, {}).get("status") == "принят":
                continue
            verdict = verdicts.get(asset.id)
            if verdict and not _verdict_is_stale(verdict, report):
                continue
        items.append(QueueItem(asset, review_dir(root) / f"{asset.id}.png", report))
    return items


def status_line(assets: list[Asset], root: Path) -> str:
    from .promote import load_decisions

    decisions = load_decisions(root)
    generated = [a for a in assets if a.generated]
    with_candidates = [a for a in generated if load_report(a, root)]
    settled = [a for a in with_candidates
               if decisions.get(a.id, {}).get("status") == "принят"]
    return (
        f"генерируется: {len(generated)}, есть кандидаты: {len(with_candidates)}, "
        f"уже в игре: {len(settled)}, "
        f"ждут ревью: {len(queue(assets, root))}"
    )
