"""Списки id и индексы для селектов интерфейса.

Всё, что игрок мог бы «угадывать» строкой, здесь собирается в списки:
id фруктов, монстров, снаряжения, косметики (из .tres), мотивы
(из motifs.json), грейды и жанры (лестницы проекта), индекс чартов
(из имён файлов charts/). Регексы по .tres — тот же приём, что
в tools/artgen/beatroot_artgen/manifest.py.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import tres

GRADE_KEYS = ["common", "uncommon", "rare", "unique", "epic", "legendary"]
GENRE_KEYS = ["rock", "disco", "folk", "electro", "latin"]
BUFF_KEYS = ["shield_reduction", "power_bonus", "window_scale"]

ENTITY_DIRS = {
    "monsters": "data/monsters",
    "gear": "data/gear",
    "cosmetics": "data/cosmetics",
    "fruits": "data/fruits",
}

# Имя чарта: <жанр>_<мотив>_<грейд>_<bpm>.json — ровно четыре токена.
_CHART_NAME = re.compile(
    r"^(?P<genre>[a-z]+)_(?P<motif>[a-z]+)_(?P<grade>[a-z]+)_(?P<bpm>\d+)$")


def entity_ids(root: Path, kind: str) -> list[str]:
    directory = root / ENTITY_DIRS[kind]
    return sorted(
        str(tres.read_fields(p).get("id", ""))
        for p in directory.glob("*.tres")
        if tres.read_fields(p).get("id")
    )


def display_names(root: Path, kind: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in (root / ENTITY_DIRS[kind]).glob("*.tres"):
        fields = tres.read_fields(path)
        if fields.get("id"):
            out[str(fields["id"])] = str(fields.get("display_name", ""))
    return out


def motif_ids(root: Path) -> list[str]:
    with open(root / "data" / "motifs.json", encoding="utf-8") as fh:
        data = json.load(fh)
    return [m["id"] for m in data.get("motifs", []) if "id" in m]


def motif_titles(root: Path) -> dict[str, str]:
    with open(root / "data" / "motifs.json", encoding="utf-8") as fh:
        data = json.load(fh)
    return {m["id"]: str(m.get("title", m["id"]))
            for m in data.get("motifs", []) if "id" in m}


def track_index(root: Path) -> dict[str, dict[str, str]]:
    """Стемы треков: жанр_мотив -> {грейд -> имя файла без .ogg}.

    music/*.ogg зеркалит charts/ один в один; индекс строится из имён —
    трек, как и чарт, никем не объявляется: он ЕСТЬ или его НЕТ.
    Нужен кнопке «послушать»: грейд определяет темп ремикса.
    """
    out: dict[str, dict[str, str]] = {}
    for path in (root / "music").glob("*.ogg"):
        match = _CHART_NAME.match(path.stem)
        if match is None:
            continue
        key = f"{match['genre']}_{match['motif']}"
        out.setdefault(key, {})[match["grade"]] = path.stem
    return out


def chart_index(root: Path) -> dict[str, list[str]]:
    """Какие грейды реально существуют для пары жанр_мотив.

    Индекс строится из имён файлов, как в data/chart_select.gd:
    чарт никем не объявляется, он ЕСТЬ или его НЕТ. Селект мотива
    в админке фильтруется по этому индексу.
    """
    out: dict[str, list[str]] = {}
    for path in (root / "charts").glob("*.json"):
        match = _CHART_NAME.match(path.stem)
        if match is None:
            continue
        key = f"{match['genre']}_{match['motif']}"
        out.setdefault(key, [])
        if match["grade"] not in out[key]:
            out[key].append(match["grade"])
    for grades in out.values():
        grades.sort(key=lambda g: GRADE_KEYS.index(g) if g in GRADE_KEYS else 99)
    return out


def image_dirs(root: Path) -> list[str]:
    art = root / "art"
    skip = {"raw", "candidates", "review", "palette"}
    return sorted(
        p.name for p in art.iterdir()
        if p.is_dir() and p.name not in skip and any(p.glob("*.png"))
    )


def images_in(root: Path, directory: str) -> list[str]:
    if directory != Path(directory).name:
        raise ValueError(f"Недопустимый каталог: {directory}")
    art = root / "art" / directory
    if not art.is_dir():
        return []
    return sorted(p.name for p in art.glob("*.png"))


def all_refs(root: Path) -> dict:
    return {
        "grade_keys": GRADE_KEYS,
        "genre_keys": GENRE_KEYS,
        "buff_keys": BUFF_KEYS,
        "fruit_ids": entity_ids(root, "fruits"),
        "monster_ids": entity_ids(root, "monsters"),
        "gear_ids": entity_ids(root, "gear"),
        "cosmetic_ids": entity_ids(root, "cosmetics"),
        "motif_ids": motif_ids(root),
        "motif_titles": motif_titles(root),
        "chart_index": chart_index(root),
        "track_index": track_index(root),
        "display_names": {
            kind: display_names(root, kind) for kind in ENTITY_DIRS
        },
        "image_dirs": image_dirs(root),
    }
