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

## Порядок грейдов. Совпадает с MonsterData.Rarity и с ключами в JSON —
## имя грейда служит ключом во всех таблицах.
const GRADE_KEYS := ["common", "uncommon", "rare", "unique", "epic", "legendary"]

## Запасные значения на случай испорченного или отсутствующего файла.
##
## Игра не имеет права упасть из-за данных: битый JSON — это плохая картинка
## баланса, а не конец сессии. Тот же принцип, что в ChartLoader.
const FALLBACK_STAT_SCALE := [1.0, 1.15, 1.3, 1.5, 1.7, 2.0]
const FALLBACK_STRIKE_SCALE := [1.0, 1.4, 2.0, 2.8, 3.8, 5.0]
const FALLBACK_THRESHOLDS := [100, 150, 200, 250, 300, 400]
const FALLBACK_XP_CURVE := [0, 100, 220, 370, 550, 770, 1030, 1340, 1700, 2120]
const FALLBACK_GLADE_WEIGHTS := {"battle": 65.0, "wild_bush": 12.0, "campfire": 8.0, "encounter": 15.0}

static var _progression: Dictionary = {}
static var _drops: Dictionary = {}
static var _merchant: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_progression = _read(PROGRESSION_PATH)
	_drops = _read(DROP_TABLES_PATH)
	_merchant = _read(MERCHANT_PATH)
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
	var floor_common := float(shift_section.get("common_floor", 12.0))
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


# --- бабка -------------------------------------------------------------------

## Доля серебра игрока, которую просит бабка: минимум и максимум.
## Просьба никогда не превышает наличие — проверяется на стороне вызова.
static func granny_ask_fraction() -> Vector2:
	ensure_loaded()
	var granny := _section(_drops, "granny")
	var low := float(granny.get("ask_min_fraction", 0.10))
	var high := float(granny.get("ask_max_fraction", 0.40))
	return Vector2(minf(low, high), maxf(low, high))
