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

## Порядок грейдов. Совпадает с MonsterData.Rarity и с ключами в JSON —
## имя грейда служит ключом во всех таблицах.
const GRADE_KEYS := ["common", "uncommon", "rare", "unique", "epic", "legendary"]

## Запасные значения на случай испорченного или отсутствующего файла.
##
## Игра не имеет права упасть из-за данных: битый JSON — это плохая картинка
## баланса, а не конец сессии. Тот же принцип, что в ChartLoader.
const FALLBACK_STAT_SCALE := [1.0, 1.15, 1.3, 1.5, 1.7, 2.0]
const FALLBACK_STRIKE_SCALE := [1.5, 1.9, 2.4, 3.1, 4.0, 5.0]
const FALLBACK_THRESHOLDS := [100, 150, 200, 250, 300, 400]
const FALLBACK_XP_CURVE := [0, 100, 220, 370, 550, 770, 1030, 1340, 1700, 2120]
const FALLBACK_GLADE_WEIGHTS := {"battle": 65.0, "wild_bush": 12.0, "campfire": 8.0, "encounter": 15.0}

static var _progression: Dictionary = {}
static var _drops: Dictionary = {}
static var _merchant: Dictionary = {}
static var _fruits: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_progression = _read(PROGRESSION_PATH)
	_drops = _read(DROP_TABLES_PATH)
	_merchant = _read(MERCHANT_PATH)
	_fruits = _read(FRUITS_PATH)
	_loaded = true


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
		return FALLBACK_STAT_SCALE[clampi(grade, 0, FALLBACK_STAT_SCALE.size() - 1)]
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
		return FALLBACK_STRIKE_SCALE[clampi(grade, 0, FALLBACK_STRIKE_SCALE.size() - 1)]
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
		return FALLBACK_THRESHOLDS[clampi(grade, 0, FALLBACK_THRESHOLDS.size() - 1)]
	return int(value)


## Запасные прибавки дружбы — копия progression.json → friendship.gains.
## Сверяются тестом с таблицей, как и остальные fallback'и.
const FALLBACK_FRIENDSHIP_GAINS := {
	"victory": 10, "victory_s_rank": 15, "favorite_fruit": 35, "other_fruit": 10,
}


## Прибавка дружбы за событие: победа, S-ранг, угощение (GDD §6.1).
## Ноль рандома. До этого геттера числа жили константами в GameState,
## а таблица объявляла себя источником истины, но не читалась ни строчкой.
static func friendship_gain(key: String) -> int:
	ensure_loaded()
	var friendship := _section(_progression, "friendship")
	var gains := _section(friendship, "gains")
	return int(gains.get(key, FALLBACK_FRIENDSHIP_GAINS.get(key, 0)))


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
		table = FALLBACK_XP_CURVE
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
	return weights if not weights.is_empty() else FALLBACK_GLADE_WEIGHTS


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

## Веса грейдов на глубине d. Сдвигаются к редким, но обычные не исчезают:
## приручение обычного должно оставаться лёгким на любой глубине (GDD §6.3).
static func rarity_weights(depth: int) -> PackedFloat32Array:
	ensure_loaded()
	var table := _section(_drops, "monster_rarity_by_depth")
	var base := _section(table, "base_weights")
	var shift_section := _section(table, "depth_shift")
	var per_shift := _section(shift_section, "per_shift")

	# Коэффициенты — отдельные поля, а не разбор текста формулы: поле "formula"
	# написано для человека, и правка описания не должна менять баланс
	var divisor := float(shift_section.get("divisor", 10.0))
	if divisor <= 0.0:
		divisor = 10.0
	var max_shift := float(shift_section.get("max_shift", 3.0))

	var shift := minf(float(depth) / divisor, max_shift)
	var floor_common := float(shift_section.get("common_floor", 15.0))
	var unlocks := _section(table, "unlock_depth")

	var out := PackedFloat32Array()
	for i in GRADE_KEYS.size():
		var key: String = GRADE_KEYS[i]

		# Порог глубины: до него грейд не встречается ВОВСЕ.
		#
		# Без порогов линейный сдвиг выдавал уникального уже на второй поляне —
		# игрок утыкался в непроходимый бой, не успев понять правила. У поверхности
		# должно быть почти сплошь обычное, а редкое — наградой за то,
		# что зашёл глубже
		var unlock := int(unlocks.get(key, 0))
		if depth < unlock:
			out.append(0.0)
			continue

		var start := float(base.get(key, FALLBACK_STAT_SCALE[i]))
		var step := float(per_shift.get(key, 0.0))
		var weight := start + step * shift
		if key == "common":
			weight = maxf(weight, floor_common)
		out.append(maxf(weight, 0.0))
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


## Семена каких культур продаются в лавках. Базовые — те же, что в стартовом
## наборе; дикие виды добываются только с кустов в лесу (GDD §7.3): продавать
## их значило бы обесценить весь контур «лес → семена → ферма».
static func base_seed_ids() -> Array:
	ensure_loaded()
	var farm := _section(_merchant, "farm_merchant")
	var value: Variant = farm.get("base_seed_ids", [])
	var ids: Array = value if typeof(value) == TYPE_ARRAY else []
	return ids if not ids.is_empty() else ["drum_berry", "echo_pear"]


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


## Ярлык качества по тиру. Только для показа: числа считаются от тира.
static func fruit_quality_label(tier: int) -> String:
	ensure_loaded()
	var labels := _section(_fruits, "quality_labels")
	return String(labels.get(str(clampi(tier, 0, 3)), "Обычный"))
