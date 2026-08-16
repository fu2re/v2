"""Чтение и точечная правка плоских .tres.

Общего парсера ресурсов Godot здесь нет намеренно: файлы сущностей
плоские (key = value в секции [resource]), и всё, что нужно админке, —
прочитать эти пары и заменить значение ОДНОГО известного поля.
Прецедент — tools/artgen/beatroot_artgen/promote.py, который так же
правит sprite_path. Патч отказывается работать, если строки поля нет:
выдумывать поля, которых движок не записал, инструменту нельзя.
"""

from __future__ import annotations

import re
from pathlib import Path

# Поля идентичности, которые разрешено править из админки.
# Числа сущностей живут в JSON и правятся через configs, а не здесь.
EDITABLE_FIELDS = {
    "monsters": {"display_name", "genre", "favorite_fruit_id", "motif_id", "sprite_path"},
    "gear": {"display_name", "slot", "rarity", "sprite_path"},
    "cosmetics": {"display_name", "slot", "sprite_path"},
    "fruits": {"display_name", "tier", "sprite_path"},
}

_LINE = re.compile(r"^(?P<key>[A-Za-z_][A-Za-z0-9_]*) = (?P<value>.+)$")


def read_fields(path: Path) -> dict:
    """Пары key -> значение из секции [resource]; script пропускается."""
    out: dict = {}
    in_resource = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() == "[resource]":
            in_resource = True
            continue
        if not in_resource:
            continue
        match = _LINE.match(line)
        if match is None or match["key"] == "script":
            continue
        out[match["key"]] = _parse_value(match["value"])
    return out


def patch_field(path: Path, key: str, value) -> None:
    """Заменить значение существующего поля. Нет строки — отказ."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"^{re.escape(key)} = .+$", re.MULTILINE)
    if pattern.search(text) is None:
        raise KeyError(f"{path.name}: поля {key} нет — патчить нечего")
    new_text = pattern.sub(f"{key} = {_format_value(value)}", text, count=1)
    path.write_text(new_text, encoding="utf-8", newline="\n")


def _parse_value(raw: str):
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    try:
        return int(raw)
    except ValueError:
        pass
    try:
        return float(raw)
    except ValueError:
        return raw


def _format_value(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return f'"{value}"'
    if isinstance(value, float) and value == int(value):
        # Godot пишет целые float как 1.0, а не 1
        return f"{value:.1f}"
    return str(value)
