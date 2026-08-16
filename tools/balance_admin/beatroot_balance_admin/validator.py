"""Валидатор балансовых таблиц: (errors, warnings), пусто — чисто.

Ошибки блокируют сохранение, предупреждения возвращаются рядом с успехом.
Контракт «список строк, пустой = чисто» — общий для chart.py:validate,
chart_validator.gd и manifest.py:check.

Инварианты продублированы в tests/test_balance_tables.gd и
tests/test_shop.gd — правь ОБА места (принятый в проекте паттерн:
см. chart_validator.gd <-> chart.py). Сохранение, прошедшее валидатор,
обязано оставлять ./run_tests.sh зелёным.
"""

from __future__ import annotations

from pathlib import Path

from . import tres
from .refs import ENTITY_DIRS, GENRE_KEYS, GRADE_KEYS, chart_index, entity_ids

# Контракт правил разметки: минимальный интервал нот заморожен литералом
# в chart_validator.gd и chart.py. Окно GOOD, из которого он когда-то
# выводился, теперь в battle.json — сузить его можно, а вот расширить
# сверх этого предела значит молча инвалидировать все чарты.
FROZEN_MIN_NOTE_INTERVAL = 0.132

REQUIRED = {
    "progression.json": [
        "instance_levels.max_level",
        "instance_levels.stat_bonus_per_level",
        "instance_levels.xp_to_next_level",
        "xp_sources.battle_victory_base",
        "xp_sources.battle_victory_per_enemy_grade",
        "xp_sources.battle_victory_s_rank_bonus",
        "xp_sources.battle_defeat_share",
        "xp_sources.feeding_by_fruit_tier",
        "xp_sources.feeding_favorite_multiplier",
        "battle.vibe_depth_scale",
        "species_experience.damage_step_per_encounter",
        "species_experience.damage_cap",
        "friendship.gains.victory",
        "friendship.gains.victory_s_rank",
        "friendship.gains.favorite_fruit",
        "friendship.gains.other_fruit",
        *[f"grade_multipliers.stat_scale.{g}" for g in GRADE_KEYS],
        *[f"grade_multipliers.strike_scale.{g}" for g in GRADE_KEYS],
        *[f"friendship.thresholds.{g}" for g in GRADE_KEYS],
    ],
    "drop_tables.json": [
        "run_rewards.base_silver_per_glade",
        "run_rewards.depth_scale",
        "run_rewards.loot_bush_silver_base",
        "run_rewards.granny_fallback_silver",
        "glade_types.weights_percent.battle",
        "glade_types.weights_percent.wild_bush",
        "glade_types.weights_percent.campfire",
        "glade_types.weights_percent.encounter",
        "encounter_types.weights_percent.merchant",
        "loot_bush.weights_percent.silver_handful",
        "granny.ask_min_fraction",
        "granny.ask_max_fraction",
        "granny.gift_weights_percent.seed_tier_up",
        "monster_rarity_by_depth.depth_shift.divisor",
        "monster_rarity_by_depth.depth_shift.max_shift",
        "monster_rarity_by_depth.depth_shift.common_floor",
        "wild_bush.yield.seed_of_same_fruit",
        "wild_bush.yield.fruit_chance_percent",
        "wild_bush.yield.fruits_when_lucky",
        "soft_death.lost_percent.run_fruits",
        "soft_death.lost_percent.run_silver",
        "cosmetic_crate.price_gold",
        "cosmetic_crate.pity.guaranteed_after_opens",
        "cosmetic_crate.pity.min_rarity",
        *[f"monster_rarity_by_depth.base_weights.{g}" for g in GRADE_KEYS],
        *[f"monster_rarity_by_depth.unlock_depth.{g}" for g in GRADE_KEYS],
        *[f"monster_rarity_by_depth.depth_shift.per_shift.{g}" for g in GRADE_KEYS],
        *[f"victory_chest.drop_chance_percent_by_monster_rarity.{g}" for g in GRADE_KEYS],
        *[f"victory_chest.odds_percent_by_monster_rarity.{g}" for g in GRADE_KEYS],
    ],
    "merchant.json": [
        "forest_merchant.stock_size",
        "farm_merchant.rotation_minutes",
        "farm_merchant.rotating_gear_slots",
        "farm_merchant.base_seed_ids",
        *[f"prices_silver.seeds_by_tier.{t}" for t in range(4)],
    ],
    "fruits.json": [
        "buffs.max_total",
        *[f"tiers.{t}.{f}" for t in range(4)
          for f in ("grow_seconds", "friendship_scale", "heal")],
    ],
    "battle.json": [
        "strikes.strike_damage", "strikes.crit_multiplier", "strikes.miss_damage",
        "strikes.skill_miss_damage", "strikes.stray_free_taps",
        "strikes.stray_tap_damage", "strikes.max_blow_share",
        "attack.attack_multiplier", "attack.min_series_length",
        "shield.base_shield", "shield.shield_restore",
        "skills.attack_bonus", "skills.shield_gain", "skills.health_gain",
        "skills.combo_gain", "skills.window_boost", "skills.window_bars",
        "judge.perfect_window", "judge.good_window", "judge.late_window",
        "judge.effects.perfect", "judge.effects.good",
        "judge.effects.early_late", "judge.effects.miss",
        "judge.combo_steps",
        "genre.advantage_multiplier", "genre.disadvantage_multiplier",
        "genre.beats.rock",
    ],
}


