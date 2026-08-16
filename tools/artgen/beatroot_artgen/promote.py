"""Перенос принятых кандидатов в игру.

Отдельный шаг, а не побочный эффект генерации: пока ассет лежит в `candidates/`,
он ничего не ломает, и переигрывать решение бесплатно. Как только он оказался
в `art/<вид>/` и прописан в `.tres` — он в игре, и цена ошибки другая.

Решение человека хранится отдельно от вердикта Клода. Смешивать нельзя:
повторный прогон ревью перезаписал бы вердикты, а вместе с ними — и то, что
человек уже решил своими глазами.

Отклонение сдвигает счётчик попытки. Без него следующий прогон выдал бы ровно
те же картинки: сид детерминирован от id и номера варианта, и «перегенерировать»
без смены попытки означает получить тот же брак второй раз.
"""

from __future__ import annotations

import json
import re
import shutil
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .manifest import Asset, by_id
from .review import review_dir

DECISIONS_NAME = "decisions.json"

ASSETS_MD_BEGIN = "<!-- artgen:begin -->"
ASSETS_MD_END = "<!-- artgen:end -->"

# Ресурсы, у которых есть поле спрайта. У снаряжения и косметики его пока нет —
# иконки некуда прописать, и это надо чинить в игре, а не выдумывать поле здесь.
SPRITE_FIELD_DIRS = {
    "monster": "data/monsters",
    "fruit": "data/fruits",
}


def decisions_path(root: Path) -> Path:
    return review_dir(root) / DECISIONS_NAME


def load_decisions(root: Path) -> dict:
    path = decisions_path(root)
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8")).get("decisions", {})


def save_decisions(decisions: dict, root: Path) -> None:
    path = decisions_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "decisions": decisions,
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def attempt_of(asset_id: str, root: Path) -> int:
    return int(load_decisions(root).get(asset_id, {}).get("attempt", 0))


@dataclass
class Result:
    promoted: list[tuple[str, Path]] = field(default_factory=list)
    rejected: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    # Ассеты, чей путь к спрайту некуда прописать: в ресурсе нет поля
    unwired: list[str] = field(default_factory=list)

    def as_text(self) -> str:
        lines = []
        for aid, path in self.promoted:
            lines.append(f"  принят  {aid} -> {path}")
        for aid in self.rejected:
            lines.append(f"  отклонён {aid} (следующая попытка даст другие сиды)")
        if self.unwired:
            lines.append("")
            lines.append("Файлы на месте, но в игру не подключены — в ресурсе нет поля спрайта:")
            lines.append(f"  {', '.join(self.unwired)}")
            lines.append("  Нужно добавить поле в GearData/CosmeticData и показать иконку в лавке.")
        for p in self.problems:
            lines.append(f"  ! {p}")
        return "\n".join(lines) or "  ничего не изменилось"


def _update_sprite_path(asset: Asset, target: Path, root: Path) -> bool:
    """Прописать путь к спрайту в .tres. False — поля нет, править нечего.

    У монстра шесть грейдов, а поле `sprite_path` в MonsterData одно. Пишем
    в него только базовый грейд; остальные ложатся на диск и ждут, пока
    в данных появится место под набор. Придумывать поле здесь нельзя —
    это игровая модель, а не дело арт-пайплайна.
    """
    rel = SPRITE_FIELD_DIRS.get(asset.kind.name)
    if rel is None:
        return False
    if asset.grade is not None and not asset.grade.is_base:
        return False
    tres = root / rel / f"{asset.base_id}.tres"
    if not tres.exists():
        return False

    text = tres.read_text(encoding="utf-8")
    if "sprite_path" not in text:
        return False

    res_path = "res://" + target.relative_to(root).as_posix()
    updated = re.sub(r'^sprite_path\s*=\s*".*"$',
                     f'sprite_path = "{res_path}"', text, flags=re.MULTILINE)
    if updated != text:
        tres.write_text(updated, encoding="utf-8")
    return True


