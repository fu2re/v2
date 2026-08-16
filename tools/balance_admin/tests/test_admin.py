"""Тесты балансовой админки: формат, валидатор, бэкапы, .tres-патч.

Гоняются на КОПИИ данных репозитория во временном каталоге: тест,
который портит живые конфиги, хуже отсутствия теста.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from beatroot_balance_admin import backups, configs, schema, tres, validator

REPO = Path(__file__).resolve().parents[3]


@pytest.fixture()
def root(tmp_path: Path) -> Path:
    """Копия data/ и charts/ (именами) в песочнице."""
    shutil.copytree(REPO / "data", tmp_path / "data")
    charts = tmp_path / "charts"
    charts.mkdir()
    for chart in (REPO / "charts").glob("*.json"):
        (charts / chart.name).touch()  # валидатору важны имена, не содержимое
    art = tmp_path / "art" / "monster"
    art.mkdir(parents=True)
    for sprite in (REPO / "art" / "monster").glob("*.png"):
        (art / sprite.name).touch()
    return tmp_path


def _load_all(root: Path) -> dict:
    return {c["name"]: configs.read_config(root, c["name"])
            for c in configs.list_configs(root)}


# --- канонический формат ------------------------------------------------------

def test_canonical_roundtrip_is_stable(root: Path) -> None:
    """Повторная запись без изменений даёт байт-в-байт тот же файл."""
    for cfg in configs.list_configs(root):
        if cfg["readonly"]:
            continue
        path = root / "data" / cfg["name"]
        before = path.read_bytes()
        configs.write_config(root, cfg["name"],
                             configs.read_config(root, cfg["name"]))
        assert path.read_bytes() == before, f"{cfg['name']} переформатировался"


def test_canonical_preserves_cyrillic_and_floats(root: Path) -> None:
    text = (root / "data" / "battle.json").read_text(encoding="utf-8")
    assert "Числа боя" in text, "кириллица не должна экранироваться"
    assert '"window_bars": 4.0' in text, "float не должен схлопнуться в int"


def test_coerce_restores_float_tokens() -> None:
    original = {"a": 1.0, "b": 2, "nested": {"c": [0.5, 1.5]}}
    from_js = {"a": 1, "b": 2, "nested": {"c": [0.5, 2]}}
    fixed = schema.coerce_types(original, from_js)
    assert isinstance(fixed["a"], float)
    assert isinstance(fixed["b"], int)
    assert isinstance(fixed["nested"]["c"][1], float)


def test_readonly_configs_refuse_write(root: Path) -> None:
    with pytest.raises(PermissionError):
        configs.write_config(root, "items.json", {})


# --- валидатор ----------------------------------------------------------------

def test_current_tables_are_clean(root: Path) -> None:
    errors, warnings = validator.validate(root, _load_all(root))
    assert errors == []
    assert warnings == []


def test_missing_required_key_is_error(root: Path) -> None:
    tables = _load_all(root)
    del tables["battle.json"]["strikes"]["strike_damage"]
    errors, _ = validator.validate(root, tables)
    assert any("strike_damage" in e for e in errors)


def test_broken_weights_sum_is_error(root: Path) -> None:
    tables = _load_all(root)
    tables["drop_tables.json"]["glade_types"]["weights_percent"]["battle"] = 64
    errors, _ = validator.validate(root, tables)
    assert any("100%" in e for e in errors)


def test_crate_pool_invariant(root: Path) -> None:
    """Грейд с шансом, но без вещей в пуле — ошибка (SHOP.md §4)."""
    tables = _load_all(root)
    for row in tables["cosmetics.json"]["items"].values():
        if row["rarity"] == "unique":
            row["in_crates"] = False
    errors, _ = validator.validate(root, tables)
    assert any("unique" in e and "in_crates" in e for e in errors)


def test_widened_good_window_warns_about_charts(root: Path) -> None:
    tables = _load_all(root)
    tables["battle.json"]["judge"]["good_window"] = 0.15
    _, warnings = validator.validate(root, tables)
    assert any("интервал" in w for w in warnings)


def test_monotonic_scale_guard(root: Path) -> None:
    tables = _load_all(root)
    tables["progression.json"]["grade_multipliers"]["stat_scale"]["epic"] = 9.0
    errors, _ = validator.validate(root, tables)
    assert errors, "сломанная монотонность обязана ловиться"


# --- бэкапы -------------------------------------------------------------------

def test_backup_and_rollback_roundtrip(root: Path) -> None:
    battle = configs.read_config(root, "battle.json")
    original = json.dumps(battle, sort_keys=True)

    stamp = backups.snapshot(root, changed=["battle.json"])
    battle["strikes"]["strike_damage"] = 99
    configs.write_config(root, "battle.json", battle)
    assert configs.read_config(
        root, "battle.json")["strikes"]["strike_damage"] == 99

    backups.rollback(root, stamp)
    restored = configs.read_config(root, "battle.json")
    assert json.dumps(restored, sort_keys=True) == original

    # Откат сам снял точку pre_rollback — дорога назад не одностороняя
    notes = [b.get("note", "") for b in backups.list_backups(root)]
    assert any("pre_rollback" in n for n in notes)


# --- .tres --------------------------------------------------------------------

def test_tres_patch_single_line(root: Path) -> None:
    path = root / "data" / "monsters" / "disco_sprout.tres"
    before = path.read_text(encoding="utf-8").splitlines()
    tres.patch_field(path, "motif_id", "zarya")
    after = path.read_text(encoding="utf-8").splitlines()
    diff = [i for i, (a, b) in enumerate(zip(before, after)) if a != b]
    assert len(diff) == 1, "патч обязан менять ровно одну строку"
    assert 'motif_id = "zarya"' in after[diff[0]]


def test_tres_patch_refuses_missing_field(root: Path) -> None:
    path = root / "data" / "monsters" / "disco_sprout.tres"
    with pytest.raises(KeyError):
        tres.patch_field(path, "no_such_field", 1)


def test_tres_noop_patch_is_identical(root: Path) -> None:
    path = root / "data" / "monsters" / "disco_sprout.tres"
    before = path.read_bytes()
    fields = tres.read_fields(path)
    tres.patch_field(path, "motif_id", fields["motif_id"])
    assert path.read_bytes() == before