def validate(root: Path, configs: dict[str, dict]) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    for name, paths in REQUIRED.items():
        data = configs.get(name)
        if data is None:
            errors.append(f"{name}: файл не прочитался")
            continue
        for path in paths:
            if _get(data, path) is None:
                errors.append(f"{name}: нет обязательного ключа {path}")

    if errors:
        # Без обязательных ключей остальные проверки посыплются вторичным
        # шумом — сначала полнота
        return errors, warnings

    _check_progression(configs["progression.json"], errors)
    _check_drop_tables(configs["drop_tables.json"], errors, warnings)
    _check_battle(configs["battle.json"], errors, warnings)
    _check_fruits(configs["fruits.json"], errors)
    _check_merchant(root, configs["merchant.json"], errors)
    _check_crate(root, configs["drop_tables.json"],
                 configs.get("cosmetics.json", {}), errors)
    _check_entities(root, configs, errors)
    return errors, warnings


# --- прогрессия ---------------------------------------------------------------

def _check_progression(data: dict, errors: list[str]) -> None:
    stat = _get(data, "grade_multipliers.stat_scale")
    strike = _get(data, "grade_multipliers.strike_scale")
    thresholds = _get(data, "friendship.thresholds")

    _check_monotonic(stat, "grade_multipliers.stat_scale", errors)
    _check_monotonic(strike, "grade_multipliers.strike_scale", errors)
    _check_monotonic(thresholds, "friendship.thresholds", errors)

    ratio = float(stat["legendary"]) / float(stat["common"])
    if not 1.8 <= ratio <= 2.2:
        errors.append(
            "progression.json: легендарный должен быть примерно вдвое крепче "
            f"обычного (GDD §6.3), сейчас x{ratio:.2f}")

    max_level = int(_get(data, "instance_levels.max_level"))
    curve = _get(data, "instance_levels.xp_to_next_level")
    if not isinstance(curve, list) or len(curve) != max_level:
        errors.append(
            f"progression.json: длина xp_to_next_level ({len(curve)}) "
            f"не равна max_level ({max_level})")
    else:
        if int(curve[0]) != 0:
            errors.append("progression.json: первый уровень обязан стоить 0 опыта")
        for i in range(1, len(curve)):
            if int(curve[i]) <= int(curve[i - 1]):
                errors.append(
                    f"progression.json: кривая опыта не растёт на ступени {i + 1}")
                break


def _check_monotonic(table: dict, label: str, errors: list[str]) -> None:
    previous = None
    for grade in GRADE_KEYS:
        value = float(table.get(grade, 0))
        if previous is not None and value <= previous:
            errors.append(
                f"progression.json: {label}.{grade} ({value:g}) "
                f"не больше предыдущего грейда ({previous:g})")
        previous = value


# --- дроп ---------------------------------------------------------------------

