"""Чтение и запись балансовых JSON.

Запись — КАНОНИЧЕСКИМ форматом, а не голым json.dumps: скалярные массивы
и короткие плоские словари остаются в одну строку, топ-секции разделяются
пустой строкой, кириллица не экранируется, завершающий перевод строки,
UTF-8, unix-переводы. Файлы data/*.json один раз приведены к этому виду,
после чего no-op сохранение даёт пустой git diff — это приёмочный тест
инструмента (правку без изменения данных сервер вообще не пишет).
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path

# Инлайн-порог: скалярный массив или плоский словарь короче этого — в одну
# строку. Число влияет только на эстетику канонического вида.
_INLINE_LIMIT = 100

# Файлы, которые админка показывает, но не даёт править:
# items.json — справочник, не читается кодом; motifs.json — замороженный
# выход chartgen, правится только регенерацией мелодий.
READONLY = {"items.json", "motifs.json"}


def data_dir(root: Path) -> Path:
    return root / "data"


def list_configs(root: Path) -> list[dict]:
    """Все data/*.json c флагом readonly. Новый файл подхватится сам."""
    out = []
    for path in sorted(data_dir(root).glob("*.json")):
        out.append({
            "name": path.name,
            "readonly": path.name in READONLY,
            "size": path.stat().st_size,
        })
    return out


def read_config(root: Path, name: str) -> dict:
    path = _safe_path(root, name)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def write_config(root: Path, name: str, data: dict) -> None:
    """Атомарная запись: во временный файл рядом, затем replace.

    Обрыв на середине записи не должен оставлять полфайла — Balance
    в игре прочитает мусор и молча уйдёт на заглушки.
    """
    path = _safe_path(root, name)
    if name in READONLY:
        raise PermissionError(f"{name} — только для чтения")
    payload = dumps_canonical(data)
    fd, tmp_name = tempfile.mkstemp(dir=path.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(payload)
        os.replace(tmp_name, path)
    except BaseException:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def dumps_canonical(data: dict) -> str:
    return _dump(data, 0, top=True) + "\n"


def _dump(value, indent: int, top: bool = False) -> str:
    pad = "  " * indent
    child_pad = "  " * (indent + 1)

    if isinstance(value, dict):
        if not value:
            return "{}"
        if not top and _fits_inline_dict(value, indent):
            body = ", ".join(
                f"{json.dumps(k, ensure_ascii=False)}: {_scalar_dump(v)}"
                for k, v in value.items())
            return "{ " + body + " }"
        items = [
            f"{child_pad}{json.dumps(k, ensure_ascii=False)}: "
            f"{_dump(v, indent + 1)}"
            for k, v in value.items()
        ]
        # Пустая строка между топ-секциями — так файлы читаются глазами
        separator = ",\n\n" if top else ",\n"
        return "{\n" + separator.join(items) + f"\n{pad}}}"

    if isinstance(value, list):
        if not value:
            return "[]"
        if all(_is_scalar(x) for x in value):
            inline = "[" + ", ".join(_scalar_dump(x) for x in value) + "]"
            if len(inline) + indent * 2 <= _INLINE_LIMIT:
                return inline
        items = [f"{child_pad}{_dump(x, indent + 1)}" for x in value]
        return "[\n" + ",\n".join(items) + f"\n{pad}]"

    return _scalar_dump(value)


def _fits_inline_dict(value: dict, indent: int) -> bool:
    if not all(_is_scalar(v) for v in value.values()):
        return False
    rendered = sum(len(json.dumps(k, ensure_ascii=False))
                   + len(_scalar_dump(v)) + 4 for k, v in value.items())
    return rendered + indent * 2 + 4 <= _INLINE_LIMIT


def _is_scalar(value) -> bool:
    return value is None or isinstance(value, (bool, int, float, str))


def _scalar_dump(value) -> str:
    if isinstance(value, float):
        # 0.05 остаётся 0.05, а 2.0 — 2.0: repr питона совпадает с JSON
        return json.dumps(value)
    return json.dumps(value, ensure_ascii=False)


def _safe_path(root: Path, name: str) -> Path:
    """Имя файла — только базовое, никаких путей: это HTTP-вход."""
    if name != Path(name).name or not name.endswith(".json"):
        raise ValueError(f"Недопустимое имя конфига: {name}")
    path = data_dir(root) / name
    if not path.is_file():
        raise FileNotFoundError(f"Нет такого конфига: {name}")
    return path
