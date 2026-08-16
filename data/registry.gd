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
	_loaded = true


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


## Монстры, доступные на заданной глубине забега. Чем глубже, тем выше
## шанс редких (GDD §8.3) — здесь только фильтр пула, розыгрыш в RunManager.
static func monsters_of_rarity(rarity: MonsterData.Rarity) -> Array[MonsterData]:
	var out: Array[MonsterData] = []
	for m in all_monsters():
		if m.rarity == rarity:
			out.append(m)
	return out


## Зелья, отсортированы по цене: дешёвое первым, как и снаряжение.
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