def _check_drop_tables(data: dict, errors: list[str],
                       warnings: list[str]) -> None:
    for label, path in [
        ("поляны", "glade_types.weights_percent"),
        ("встречи", "encounter_types.weights_percent"),
        ("куст с лутом", "loot_bush.weights_percent"),
        ("подарки бабки", "granny.gift_weights_percent"),
    ]:
        _check_sum_100(_get(data, path), f"drop_tables.json: доли «{label}»",
                       errors)

    odds = _get(data, "victory_chest.odds_percent_by_monster_rarity")
    for grade in GRADE_KEYS:
        row = odds.get(grade, {})
        if set(k for k in row if not k.startswith("_")) != {"cheap", "mid", "expensive"}:
            errors.append(
                f"drop_tables.json: у сундука грейда {grade} должны быть "
                "ровно тиры cheap/mid/expensive")
            continue
        _check_sum_100(row, f"drop_tables.json: шансы сундука грейда {grade}",
                       errors)

    for key in ("ask_min_fraction", "ask_max_fraction"):
        value = float(_get(data, f"granny.{key}"))
        if not 0.0 <= value <= 1.0:
            errors.append(f"drop_tables.json: granny.{key} должна быть долей 0..1")
    if float(_get(data, "granny.ask_min_fraction")) \
            > float(_get(data, "granny.ask_max_fraction")):
        errors.append("drop_tables.json: granny.ask_min_fraction больше максимума")

    for key, value in _get(data, "soft_death.lost_percent").items():
        if not _is_doc(key) and not 0 <= float(value) <= 100:
            errors.append(
                f"drop_tables.json: soft_death.lost_percent.{key} вне 0..100")

    chance = _get(data, "wild_bush.yield.fruit_chance_percent")
    if not 0 <= float(chance) <= 100:
        errors.append("drop_tables.json: fruit_chance_percent вне 0..100")

    divisor = float(_get(data, "monster_rarity_by_depth.depth_shift.divisor"))
    if divisor <= 0:
        errors.append("drop_tables.json: depth_shift.divisor должен быть больше нуля")

    _warn_examples_drift(data, warnings)


def _warn_examples_drift(data: dict, warnings: list[str]) -> None:
    """examples_percent — документация; она дрейфует, когда правят веса.

    Пересчёт повторяет Balance.rarity_weights (data/balance.gd) —
    при правке формулы там менять и здесь.
    """
    examples = _get(data, "monster_rarity_by_depth.examples_percent")
    if not isinstance(examples, dict):
        return
    for label, depth in [("depth_0", 0), ("depth_5", 5), ("depth_10", 10),
                         ("depth_15", 15), ("depth_20", 20),
                         ("depth_30_plus", 30)]:
        recorded = examples.get(label)
        if not isinstance(recorded, dict):
            continue
        actual = _rarity_percent(data, depth)
        for grade in GRADE_KEYS:
            want = float(recorded.get(grade, 0))
            got = actual[grade]
            if abs(want - got) > 1.5:
                warnings.append(
                    "drop_tables.json: examples_percent.%s разъехались с расчётом "
                    "(%s: записано %g, выходит %.0f) — это документация, обнови её"
                    % (label, grade, want, got))
                break


def _rarity_percent(data: dict, depth: int) -> dict[str, float]:
    table = _get(data, "monster_rarity_by_depth")
    shift_section = table["depth_shift"]
    shift = min(depth / float(shift_section["divisor"]),
                float(shift_section["max_shift"]))
    weights: dict[str, float] = {}
    for grade in GRADE_KEYS:
        if depth < int(table["unlock_depth"].get(grade, 0)):
            weights[grade] = 0.0
            continue
        value = float(table["base_weights"].get(grade, 0.0)) \
            + float(shift_section["per_shift"].get(grade, 0.0)) * shift
        if grade == "common":
            value = max(value, float(shift_section["common_floor"]))
        weights[grade] = max(value, 0.0)
    total = sum(weights.values())
    if total <= 0:
        return {g: 0.0 for g in GRADE_KEYS}
    return {g: w * 100.0 / total for g, w in weights.items()}


# --- бой ----------------------------------------------------------------------

