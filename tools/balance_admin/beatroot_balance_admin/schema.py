"""Схема формы из произвольного JSON-дерева.

Никакого кода на конкретный файл: новый data/foo.json сразу получает
рабочую форму. Схема выводится из самих данных (типы листьев, узнаваемые
паттерны ключей), а hints.json рядом с инструментом дообогащает то,
что по данным не угадать. Приоритет: hints > паттерны > типы.
"""

from __future__ import annotations

import fnmatch
import json
from pathlib import Path

from .refs import BUFF_KEYS, GRADE_KEYS

DOC_KEYS = {"description", "note", "why", "formula"}
DOC_SUFFIXES = ("_note", "_readme", "_rule", "_formula", "_why", "_question")

# Суффикс ключа -> источник вариантов в /api/refs
_ID_SOURCES = [
    ("fruit_id", "fruit_ids"),
    ("seed_ids", "fruit_ids"),
    ("motif_id", "motif_ids"),
    ("monster_id", "monster_ids"),
    ("gear_id", "gear_ids"),
    ("cosmetic_id", "cosmetic_ids"),
]


def load_hints(hints_path: Path) -> dict:
    if not hints_path.is_file():
        return {"widgets": []}
    with open(hints_path, encoding="utf-8") as fh:
        return json.load(fh)


def build_schema(name: str, data, hints: dict) -> dict:
    return _annotate(name, data, [], hints)


def _annotate(name: str, value, path: list[str], hints: dict) -> dict:
    key = path[-1] if path else ""
    node: dict = {"path": ".".join(path)}

    hint = _hint_for(name, node["path"], hints)
    if hint is not None:
        node.update({k: v for k, v in hint.items() if k != "match"})

    if _is_doc_key(key):
        node["kind"] = "doc"
        node["value_kind"] = _kind_of(value)
        return node

    if isinstance(value, dict):
        node.setdefault("kind", "object")
        # Узнаваемые паттерны словарей
        grade_hits = sum(1 for k in value if k in GRADE_KEYS)
        flat_numeric = value and all(
            _is_doc_key(k) or isinstance(v, (int, float))
            and not isinstance(v, bool)
            for k, v in value.items())
        if grade_hits >= 3 and flat_numeric:
            node.setdefault("widget", "grade_map")
        elif value and all(k in BUFF_KEYS or _is_doc_key(k) for k in value):
            node.setdefault("widget", "buff_map")
        # Индикатор суммы — только у РАСПРЕДЕЛЕНИЙ. «weights» и «odds» —
        # доли одного розыгрыша и обязаны давать 100; «chance»/«percent»
        # сами по себе — независимые шансы, их сумма ничего не значит
        if flat_numeric and ("weights" in key or "odds" in key):
            node.setdefault("sum_to", 100.0)
        node["children"] = {
            k: _annotate(name, v, path + [str(k)], hints)
            for k, v in value.items()
        }
        return node

    if isinstance(value, list):
        node.setdefault("kind", "array")
        if value and all(isinstance(x, dict) for x in value):
            node.setdefault("widget", "object_table")
            node["item_schema"] = _annotate(name, value[0], path + ["0"], hints)
        elif all(isinstance(x, str) for x in value):
            node.setdefault("widget", "string_list")
        return node

    node.setdefault("kind", _kind_of(value))

    # Селекты по суффиксу ключа
    for suffix, source in _ID_SOURCES:
        if key.endswith(suffix):
            node.setdefault("widget", "select")
            node.setdefault("options", source)
            if suffix.endswith("_ids"):
                node["widget"] = "multi_select"
            break

    if key == "sprite_path" or (
            isinstance(value, str) and value.startswith("res://art/")):
        node["widget"] = "image"
    elif isinstance(value, str) and value in GRADE_KEYS:
        node.setdefault("widget", "select")
        node.setdefault("options", "grade_keys")

    return node


def coerce_types(original, incoming):
    """Вернуть incoming с типами токенов original.

    JS не различает 1 и 1.0: после round-trip через браузер float с нулевой
    дробной частью приезжает int-ом, и наивная запись меняла бы 1.0 -> 1
    по всему файлу. Где в исходнике был float — восстанавливаем float;
    настоящую смену значения (15 -> 15.5) не трогаем.
    """
    if isinstance(original, dict) and isinstance(incoming, dict):
        return {
            k: coerce_types(original.get(k), v) if k in original else v
            for k, v in incoming.items()
        }
    if isinstance(original, list) and isinstance(incoming, list):
        sample = original[0] if original else None
        return [coerce_types(sample, v) for v in incoming]
    if isinstance(original, float) and isinstance(incoming, int) \
            and not isinstance(incoming, bool):
        return float(incoming)
    return incoming


def _is_doc_key(key: str) -> bool:
    return (key.startswith("_") or key in DOC_KEYS
            or key.endswith(DOC_SUFFIXES))


def _kind_of(value) -> str:
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "null"


def _hint_for(name: str, dotted: str, hints: dict) -> dict | None:
    target = f"{name}:{dotted}"
    for entry in hints.get("widgets", []):
        if fnmatch.fnmatch(target, entry.get("match", "")):
            return entry
    return None