def checkpoint_of(asset_id: str, root: Path, fallback: str) -> str:
    """Чем на самом деле сгенерирован конкретный ассет.

    Один чекпойнт на всю команду записывать нельзя: часть ассетов сделана
    другой моделью (мшистая грядка — SDXL, остальное — FLUX), а таблица
    происхождения в коммерческой игре обязана называть модель точно.
    Настоящее имя лежит в отчёте рядом с кандидатами.
    """
    report = root / "art" / "candidates" / asset_id / "report.json"
    if report.exists():
        name = json.loads(report.read_text(encoding="utf-8")).get("checkpoint", "")
        if name:
            return name
    return fallback


def _update_assets_md(promoted: list[tuple[str, Path]], checkpoint: str, root: Path) -> None:
    """Перезаписать управляемый блок в ASSETS.md.

    Блок именно управляемый, с маркерами: разбирать markdown-таблицу регуляркой
    и дописывать в неё строки — способ однажды её молча испортить.
    """
    md = root / "ASSETS.md"
    if not md.exists():
        return

    rows = "\n".join(
        f"| `{path.relative_to(root).as_posix()}` | "
        f"ComfyUI, `{checkpoint_of(asset_id, root, checkpoint)}`, "
        f"постобработка `tools/artgen` | Собственное производство |"
        for asset_id, path in sorted(promoted)
    )
    block = (
        f"{ASSETS_MD_BEGIN}\n"
        f"### Сгенерированные ассеты\n\n"
        f"Раздел ведёт `artgen promote` — правки руками будут затёрты.\n"
        f"Каждый ассет доводится вручную после переноса: это и качество,\n"
        f"и основание для прав на результат.\n\n"
        f"| Файл | Происхождение | Лицензия |\n|---|---|---|\n{rows}\n"
        f"{ASSETS_MD_END}"
    )

    text = md.read_text(encoding="utf-8")
    if ASSETS_MD_BEGIN in text and ASSETS_MD_END in text:
        start = text.index(ASSETS_MD_BEGIN)
        end = text.index(ASSETS_MD_END) + len(ASSETS_MD_END)
        text = text[:start] + block + text[end:]
    else:
        text = text.rstrip() + "\n\n" + block + "\n"
    md.write_text(text, encoding="utf-8")


def promote(assets: list[Asset], picks: dict[str, str], rejects: list[str],
            root: Path, checkpoint: str = "") -> Result:
    known = by_id(assets)
    decisions = load_decisions(root)
    result = Result()
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    for asset_id, variant in picks.items():
        asset = known.get(asset_id)
        if asset is None:
            result.problems.append(f"{asset_id}: нет в манифесте")
            continue

        source = asset.candidates_dir(root) / f"{variant}.png"
        if not source.exists():
            result.problems.append(f"{asset_id}: вариант {variant} не найден ({source})")
            continue

        target = asset.target_path(root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)

        if not _update_sprite_path(asset, target, root):
            result.unwired.append(asset_id)

        decisions[asset_id] = {
            "status": "принят",
            "variant": variant,
            "attempt": int(decisions.get(asset_id, {}).get("attempt", 0)),
            "at": now,
        }
        result.promoted.append((asset_id, target))

    for asset_id in rejects:
        if asset_id not in known:
            result.problems.append(f"{asset_id}: нет в манифесте")
            continue
        previous = decisions.get(asset_id, {})
        decisions[asset_id] = {
            "status": "отклонён",
            "variant": None,
            "attempt": int(previous.get("attempt", 0)) + 1,
            "at": now,
        }
        result.rejected.append(asset_id)

    save_decisions(decisions, root)
    if result.promoted:
        every = [(aid, path) for aid, path in result.promoted]
        # В ASSETS.md должен попасть весь принятый набор, а не только текущая
        # пачка — иначе таблица теряет прошлые строки при следующем прогоне
        for asset_id, decision in decisions.items():
            if decision["status"] == "принят" and asset_id in known:
                entry = (asset_id, known[asset_id].target_path(root))
                if entry not in every:
                    every.append(entry)
        _update_assets_md(every, checkpoint or "чекпойнт не указан", root)

    return result
