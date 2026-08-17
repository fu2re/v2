class_name Balance
extends RefCounted

## Балансовые таблицы игры: грейды, уровни, дружба, дроп.
##
## Числа лежат в JSON рядом с GDD и правятся дизайнером без программиста.
## До появления этого класса таблицы объявляли себя источником истины
## («расхождение кода и таблицы — баг»), но кодом не читались ни строчкой —
## и успели разойтись: множитель легендарного был 1.7 в коде против 2.0
## в таблице. Теперь источник ровно один.
##
## Статический класс, а не автозагрузчик: тесты гоняются headless и дёргают
## баланс без дерева сцен, как и Registry.

const PROGRESSION_PATH := "res://data/progression.json"
const DROP_TABLES_PATH := "res://data/drop_tables.json"
const MERCHANT_PATH := "res://data/merchant.json"
const FRUITS_PATH := "res://data/fruits.json"
const BATTLE_PATH := "res://data/battle.json"
const MONSTERS_PATH := "res://data/monsters.json"
const GEAR_PATH := "res://data/gear.json"
const COSMETICS_PATH := "res://data/cosmetics.json"

## Порядок грейдов. Совпадает с MonsterData.Rarity и с ключами в JSON —
## имя грейда служит ключом во всех таблицах.
const GRADE_KEYS := ["common", "uncommon", "rare", "unique", "epic", "legendary"]

## Запасных КОПИЙ таблиц здесь больше нет — только нейтральные заглушки
## в геттерах. Копии требовали теста паритета «fallback == JSON», а он
## краснел бы от каждой легитимной правки баланса в редакторе. Игра
## по-прежнему не падает из-за данных: битый JSON — это плохая картинка
## баланса (и push_error в логе), а не конец сессии. Полноту таблиц
## сторожит tests/test_balance_tables.gd (_test_tables_complete).

static var _progression: Dictionary = {}
static var _drops: Dictionary = {}
static var _merchant: Dictionary = {}
static var _fruits: Dictionary = {}
static var _battle: Dictionary = {}
static var _monsters: Dictionary = {}
static var _gear: Dictionary = {}
static var _cosmetics: Dictionary = {}
static var _loaded := false

## Кеш горячего пути. Judge.grade() дёргается на каждый тап, а подача нот —
## каждый кадр: ходить по словарям там нельзя, поэтому скаляры оценки
## разбираются один раз при загрузке в типизированные поля.
static var _judge_perfect: float = 0.05
static var _judge_good: float = 0.11
static var _judge_late: float = 0.18
static var _judge_effects: Dictionary = {}
static var _combo_steps: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_progression = _read(PROGRESSION_PATH)
	_drops = _read(DROP_TABLES_PATH)
	_merchant = _read(MERCHANT_PATH)
	_fruits = _read(FRUITS_PATH)
	_battle = _read(BATTLE_PATH)
	_monsters = _read(MONSTERS_PATH)
	_gear = _read(GEAR_PATH)
	_cosmetics = _read(COSMETICS_PATH)
	_cache_battle_scalars()
	_loaded = true


static func _cache_battle_scalars() -> void:
	var judge := _section(_battle, "judge")
	_judge_perfect = float(judge.get("perfect_window", 0.05))
	_judge_good = float(judge.get("good_window", 0.11))
	_judge_late = float(judge.get("late_window", 0.18))
	_judge_effects = _section(judge, "effects")
	var steps: Variant = judge.get("combo_steps", [])
	_combo_steps = steps if typeof(steps) == TYPE_ARRAY else []


## Перечитать таблицы. Нужно редактору и тестам, правящим JSON на ходу.
static func reload() -> void:
	_loaded = false
	ensure_loaded()


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Таблица баланса не найдена: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Таблица баланса повреждена: %s" % path)
		return {}
	return parsed


