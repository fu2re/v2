class_name Registry
extends RefCounted

## Реестр игрового контента. Сканирует каталоги с .tres, чтобы добавление
## монстра или фрукта не требовало правки кода — только нового файла.

const MONSTER_DIR := "res://data/monsters"
const FRUIT_DIR := "res://data/fruits"
const GEAR_DIR := "res://data/gear"
const COSMETIC_DIR := "res://data/cosmetics"

static var _monsters: Dictionary = {}
static var _fruits: Dictionary = {}
static var _gear: Dictionary = {}
static var _cosmetics: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_monsters = _scan(MONSTER_DIR)
	_fruits = _scan(FRUIT_DIR)
	_gear = _scan(GEAR_DIR)
	_cosmetics = _scan(COSMETIC_DIR)
	_apply_balance_stats()
	_loaded = true


## Перечитать каталоги и таблицы статов заново — для редактора и тестов,
## правящих данные на ходу. Одного Balance.reload() мало: числа уже
## накачаны в закешированные ресурсы, и без пересканирования там останутся
## старые значения.
static func reload() -> void:
	_loaded = false
	ensure_loaded()


## Числа сущностей живут в JSON (monsters.json / gear.json / cosmetics.json),
## а .tres хранит только идентичность: имя, жанр, слот, спрайт. Здесь таблицы
## накатываются на загруженные ресурсы — источник чисел ровно один.
## Вида нет в таблице — ошибка данных: остаются дефолты класса, о чём и кричим.
static func _apply_balance_stats() -> void:
	for id: String in _monsters:
		var stats := Balance.monster_stats(id)
		if stats.is_empty():
			push_error("Монстра %s нет в data/monsters.json — статы остались дефолтными" % id)
			continue
		var m: MonsterData = _monsters[id]
		m.base_vibe = int(stats.get("base_vibe", m.base_vibe))
		m.base_health = int(stats.get("base_health", m.base_health))
		m.base_power = float(stats.get("base_power", m.base_power))

	for id: String in _gear:
		var stats := Balance.gear_stats(id)
		if stats.is_empty():
			push_error("Снаряжения %s нет в data/gear.json — числа остались дефолтными" % id)
			continue
		var g: GearData = _gear[id]
		g.window_scale = float(stats.get("window_scale", g.window_scale))
		g.power_bonus = float(stats.get("power_bonus", g.power_bonus))
		g.health_bonus = int(stats.get("health_bonus", g.health_bonus))
		g.shield_reduction = float(stats.get("shield_reduction", g.shield_reduction))
		g.price = int(stats.get("price", g.price))

	for id: String in _cosmetics:
		var stats := Balance.cosmetic_stats(id)
		if stats.is_empty():
			push_error("Косметики %s нет в data/cosmetics.json — числа остались дефолтными" % id)
			continue
		var c: CosmeticData = _cosmetics[id]
		c.price_gold = int(stats.get("price_gold", c.price_gold))
		var rarity_index := Balance.grade_index(String(stats.get("rarity", "")))
		if rarity_index >= 0:
			c.rarity = rarity_index as MonsterData.Rarity
		c.in_crates = bool(stats.get("in_crates", c.in_crates))


static func _scan(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Каталог данных не найден: %s" % dir_path)
		return out

	for file_name in dir.get_files():
		# В экспортированной сборке .tres лежат как .remap
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [dir_path, clean])
		if res == null or not ("id" in res) or String(res.id).is_empty():
			push_warning("Ресурс без id пропущен: %s/%s" % [dir_path, clean])
			continue
		out[res.id] = res
	return out


static func monster(id: String) -> MonsterData:
	ensure_loaded()
	return _monsters.get(id)


static func fruit(id: String) -> FruitData:
	ensure_loaded()
	return _fruits.get(id)


static func gear(id: String) -> GearData:
	ensure_loaded()
	return _gear.get(id)


static func all_gear() -> Array[GearData]:
	ensure_loaded()
	var out: Array[GearData] = []
	for g: GearData in _gear.values():
		out.append(g)
	out.sort_custom(func(a, b): return a.price < b.price)
	return out


static func gear_for_slot(slot: GearData.Slot) -> Array[GearData]:
	var out: Array[GearData] = []
	for g in all_gear():
		if g.slot == slot:
			out.append(g)
	return out


static func all_monsters() -> Array[MonsterData]:
	ensure_loaded()
	var out: Array[MonsterData] = []
	for m: MonsterData in _monsters.values():
		out.append(m)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func all_fruits() -> Array[FruitData]:
	ensure_loaded()
	var out: Array[FruitData] = []
	for f: FruitData in _fruits.values():
		out.append(f)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func cosmetic(id: String) -> CosmeticData:
	ensure_loaded()
	return _cosmetics.get(id)


static func all_cosmetics() -> Array[CosmeticData]:
	ensure_loaded()
	var out: Array[CosmeticData] = []
	for c: CosmeticData in _cosmetics.values():
		out.append(c)
	out.sort_custom(func(a, b): return a.price_gold < b.price_gold)
	return out