def _check_battle(data: dict, errors: list[str], warnings: list[str]) -> None:
    perfect = float(_get(data, "judge.perfect_window"))
    good = float(_get(data, "judge.good_window"))
    late = float(_get(data, "judge.late_window"))
    if not perfect < good < late:
        errors.append(
            "battle.json: окна оценки обязаны быть строго упорядочены "
            f"(perfect {perfect:g} < good {good:g} < late {late:g})")
    if good * 1.2 > FROZEN_MIN_NOTE_INTERVAL + 1e-9:
        warnings.append(
            "battle.json: good_window * 1.2 (%.3f) превысил замороженный "
            "минимальный интервал нот %.3f (chart_validator.gd) — существующие "
            "чарты могут стать нечестными: окно тапа накроет соседние ноты"
            % (good * 1.2, FROZEN_MIN_NOTE_INTERVAL))

    steps = _get(data, "judge.combo_steps")
    previous_combo = 0
    previous_mult = 1.0
    for step in steps:
        combo = int(step.get("combo", 0))
        mult = float(step.get("multiplier", 0))
        if combo <= previous_combo:
            errors.append("battle.json: пороги combo_steps обязаны расти")
        if mult < previous_mult:
            errors.append("battle.json: множители combo_steps не должны убывать")
        previous_combo, previous_mult = combo, mult

    for path in ("strikes.strike_damage", "strikes.crit_multiplier",
                 "attack.attack_multiplier", "shield.base_shield"):
        if float(_get(data, path)) <= 0:
            errors.append(f"battle.json: {path} должен быть больше нуля")

    share = float(_get(data, "strikes.max_blow_share"))
    if not 0.0 < share <= 1.0:
        errors.append("battle.json: max_blow_share — доля в (0..1]")

    restore = int(_get(data, "shield.shield_restore"))
    if not 0 < restore <= 3:
        errors.append(
            "battle.json: shield_restore обязан быть 1..3 — щит чинится "
            "по чуть-чуть, иначе забег перестаёт быть испытанием "
            "(tests/test_fair_play.gd)")

    beats = _get(data, "genre.beats")
    for attacker, defender in beats.items():
        if _is_doc(attacker):
            continue
        if attacker not in GENRE_KEYS or str(defender) not in GENRE_KEYS:
            errors.append(
                f"battle.json: genre.beats {attacker} -> {defender} — "
                f"неизвестный жанр (допустимы {', '.join(GENRE_KEYS)})")


# --- фрукты и торговец --------------------------------------------------------

def _check_fruits(data: dict, errors: list[str]) -> None:
    for tier in range(4):
        row = _get(data, f"tiers.{tier}")
        if int(row.get("grow_seconds", 0)) <= 0:
            errors.append(f"fruits.json: tiers.{tier}.grow_seconds должно быть "
                          "больше нуля")
        if float(row.get("friendship_scale", 0)) <= 0:
            errors.append(f"fruits.json: tiers.{tier}.friendship_scale должна "
                          "быть больше нуля")


def _check_merchant(root: Path, data: dict, errors: list[str]) -> None:
    fruit_ids = set(entity_ids(root, "fruits"))
    for seed_id in _get(data, "farm_merchant.base_seed_ids"):
        if seed_id not in fruit_ids:
            errors.append(
                f"merchant.json: base_seed_ids содержит {seed_id}, "
                f"а такого фрукта нет (есть: {', '.join(sorted(fruit_ids))})")
    for tier in range(4):
        if int(_get(data, f"prices_silver.seeds_by_tier.{tier}")) <= 0:
            errors.append(f"merchant.json: цена семени тира {tier} должна быть "
                          "больше нуля")
    if int(_get(data, "farm_merchant.rotation_minutes")) <= 0:
        errors.append("merchant.json: rotation_minutes должно быть больше нуля")
    if int(_get(data, "forest_merchant.stock_size")) <= 0:
        errors.append("merchant.json: stock_size должен быть больше нуля")


# --- пластинка (SHOP.md §4) ---------------------------------------------------

def _check_crate(root: Path, drops: dict, cosmetics: dict,
                 errors: list[str]) -> None:
    crate = drops.get("cosmetic_crate", {})
    odds = {k: v for k, v in crate.get("odds_percent_by_rarity", {}).items()
            if not _is_doc(k)}
    refunds = {k: v for k, v in crate.get("duplicate_refund_gold", {}).items()
               if not _is_doc(k)}
    items = cosmetics.get("items", {})

    _check_sum_100(odds, "drop_tables.json: шансы пластинки", errors)

    price = int(crate.get("price_gold", 0))
    if price <= 0:
        errors.append("drop_tables.json: цена пластинки должна быть больше нуля")

    pity_rarity = str(_get(drops, "cosmetic_crate.pity.min_rarity"))
    if pity_rarity not in odds:
        errors.append(
            f"drop_tables.json: pity.min_rarity ({pity_rarity}) отсутствует "
            "в таблице шансов пластинки")

    for grade in odds:
        if grade not in GRADE_KEYS:
            errors.append(f"drop_tables.json: шансы пластинки: {grade} — "
                          "не грейд")
            continue
        pool = [cid for cid, row in items.items()
                if row.get("rarity") == grade and row.get("in_crates")]
        if not pool:
            errors.append(
                f"drop_tables.json: у грейда {grade} есть шанс в пластинке, "
                "но нет ни одной косметики этого грейда с in_crates — "
                "публикуемые шансы лгут (SHOP.md §4)")
            continue
        refund = refunds.get(grade)
        if refund is None:
            errors.append(f"drop_tables.json: нет возврата за дубль грейда "
                          f"{grade} (SHOP.md §4)")
        else:
            cheapest = min(int(items[cid].get("price_gold", 0)) for cid in pool)
            if int(refund) >= cheapest:
                errors.append(
                    f"drop_tables.json: возврат за дубль {grade} ({refund}) "
                    f"не меньше самой дешёвой вещи пула ({cheapest}) — "
                    "золото печатается")

    for cid, row in items.items():
        if row.get("in_crates") and str(row.get("rarity")) not in odds:
            errors.append(
                f"cosmetics.json: {cid} лежит в пуле пластинки, но у грейда "
                f"{row.get('rarity')} нет строки шансов (SHOP.md §4)")