## Вложенная секция таблицы. Чтение из Dictionary даёт Variant,
## поэтому тип указан явно везде — иначе парсер валит весь скрипт.
static func _section(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func grade_index(key: String) -> int:
	return GRADE_KEYS.find(key)


static func grade_key(grade: int) -> String:
	return GRADE_KEYS[clampi(grade, 0, GRADE_KEYS.size() - 1)]


# --- грейды ------------------------------------------------------------------

## Множитель статов по грейду. ОДИН И ТОТ ЖЕ для дикого монстра и для
## приручённого (GDD §6.3): грейд — свойство существа, а не роль в бою.
static func grade_stat_scale(grade: int) -> float:
	ensure_loaded()
	var multipliers := _section(_progression, "grade_multipliers")
	var scales := _section(multipliers, "stat_scale")
	var value: Variant = scales.get(grade_key(grade), null)
	if value == null:
		push_error("Нет множителя статов для грейда %s" % grade_key(grade))
		return 1.0
	return float(value)


## Насколько больно бьёт дикий монстр этого грейда.
##
## Отдельная шкала, и разрыв в ней намеренно круче, чем у крепости: обычный
## должен щекотать, а эпический — пугать по-настоящему. Пока обе величины
## шли по одной кривой, эпический бил лишь чуть сильнее обычного, и грейд
## читался только подписью в углу, а не тем, что происходит на экране.
static func grade_strike_scale(grade: int) -> float:
	ensure_loaded()
	var multipliers := _section(_progression, "grade_multipliers")
	var scales := _section(multipliers, "strike_scale")
	var value: Variant = scales.get(grade_key(grade), null)
	if value == null:
		push_error("Нет множителя удара для грейда %s" % grade_key(grade))
		return 1.0
	return float(value)


## Рост Настроя монстра с глубиной забега: +доля за каждую поляну (GDD §8.3).
## Поверх грейда, который остаётся главным множителем сложности.
static func vibe_depth_scale() -> float:
	ensure_loaded()
	var battle := _section(_progression, "battle")
	return float(battle.get("vibe_depth_scale", 0.05))


# --- дружба ------------------------------------------------------------------

## Порог дружбы для грейда. У каждой пары «вид + грейд» своя независимая
## шкала (GDD §6.1): дружба с обычным экземпляром не приближает редкого.
static func friendship_threshold(grade: int) -> int:
	ensure_loaded()
	var friendship := _section(_progression, "friendship")
	var thresholds := _section(friendship, "thresholds")
	var value: Variant = thresholds.get(grade_key(grade), null)
	if value == null:
		push_error("Нет порога дружбы для грейда %s" % grade_key(grade))
		return 100
	return int(value)


## Прибавка дружбы за событие: победа, S-ранг, угощение (GDD §6.1).
## Ноль рандома. До этого геттера числа жили константами в GameState,
## а таблица объявляла себя источником истины, но не читалась ни строчкой.
static func friendship_gain(key: String) -> int:
	ensure_loaded()
	var friendship := _section(_progression, "friendship")
	var gains := _section(friendship, "gains")
	return int(gains.get(key, 0))


# --- уровни экземпляра -------------------------------------------------------

static func max_level() -> int:
	ensure_loaded()
	var levels := _section(_progression, "instance_levels")
	return int(levels.get("max_level", 10))


## Прибавка к статам за каждый уровень сверх первого.
static func level_stat_bonus() -> float:
	ensure_loaded()
	var levels := _section(_progression, "instance_levels")
	return float(levels.get("stat_bonus_per_level", 0.08))


## Суммарный опыт, нужный чтобы ДОСТИЧЬ этого уровня.
static func xp_for_level(level: int) -> int:
	ensure_loaded()
	var levels := _section(_progression, "instance_levels")
	var curve: Variant = levels.get("xp_to_next_level", [])
	var table: Array = curve if typeof(curve) == TYPE_ARRAY else []
	if table.is_empty():
		# Заглушка на случай битой таблицы: линейная лестница вместо кривой
		return clampi(level - 1, 0, max_level() - 1) * 100
	var index := clampi(level - 1, 0, table.size() - 1)
	return int(table[index])


## Опыт за угощение фруктом этого тира. Кормление — второй источник
## уровня рядом с боями: оно держит ферму в петле после приручения.
static func feeding_xp_for_tier(tier: int) -> int:
	ensure_loaded()
	var sources := _section(_progression, "xp_sources")
	var table: Variant = sources.get("feeding_by_fruit_tier", [])
	var values: Array = table if typeof(table) == TYPE_ARRAY else []
	if values.is_empty():
		return 10
	return int(values[clampi(tier, 0, values.size() - 1)])


static func feeding_favorite_multiplier() -> float:
	ensure_loaded()
	var sources := _section(_progression, "xp_sources")
	return float(sources.get("feeding_favorite_multiplier", 2.0))


## Опыт за победу: база плюс надбавка за грейд противника и за чистый бой.
static func xp_for_victory(enemy_grade: int, s_rank: bool) -> int:
	ensure_loaded()
	var sources := _section(_progression, "xp_sources")
	var base := int(sources.get("battle_victory_base", 25))
	var per_grade := int(sources.get("battle_victory_per_enemy_grade", 10))
	var bonus := int(sources.get("battle_victory_s_rank_bonus", 15))
	return base + per_grade * enemy_grade + (bonus if s_rank else 0)


## Опыт за бой, в котором монстр устоял.
##
## Меньше, чем за победу, но не ноль: иначе новичок, которому пока нечем
## добить, застревает намертво — бой обязателен, победить нечем, а гуардиан
## не растёт. Танцевал — значит учился, и это ровно то же основание,
## по которому опыт против вида даётся и за проигранный бой (GDD §6.4).
static func xp_for_defeat(enemy_grade: int) -> int:
	ensure_loaded()
	var sources := _section(_progression, "xp_sources")
	var share := float(sources.get("battle_defeat_share", 0.5))
	return int(round(xp_for_victory(enemy_grade, false) * share))


# --- опыт против вида --------------------------------------------------------

static func species_xp_step() -> float:
	ensure_loaded()
	var xp := _section(_progression, "species_experience")
	return float(xp.get("damage_step_per_encounter", 0.04))


static func species_xp_cap() -> float:
	ensure_loaded()
	var xp := _section(_progression, "species_experience")
	return float(xp.get("damage_cap", 0.6))


# --- поляны и встречи --------------------------------------------------------

static func glade_weights() -> Dictionary:
	ensure_loaded()
	var types := _section(_drops, "glade_types")
	var weights := _section(types, "weights_percent")
	if weights.is_empty():
		# Заглушка на случай битой таблицы: лента из одних боёв — заметно
		# сломанная, но играбельная
		push_error("Веса полян не прочитались — лента только из боёв")
		return {"battle": 100.0}
	return weights


static func encounter_weights() -> Dictionary:
	ensure_loaded()
	var types := _section(_drops, "encounter_types")
	return _section(types, "weights_percent")


static func loot_bush_weights() -> Dictionary:
	ensure_loaded()
	var bush := _section(_drops, "loot_bush")
	return _section(bush, "weights_percent")


static func granny_gift_weights() -> Dictionary:
	ensure_loaded()
	var granny := _section(_drops, "granny")
	return _section(granny, "gift_weights_percent")


# --- грейд встреченного монстра ----------------------------------------------

## Веса грейдов на глубине d — ступенчатая таблица by_depth: действует
## последняя строка, чей from_depth уже достигнут. Была формула со сдвигом
## и порогами, но семь её крутилок всё равно проверяли по таблице примеров —
## теперь таблица и есть баланс: что записано, то и выпадает (GDD §6.3).
static func rarity_weights(depth: int) -> PackedFloat32Array:
	ensure_loaded()
	var table := _section(_drops, "monster_rarity_by_depth")
	var rows: Variant = table.get("by_depth", [])
	var list: Array = rows if typeof(rows) == TYPE_ARRAY else []

	var row: Dictionary = {}
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if depth >= int(entry.get("from_depth", 0)):
			row = entry
	if row.is_empty():
		# Заглушка на случай битой таблицы: все встречи обычные — заметно
		# сломанная, но играбельная лента
		push_error("Таблица редкости by_depth пуста или не достигнута")
		return PackedFloat32Array([100.0, 0.0, 0.0, 0.0, 0.0, 0.0])

	var out := PackedFloat32Array()
	for key: String in GRADE_KEYS:
		out.append(maxf(float(row.get(key, 0.0)), 0.0))
	return out


## Шансы тира сундука за победу над монстром этого грейда.
static func victory_chest_odds(grade: int) -> PackedFloat32Array:
	ensure_loaded()
	var chest := _section(_drops, "victory_chest")
	var odds := _section(chest, "odds_percent_by_monster_rarity")
	var row := _section(odds, grade_key(grade))
	var out := PackedFloat32Array()
	for tier in ["cheap", "mid", "expensive"]:
		out.append(float(row.get(tier, 0.0)))
	if out[0] + out[1] + out[2] <= 0.0:
		return PackedFloat32Array([70.0, 25.0, 5.0])
	return out


## Шанс, что сундук вообще выпадет за победу (GDD §8.1.2).
##
## Отдельно от долей тиров: те отвечают на «что именно», а этот — на «дадут ли
## вообще». Пока сундук падал всегда, снаряжение перестало быть событием.
static func victory_chest_chance(grade: int) -> float:
	ensure_loaded()
	var chest := _section(_drops, "victory_chest")
	var chances := _section(chest, "drop_chance_percent_by_monster_rarity")
	return float(chances.get(grade_key(grade), 10.0)) / 100.0


## Шанс подобрать с дикого куста ещё и фрукт. Мал намеренно: фрукты растят
## на грядке, и если их можно набрать в лесу, ферма становится лишней.
static func wild_bush_fruit_chance() -> float:
	ensure_loaded()
	var bush := _section(_drops, "wild_bush")
	var yield_row := _section(bush, "yield")
	return float(yield_row.get("fruit_chance_percent", 15.0)) / 100.0


## Сколько семян даёт куст. Всегда: семена — то, ради чего к нему подходят.
static func wild_bush_seeds() -> int:
	ensure_loaded()
	var yield_row := _section(_section(_drops, "wild_bush"), "yield")
	return int(yield_row.get("seed_of_same_fruit", 1))


## Сколько плодов даёт удачный куст — тех самых пятнадцати процентов.
static func wild_bush_lucky_fruits() -> int:
	ensure_loaded()
	var yield_row := _section(_section(_drops, "wild_bush"), "yield")
	return int(yield_row.get("fruits_when_lucky", 1))


# --- торговец ----------------------------------------------------------------

## Цена семени по тиру. У семян нет своего ресурса, поэтому цена живёт
## в таблице торговца, а не в данных фрукта.
static func seed_price(tier: int) -> int:
	ensure_loaded()
	var prices := _section(_merchant, "prices_silver")
	var by_tier := _section(prices, "seeds_by_tier")
	var value: Variant = by_tier.get(str(tier), null)
	if value == null:
		# Запасная лестница: каждый следующий тир заметно дороже предыдущего
		return [15, 40, 100, 250][clampi(tier, 0, 3)]
	return int(value)


## Период ротации витрины усадьбы. В таблице — минуты (их читает человек),
## коду нужны секунды.
static func merchant_rotation_seconds() -> int:
	ensure_loaded()
	var farm := _section(_merchant, "farm_merchant")
	return int(farm.get("rotation_minutes", 10)) * 60


## Сколько вещей в ротации витрины усадьбы сверх постоянных семян.
static func farm_gear_slots() -> int:
	ensure_loaded()
	var farm := _section(_merchant, "farm_merchant")
	return int(farm.get("rotating_gear_slots", 2))


## Сколько товаров у лесного торговца.
static func forest_merchant_slots() -> int:
	ensure_loaded()
	var forest := _section(_merchant, "forest_merchant")
	return int(forest.get("stock_size", 3))


## Семена каких культур продаются в лавках. Базовые — те же, что в стартовом
## наборе; дикие виды добываются только с кустов в лесу (GDD §7.3): продавать
## их значило бы обесценить весь контур «лес → семена → ферма».
static func base_seed_ids() -> Array:
	ensure_loaded()
	var farm := _section(_merchant, "farm_merchant")
	var value: Variant = farm.get("base_seed_ids", [])
	var ids: Array = value if typeof(value) == TYPE_ARRAY else []
	return ids if not ids.is_empty() else ["drum_berry", "echo_pear"]


# --- серебро забега ----------------------------------------------------------

## База серебра за поляну. Формула одна на все награды забега:
## base * (1 + depth_scale * depth), округление на стороне вызова.
static func base_silver() -> int:
	ensure_loaded()
	return int(_section(_drops, "run_rewards").get("base_silver_per_glade", 8))


static func reward_depth_scale() -> float:
	ensure_loaded()
	return float(_section(_drops, "run_rewards").get("depth_scale", 0.15))


## База горсти серебра из куста с лутом — меньше поляны: встреча-бонус
## не должна обгонять честный бой.
static func loot_bush_silver_base() -> float:
	ensure_loaded()
	return float(_section(_drops, "run_rewards").get("loot_bush_silver_base", 5))


## Утешительные монетки от бабки, когда подарочный пул пуст.
static func granny_fallback_silver() -> int:
	ensure_loaded()
	return int(_section(_drops, "run_rewards").get("granny_fallback_silver", 12))


# --- бабка -------------------------------------------------------------------

## Доля серебра игрока, которую просит бабка: минимум и максимум.
## Просьба никогда не превышает наличие — проверяется на стороне вызова.
static func granny_ask_fraction() -> Vector2:
	ensure_loaded()
	var granny := _section(_drops, "granny")
	var low := float(granny.get("ask_min_fraction", 0.10))
	var high := float(granny.get("ask_max_fraction", 0.40))
	return Vector2(minf(low, high), maxf(low, high))


# --- мягкая смерть -----------------------------------------------------------

## Доля добычи, теряемая при обнулении здоровья (GDD §8.4).
## Половина, а не всё: ребёнок должен уносить домой хоть что-то.
static func soft_death_loss(kind: String) -> float:
	ensure_loaded()
	var death := _section(_drops, "soft_death")
	var lost := _section(death, "lost_percent")
	return clampf(float(lost.get(kind, 50.0)) / 100.0, 0.0, 1.0)


# --- пластинки (платный лутбокс) ---------------------------------------------

static func _crate() -> Dictionary:
	ensure_loaded()
	return _section(_drops, "cosmetic_crate")


static func crate_price() -> int:
	return int(_crate().get("price_gold", 120))


## Шансы по грейдам: индекс грейда -> процент. В словаре ТОЛЬКО грейды,
## записанные в таблице: строка с пустым пулом — ложь в публикуемых шансах
## (SHOP.md §4), и её отсутствие здесь проверяется тестом магазина.
static func crate_odds() -> Dictionary:
	var odds := _section(_crate(), "odds_percent_by_rarity")
	var out: Dictionary = {}
	for i in GRADE_KEYS.size():
		var key: String = GRADE_KEYS[i]
		if odds.has(key):
			out[i] = float(odds[key])
	if out.is_empty():
		out = {0: 60.0, 1: 27.0, 3: 13.0}
	return out


static func crate_pity_threshold() -> int:
	var pity := _section(_crate(), "pity")
	return int(pity.get("guaranteed_after_opens", 30))


static func crate_pity_min_rarity() -> int:
	var pity := _section(_crate(), "pity")
	var index := grade_index(String(pity.get("min_rarity", "unique")))
	return index if index >= 0 else 3


## Возврат за дубль. Отсутствующая строка — ошибка данных (SHOP.md §4);
## на этот случай берётся самая щедрая из имеющихся: обидеть игрока
## хуже, чем переплатить ему золотом.
static func crate_duplicate_refund(rarity: int) -> int:
	var refunds := _section(_crate(), "duplicate_refund_gold")
	var value: Variant = refunds.get(grade_key(rarity), null)
	if value != null:
		return int(value)
	push_error("Нет возврата за дубль грейда %s" % grade_key(rarity))
	var best := 15
	for entry: Variant in refunds.values():
		if typeof(entry) != TYPE_STRING:
			best = maxi(best, int(entry))
	return best


static func lootbox_banned_regions() -> Array:
	var value: Variant = _crate().get("banned_regions", [])
	var regions: Array = value if typeof(value) == TYPE_ARRAY else []
	return regions if not regions.is_empty() else ["BE", "NL"]


# --- фрукты -------------------------------------------------------------------

## Строка таблицы для тира семечка. Пустая — тир не описан, и вызывающий
## обязан подставить запасное значение сам.
static func fruit_tier(tier: int) -> Dictionary:
	ensure_loaded()
	var tiers := _section(_fruits, "tiers")
	var value: Variant = tiers.get(str(clampi(tier, 0, 3)), null)
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Время роста в секундах. Здесь и нигде больше: раньше оно жило константой
## в `FruitData`, и подкрутить его без программиста было нельзя.
static func fruit_grow_seconds(tier: int) -> int:
	var row := fruit_tier(tier)
	return int(row.get("grow_seconds", [600, 1800, 7200, 28800][clampi(tier, 0, 3)]))


## Во сколько раз плод тира щедрее самого простого при угощении.
static func fruit_friendship_scale(tier: int) -> float:
	var row := fruit_tier(tier)
	return float(row.get("friendship_scale", [1.0, 1.7, 2.7, 4.0][clampi(tier, 0, 3)]))


## Сколько здоровья вернёт плод, съеденный у костра (GDD §8.2.3).
static func fruit_heal(tier: int) -> int:
	var row := fruit_tier(tier)
	return int(row.get("heal", [12, 22, 36, 55][clampi(tier, 0, 3)]))


## Что плод даёт сверх лечения: доля к защите, прибавка к удару или окно.
## Пустой словарь — тир без бафа, и это нормально.
static func fruit_buff(tier: int) -> Dictionary:
	var row := fruit_tier(tier)
	var value: Variant = row.get("buff", {})
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Потолок каждого бафа за забег. Без него достаточно съесть десяток яблок,
## чтобы окно попадания перестало что-либо значить.
static func fruit_buff_cap(key: String) -> float:
	ensure_loaded()
	var buffs := _section(_fruits, "buffs")
	var caps := _section(buffs, "max_total")
	return float(caps.get(key, 0.0))


# --- статы сущностей (monsters.json / gear.json / cosmetics.json) ------------
# Числа видов и предметов. Registry накатывает их на загруженные ресурсы;
# пустая строка означает «вида нет в таблице» — это ошибка данных,
# и Registry оставит дефолты класса, а валидатор тестов её поймает.

static func monster_stats(id: String) -> Dictionary:
	ensure_loaded()
	return _section(_section(_monsters, "species"), id)


static func gear_stats(id: String) -> Dictionary:
	ensure_loaded()
	return _section(_section(_gear, "items"), id)


static func cosmetic_stats(id: String) -> Dictionary:
	ensure_loaded()
	return _section(_section(_cosmetics, "items"), id)


# --- бой: удары и щит (battle.json) ------------------------------------------
# Дизайн-обоснования чисел — прозой в самой таблице, рядом со значениями.

static func _battle_section(key: String) -> Dictionary:
	ensure_loaded()
	return _section(_battle, key)


static func strike_damage() -> int:
	return int(_battle_section("strikes").get("strike_damage", 15))


static func crit_multiplier() -> int:
	return int(_battle_section("strikes").get("crit_multiplier", 4))


## Тяжёлый удар — производная, а не отдельное число: особая нота ВСЕГДА
## вчетверо (crit_multiplier) больнее обычной, и разъехаться им нельзя.
static func heavy_strike_damage() -> int:
	return strike_damage() * crit_multiplier()


static func miss_damage() -> int:
	return int(_battle_section("strikes").get("miss_damage", 3))


static func skill_miss_damage() -> int:
	return int(_battle_section("strikes").get("skill_miss_damage", 6))


static func stray_free_taps() -> int:
	return int(_battle_section("strikes").get("stray_free_taps", 3))


static func stray_tap_damage() -> int:
	return int(_battle_section("strikes").get("stray_tap_damage", 2))


static func max_blow_share() -> float:
	return float(_battle_section("strikes").get("max_blow_share", 0.9))


static func attack_multiplier() -> float:
	return float(_battle_section("attack").get("attack_multiplier", 2.2))


static func min_series_length() -> int:
	return int(_battle_section("attack").get("min_series_length", 3))


static func base_shield() -> int:
	return int(_battle_section("shield").get("base_shield", 40))


static func shield_restore() -> int:
	return int(_battle_section("shield").get("shield_restore", 2))


# --- бой: спецдвижения -------------------------------------------------------

static func skill_attack_bonus() -> float:
	return float(_battle_section("skills").get("attack_bonus", 1.5))


static func skill_shield_gain() -> int:
	return int(_battle_section("skills").get("shield_gain", 6))


static func skill_health_gain() -> int:
	return int(_battle_section("skills").get("health_gain", 5))


static func skill_combo_gain() -> int:
	return int(_battle_section("skills").get("combo_gain", 5))


static func skill_window_boost() -> float:
	return float(_battle_section("skills").get("window_boost", 1.25))


static func skill_window_bars() -> float:
	return float(_battle_section("skills").get("window_bars", 4.0))


# --- бой: оценка тайминга ----------------------------------------------------
# Горячий путь: значения отдаются из кеша, заполненного при загрузке.

static func judge_perfect_window() -> float:
	ensure_loaded()
	return _judge_perfect


static func judge_good_window() -> float:
	ensure_loaded()
	return _judge_good


static func judge_late_window() -> float:
	ensure_loaded()
	return _judge_late


static func judge_effect(key: String) -> float:
	ensure_loaded()
	return float(_judge_effects.get(key, 0.0))


## Множитель комбо: шаги таблицы проверяются от старших к младшим,
## ниже первого порога — 1.0.
static func combo_multiplier(combo: int) -> float:
	ensure_loaded()
	var best := 1.0
	var best_combo := -1
	for entry: Variant in _combo_steps:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var threshold := int(entry.get("combo", 0))
		if combo >= threshold and threshold > best_combo:
			best_combo = threshold
			best = float(entry.get("multiplier", 1.0))
	return best


# --- бой: матчапы стихий -----------------------------------------------------

## Отношение защищающегося к стихии атакующего. Значения — для читаемости
## вызывающих: словесное имя вместо числа-множителя, потому что одному и тому же
## отношению соответствуют РАЗНЫЕ множители в зависимости от направления
## (уязвимость монстра ×1.4, уязвимость гуардиана ×2.0).
enum ElementRelation { NEUTRAL, DEFENDER_VULNERABLE, DEFENDER_RESISTS }


## Монстр уязвим к стихии гуардиана — урон гуардиана растёт.
static func element_vulnerability_outgoing() -> float:
	return float(_battle_section("elements").get("vulnerability_outgoing", 1.4))


## Гуардиан уязвим к стихии монстра — весь входящий урон растёт.
static func element_vulnerability_incoming() -> float:
	return float(_battle_section("elements").get("vulnerability_incoming", 2.0))


## Сопротивление режет урон в ту сторону, где оно есть.
static func element_resistance() -> float:
	return float(_battle_section("elements").get("resistance", 0.5))


## Явные матчапы стихий: ключ -> {vulnerable_to: [...], resists: [...]}.
## Списки, а не кольцо: при сотне видов граф станет произвольным.
static func element_matchups() -> Dictionary:
	return _section(_battle_section("elements"), "matchups")


## Как защищающийся относится к стихии атакующего — по СПИСКАМ защищающегося:
## уязвимость и сопротивление принадлежат тому, кто их испытывает.
static func element_relation(attacker_key: String, defender_key: String) -> ElementRelation:
	var row := _section(element_matchups(), defender_key)
	var vulnerable: Variant = row.get("vulnerable_to", [])
	if typeof(vulnerable) == TYPE_ARRAY and (vulnerable as Array).has(attacker_key):
		return ElementRelation.DEFENDER_VULNERABLE
	var resists: Variant = row.get("resists", [])
	if typeof(resists) == TYPE_ARRAY and (resists as Array).has(attacker_key):
		return ElementRelation.DEFENDER_RESISTS
	return ElementRelation.NEUTRAL


# --- бой: штраф урона по грейдам ---------------------------------------------

## Множитель урона гуардиана по монстру, чей грейд выше на gap ступеней.
## Свой грейд и ниже — без штрафа; за концом таблицы действует последнее
## значение: стена не может кончиться от того, что таблицу забыли дописать.
static func grade_gap_scale(gap: int) -> float:
	ensure_loaded()
	var table: Variant = _section(_battle, "grade_gap").get("outgoing_by_gap", [])
	var scales: Array = table if typeof(table) == TYPE_ARRAY else []
	if scales.is_empty():
		return 1.0
	if gap <= 0:
		return float(scales[0])
	return float(scales[clampi(gap, 0, scales.size() - 1)])
