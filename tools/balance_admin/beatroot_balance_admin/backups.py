"""Бекапы конфигов: снапшот перед каждой записью, откат на точку.

Точка — каталог backups/balance/<YYYYMMDD_HHMMSS>/ с копиями ВСЕХ
data/*.json и .tres сущностей (пути сохраняются относительно data/).
Копируется всё, а не только изменённое: точка обязана быть согласованным
срезом, из которого можно восстановиться не думая. Тот же принцип
copy-before-write, что у save_manager.gd для сейва игрока.
"""

from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

from .refs import ENTITY_DIRS

BACKUP_DIR = "backups/balance"


def _tracked_files(root: Path) -> list[Path]:
    out = sorted((root / "data").glob("*.json"))
    for sub in ENTITY_DIRS.values():
        out.extend(sorted((root / sub).glob("*.tres")))
    return out


def snapshot(root: Path, changed: list[str], note: str = "") -> str:
    """Снять точку. Возвращает её штамп."""
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    target = root / BACKUP_DIR / stamp
    # Две записи в одну секунду — добавляем суффикс, а не затираем
    suffix = 0
    while target.exists():
        suffix += 1
        target = root / BACKUP_DIR / f"{stamp}_{suffix}"
    target.mkdir(parents=True)

    for path in _tracked_files(root):
        relative = path.relative_to(root)
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)

    meta = {
        "stamp": target.name,
        "created": datetime.now().isoformat(timespec="seconds"),
        "changed": changed,
        "note": note,
    }
    (target / "meta.json").write_text(
        json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return target.name


def list_backups(root: Path) -> list[dict]:
    base = root / BACKUP_DIR
    if not base.is_dir():
        return []
    out = []
    for entry in sorted(base.iterdir(), reverse=True):
        meta_path = entry / "meta.json"
        if not meta_path.is_file():
            continue
        try:
            out.append(json.loads(meta_path.read_text(encoding="utf-8")))
        except ValueError:
            out.append({"stamp": entry.name, "note": "meta.json битый"})
    return out


def rollback(root: Path, stamp: str) -> list[str]:
    """Восстановить точку. Возвращает список восстановленных файлов.

    Текущее состояние сначала снимается отдельной точкой *_pre_rollback:
    откат не должен быть дорогой в один конец.
    """
    if stamp != Path(stamp).name:
        raise ValueError(f"Недопустимый штамп: {stamp}")
    source = root / BACKUP_DIR / stamp
    if not source.is_dir():
        raise FileNotFoundError(f"Точки {stamp} нет")

    snapshot(root, changed=[], note=f"pre_rollback -> {stamp}")

    restored = []
    for path in sorted(source.rglob("*")):
        if not path.is_file() or path.name == "meta.json":
            continue
        relative = path.relative_to(source)
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
        restored.append(str(relative))
    return restored