# --- сущности -----------------------------------------------------------------

def _check_entities(root: Path, configs: dict[str, dict],
                    errors: list[str]) -> None:
    fruit_ids = set(entity_ids(root, "fruits"))
    motifs = set()
    charts = chart_index(root)
    try:
        import json as _json
        with open(root / "data" / "motifs.json", encoding="utf-8") as fh:
            motifs = {m["id"] for m in _json.load(fh).get("motifs", [])}
    except (OSError, ValueError):
        errors.append("data/motifs.json не прочитался")

    tables = {
        "monsters": ("monsters.json", "species"),
        "gear": ("gear.json", "items"),
        "cosmetics": ("cosmetics.json", "items"),
    }
    for kind, (file_name, section) in tables.items():
        table = configs.get(file_name, {}).get(section, {})
        tres_ids = set(entity_ids(root, kind))
        for entity_id in table:
            if entity_id not in tres_ids:
                errors.append(f"{file_name}: строка {entity_id} без .tres "
                              f"в data/{kind}/")
        for entity_id in tres_ids:
            if entity_id not in table:
                errors.append(f"{file_name}: нет строки для data/{kind}/"
                              f"{entity_id}.tres — статы останутся дефолтными")

    for row_id, row in configs.get("gear.json", {}).get("items", {}).items():
        if int(row.get("price", 0)) <= 0:
            errors.append(f"gear.json: цена {row_id} должна быть больше нуля — "
                          "по ней сортируются трети сундука")

    for row_id, row in configs.get("cosmetics.json", {}).get("items", {}).items():
        if int(row.get("price_gold", 0)) <= 0:
            errors.append(
                f"cosmetics.json: price_gold {row_id} обязана быть больше нуля: "
                "в Бельгии и Нидерландах весь состав сундуков продаётся "
                "напрямую (GDD §12.3)")
        if str(row.get("rarity")) not in GRADE_KEYS:
            errors.append(f"cosmetics.json: rarity {row_id} — не грейд-ключ")

    # Кросс-ссылки монстров: фрукт, мотив и полный комплект чартов
    for path in sorted((root / ENTITY_DIRS["monsters"]).glob("*.tres")):
        fields = tres.read_fields(path)
        monster_id = str(fields.get("id", path.stem))
        favorite = str(fields.get("favorite_fruit_id", ""))
        if favorite and favorite not in fruit_ids:
            errors.append(f"{monster_id}: любимый фрукт {favorite} не существует")
        motif = str(fields.get("motif_id", ""))
        if motifs and motif not in motifs:
            errors.append(f"{monster_id}: мотива {motif} нет в motifs.json")
        genre_index = int(fields.get("genre", -1))
        if not 0 <= genre_index < len(GENRE_KEYS):
            errors.append(f"{monster_id}: неизвестный жанр {genre_index}")
            continue
        pair = f"{GENRE_KEYS[genre_index]}_{motif}"
        have = set(charts.get(pair, []))
        missing = [g for g in GRADE_KEYS if g not in have]
        if missing:
            errors.append(
                f"{monster_id}: для {pair} нет чартов грейдов "
                f"{', '.join(missing)} — бой уйдёт на запасной трек")
        sprite = str(fields.get("sprite_path", ""))
        if sprite.startswith("res://") \
                and not (root / sprite.removeprefix("res://")).is_file():
            errors.append(f"{monster_id}: спрайт {sprite} не существует")


# --- утилиты ------------------------------------------------------------------

def _check_sum_100(table: dict, label: str, errors: list[str]) -> None:
    total = sum(float(v) for k, v in table.items() if not _is_doc(k))
    if abs(total - 100.0) > 0.01:
        errors.append(f"{label} обязаны давать 100% (сейчас {total:g})")


def _is_doc(key: str) -> bool:
    return key.startswith("_") or key in {"description", "note", "why", "formula"}


def _get(data: dict, dotted: str):
    node = data
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node
