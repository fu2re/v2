"""FastAPI-приложение админки.

Сохранение: валидируется ВЕСЬ набор конфигов с кандидатом на месте
старого файла — кросс-ссылки живут между файлами, и валидная поодиночке
правка может ломать соседа. Ошибки — 409 и файл не тронут; успех —
снапшот в backups/, атомарная запись, предупреждения в ответе.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from . import backups, configs, refs, schema, tres, validator

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"
HINTS_PATH = Path(__file__).resolve().parent.parent / "hints.json"


def create_app(root: Path) -> FastAPI:
    root = root.resolve()
    app = FastAPI(title="BEATROOT balance admin")

    def _all_configs() -> dict[str, dict]:
        return {c["name"]: configs.read_config(root, c["name"])
                for c in configs.list_configs(root)}

    def _validate_with(candidates: dict[str, dict]) -> tuple[list[str], list[str]]:
        merged = _all_configs()
        merged.update(candidates)
        return validator.validate(root, merged)

    # --- конфиги -------------------------------------------------------------

    @app.get("/api/configs")
    def api_configs() -> list[dict]:
        return configs.list_configs(root)

    @app.get("/api/configs/{name}")
    def api_config(name: str) -> dict:
        try:
            data = configs.read_config(root, name)
        except FileNotFoundError as exc:
            raise HTTPException(404, str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        hints = schema.load_hints(HINTS_PATH)
        return {
            "name": name,
            "readonly": name in configs.READONLY,
            "data": data,
            "schema": schema.build_schema(name, data, hints),
        }

    @app.put("/api/configs/{name}")
    def api_save_config(name: str, payload: dict) -> dict:
        try:
            original = configs.read_config(root, name)
        except (FileNotFoundError, ValueError) as exc:
            raise HTTPException(404, str(exc)) from exc
        if name in configs.READONLY:
            raise HTTPException(403, f"{name} — только для чтения")

        data = schema.coerce_types(original, payload)
        if data == original:
            # Ничего не поменялось — не плодить ни запись, ни точку бэкапа
            return {"saved": name, "backup": None, "unchanged": True,
                    "warnings": []}
        errors, warnings = _validate_with({name: data})
        if errors:
            raise HTTPException(409, detail={"errors": errors,
                                             "warnings": warnings})
        stamp = backups.snapshot(root, changed=[name])
        configs.write_config(root, name, data)
        return {"saved": name, "backup": stamp, "warnings": warnings}

    @app.post("/api/validate")
    def api_validate(payload: dict) -> dict:
        """Сухой прогон: payload = {имя файла: кандидат}."""
        candidates = {}
        for name, data in payload.items():
            base = configs.read_config(root, name)
            candidates[name] = schema.coerce_types(base, data)
        errors, warnings = _validate_with(candidates)
        return {"errors": errors, "warnings": warnings}

    # --- справочники для селектов --------------------------------------------

    @app.get("/api/refs")
    def api_refs() -> dict:
        return refs.all_refs(root)

    # --- сущности (.tres идентичность + JSON статы) --------------------------

    @app.get("/api/entities/{kind}")
    def api_entities(kind: str) -> list[dict]:
        if kind not in refs.ENTITY_DIRS:
            raise HTTPException(404, f"Неизвестный вид сущностей: {kind}")
        stats_file, section = _STATS_TABLES.get(kind, (None, None))
        stats = {}
        if stats_file is not None:
            stats = configs.read_config(root, stats_file).get(section, {})
        out = []
        for path in sorted((root / refs.ENTITY_DIRS[kind]).glob("*.tres")):
            fields = tres.read_fields(path)
            entity_id = str(fields.get("id", path.stem))
            out.append({
                "id": entity_id,
                "file": path.name,
                "identity": fields,
                "stats": stats.get(entity_id, {}),
                "editable_identity": sorted(tres.EDITABLE_FIELDS[kind]),
            })
        return out

    @app.put("/api/entities/{kind}/{entity_id}")
    def api_save_entity(kind: str, entity_id: str, payload: dict) -> dict:
        """payload = {"identity": {поле: значение}, "stats": {поле: значение}}.

        Идентичность патчится в .tres, статы — в JSON-таблицу; оба изменения
        валидируются и попадают под ОДИН снапшот: правка сущности — одна
        операция, и откатываться она обязана целиком.
        """
        if kind not in refs.ENTITY_DIRS:
            raise HTTPException(404, f"Неизвестный вид сущностей: {kind}")
        tres_path = _entity_path(root, kind, entity_id)
        if tres_path is None:
            raise HTTPException(404, f"Нет сущности {entity_id}")

        identity = payload.get("identity", {})
        stats = payload.get("stats", {})
        for field in identity:
            if field not in tres.EDITABLE_FIELDS[kind]:
                raise HTTPException(400, f"Поле {field} не правится из админки")

        stats_file, section = _STATS_TABLES.get(kind, (None, None))
        candidates: dict[str, dict] = {}
        new_table = None
        if stats:
            if stats_file is None:
                raise HTTPException(400, f"У {kind} нет таблицы статов")
            new_table = configs.read_config(root, stats_file)
            row = dict(new_table.get(section, {}).get(entity_id, {}))
            row.update(stats)
            new_table.setdefault(section, {})[entity_id] = \
                schema.coerce_types(
                    configs.read_config(root, stats_file)
                    .get(section, {}).get(entity_id, {}), row)
            candidates[stats_file] = new_table

        # Идентичность валидируется «на будущем» состоянии: патчим копию
        # в памяти нельзя (валидатор читает .tres с диска), поэтому сначала
        # снапшот, потом патч, потом валидация, и при ошибках — откат патча.
        stamp = backups.snapshot(root, changed=[f"{kind}/{entity_id}"])
        original_text = tres_path.read_text(encoding="utf-8")
        try:
            for field, value in identity.items():
                tres.patch_field(tres_path, field, value)
            errors, warnings = _validate_with(candidates)
            if errors:
                raise HTTPException(409, detail={"errors": errors,
                                                 "warnings": warnings})
            if new_table is not None:
                configs.write_config(root, stats_file, new_table)
        except HTTPException:
            tres_path.write_text(original_text, encoding="utf-8", newline="\n")
            raise
        except KeyError as exc:
            tres_path.write_text(original_text, encoding="utf-8", newline="\n")
            raise HTTPException(400, str(exc)) from exc
        return {"saved": entity_id, "backup": stamp, "warnings": warnings}

    @app.post("/api/entities/monsters/{entity_id}/grade_sprite")
    def api_set_grade_sprite(entity_id: str, payload: dict) -> dict:
        """Заменить спрайт грейда: копия выбранного файла в слот конвенции.

        Спрайты грейдов игра открывает по имени art/monster/<id>_<грейд>.png —
        никакого поля в данных нет, поэтому «поменять спрайт» означает
        положить другой файл под это имя. Старый файл уезжает в точку
        бэкапа и восстанавливается откатом как обычно.
        """
        if _entity_path(root, "monsters", entity_id) is None:
            raise HTTPException(404, f"Нет монстра {entity_id}")
        grade = str(payload.get("grade", ""))
        if grade not in refs.GRADE_KEYS:
            raise HTTPException(400, f"Неизвестный грейд: {grade}")

        source_raw = str(payload.get("source", "")).removeprefix("res://")
        source = (root / source_raw).resolve()
        art_root = (root / "art").resolve()
        if not source.is_file() or source.suffix != ".png" \
                or not source.is_relative_to(art_root):
            raise HTTPException(400, f"Источник должен быть .png из art/: "
                                     f"{payload.get('source')}")

        target = root / "art" / "monster" / f"{entity_id}_{grade}.png"
        if source == target.resolve():
            return {"saved": target.name, "backup": None, "unchanged": True}
        stamp = backups.snapshot(
            root, changed=[f"art/monster/{target.name}"],
            note=f"спрайт {entity_id} · {grade}", extra_files=[target])
        shutil.copyfile(source, target)
        return {"saved": target.name, "backup": stamp}

    # --- картинки ------------------------------------------------------------

    @app.get("/api/images")
    def api_images(dir: str = "") -> dict:
        if not dir:
            return {"dirs": refs.image_dirs(root)}
        try:
            return {"dir": dir, "files": refs.images_in(root, dir)}
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc

    # --- бекапы --------------------------------------------------------------

    @app.get("/api/backups")
    def api_backups() -> list[dict]:
        return backups.list_backups(root)

    @app.post("/api/backups/{stamp}/rollback")
    def api_rollback(stamp: str) -> dict:
        try:
            restored = backups.rollback(root, stamp)
        except FileNotFoundError as exc:
            raise HTTPException(404, str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        return {"restored": restored}

    # --- статика -------------------------------------------------------------

    app.mount("/art", StaticFiles(directory=root / "art"), name="art")
    app.mount("/music", StaticFiles(directory=root / "music"), name="music")
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

    @app.get("/")
    def index() -> FileResponse:
        return FileResponse(STATIC_DIR / "index.html")

    return app


_STATS_TABLES = {
    "monsters": ("monsters.json", "species"),
    "gear": ("gear.json", "items"),
    "cosmetics": ("cosmetics.json", "items"),
    # У фруктов числа по тирам в fruits.json — отдельной таблицы на id нет
    "fruits": (None, None),
}


def _entity_path(root: Path, kind: str, entity_id: str) -> Path | None:
    for path in (root / refs.ENTITY_DIRS[kind]).glob("*.tres"):
        if str(tres.read_fields(path).get("id", "")) == entity_id:
            return path
    return None
