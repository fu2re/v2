extends Node

## Постоянный прогресс игрока: коллекция, дружба, инвентарь.
##
## Дружба здесь ключевая: она НИКОГДА не сбрасывается — ни при смерти,
## ни между забегами. Худший исход встречи с монстром — «стало ближе»,
## а не «не получилось» (GDD §6.1). Это главная защита от детской фрустрации.

signal friendship_changed(monster_id: String, value: int, threshold: int)
signal monster_tamed(monster_id: String)
signal fruits_changed()
signal silver_changed(amount: int)
signal gear_changed()
signal guardian_changed(monster_id: String)

const SAVE_VERSION := 1

## Прибавки к дружбе (GDD §6.1). Ноль рандома.
const FRIENDSHIP_WIN := 10
const FRIENDSHIP_PERFECT_WIN := 15
const FRIENDSHIP_FAVORITE_FRUIT := 35
const FRIENDSHIP_OTHER_FRUIT := 10

## Дружба по виду монстра: id -> накопленные очки.
var friendship: Dictionary = {}
## Приручённые виды.
var tamed: Array[String] = []
## Фрукты в сумке: "fruit_id:quality" -> количество.
var fruits: Dictionary = {}
## Заработанная валюта: серебро.
var silver: int = 0

## Снаряжение в сундуке: gear_id -> количество.
var gear_owned: Dictionary = {}
## Надето на гуардианов: monster_id -> { slot(int) -> gear_id }.
## Снаряжение привязано к конкретному существу, а не к игроку: смена
## гуардиана должна быть настоящим решением, а не сменой скина.
var equipped: Dictionary = {}
## Кого берём в лес.
var active_guardian_id: String = ""


func reset() -> void:
	friendship.clear()
	tamed.clear()
	fruits.clear()
	silver = 0
	gear_owned.clear()
	equipped.clear()
	active_guardian_id = ""


# --- дружба и приручение -----------------------------------------------------

func get_friendship(monster_id: String) -> int:
	return friendship.get(monster_id, 0)


func is_tamed(monster_id: String) -> bool:
	return tamed.has(monster_id)


## Начислить дружбу. Возвращает true, если монстр только что присоединился.
##
## Прибавка не отбрасывается при переполнении и не требует броска кубика:
## заполнилась шкала — монстр твой, гарантированно.
func add_friendship(monster_id: String, amount: int) -> bool:
	var data := Registry.monster(monster_id)
	if data == null:
		push_error("Неизвестный монстр: %s" % monster_id)
		return false

	var threshold := data.friendship_threshold()
	var value: int = mini(get_friendship(monster_id) + amount, threshold)
	friendship[monster_id] = value
	friendship_changed.emit(monster_id, value, threshold)

	if value >= threshold and not is_tamed(monster_id):
		tamed.append(monster_id)
		monster_tamed.emit(monster_id)
		return true
	return false


## Сколько дружбы даст угощение этим фруктом. Считается отдельно от начисления,
## чтобы интерфейс мог показать цифру ДО подтверждения.
func friendship_from_fruit(monster_id: String, fruit_id: String,
		quality: FruitData.Quality) -> int:
	var data := Registry.monster(monster_id)
	if data == null:
		return 0
	var base := FRIENDSHIP_FAVORITE_FRUIT if data.favorite_fruit_id == fruit_id \
		else FRIENDSHIP_OTHER_FRUIT
	return int(round(base * FruitData.quality_multiplier(quality)))


# --- инвентарь фруктов -------------------------------------------------------

static func fruit_key(fruit_id: String, quality: FruitData.Quality) -> String:
	return "%s:%d" % [fruit_id, quality]


func add_fruit(fruit_id: String, quality: FruitData.Quality, count: int = 1) -> void:
	var key := fruit_key(fruit_id, quality)
	fruits[key] = fruits.get(key, 0) + count
	fruits_changed.emit()


func fruit_count(fruit_id: String, quality: FruitData.Quality) -> int:
	return fruits.get(fruit_key(fruit_id, quality), 0)


func total_fruit_count(fruit_id: String) -> int:
	var total := 0
	for quality in [FruitData.Quality.PLAIN, FruitData.Quality.JUICY, FruitData.Quality.PERFECT]:
		total += fruit_count(fruit_id, quality)
	return total


func consume_fruit(fruit_id: String, quality: FruitData.Quality) -> bool:
	var key := fruit_key(fruit_id, quality)
	var have: int = fruits.get(key, 0)
	if have <= 0:
		return false
	if have == 1:
		fruits.erase(key)
	else:
		fruits[key] = have - 1
	fruits_changed.emit()
	return true


func add_silver(amount: int) -> void:
	silver = maxi(silver + amount, 0)
	silver_changed.emit(silver)


# --- снаряжение --------------------------------------------------------------

func add_gear(gear_id: String, count: int = 1) -> void:
	if Registry.gear(gear_id) == null:
		push_error("Неизвестное снаряжение: %s" % gear_id)
		return
	gear_owned[gear_id] = gear_owned.get(gear_id, 0) + count
	gear_changed.emit()


func gear_count(gear_id: String) -> int:
	return gear_owned.get(gear_id, 0)


func owned_gear_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in gear_owned:
		if gear_owned[id] > 0:
			out.append(id)
	out.sort()
	return out


## Надеть предмет. Снятый возвращается в сундук — экипировка обратима,
## иначе игрок боится экспериментировать.
func equip(monster_id: String, gear_id: String) -> bool:
	var item := Registry.gear(gear_id)
	if item == null or gear_count(gear_id) <= 0:
		return false

	var slots: Dictionary = equipped.get(monster_id, {})
	var previous: String = slots.get(item.slot, "")
	if previous == gear_id:
		return false
	if not previous.is_empty():
		gear_owned[previous] = gear_count(previous) + 1

	gear_owned[gear_id] = gear_count(gear_id) - 1
	if gear_owned[gear_id] <= 0:
		gear_owned.erase(gear_id)

	slots[item.slot] = gear_id
	equipped[monster_id] = slots
	gear_changed.emit()
	return true


func unequip(monster_id: String, slot: GearData.Slot) -> bool:
	var slots: Dictionary = equipped.get(monster_id, {})
	var gear_id: String = slots.get(slot, "")
	if gear_id.is_empty():
		return false
	slots.erase(slot)
	equipped[monster_id] = slots
	gear_owned[gear_id] = gear_count(gear_id) + 1
	gear_changed.emit()
	return true


func equipped_gear(monster_id: String, slot: GearData.Slot) -> GearData:
	var slots: Dictionary = equipped.get(monster_id, {})
	var gear_id: String = slots.get(slot, "")
	return Registry.gear(gear_id) if not gear_id.is_empty() else null


## Суммарный эффект надетого. Считается в одном месте, чтобы бой и интерфейс
## не разъехались в трактовке одних и тех же чисел.
func gear_bonuses(monster_id: String) -> Dictionary:
	var total := {
		"window_scale": 1.0,
		"power_bonus": 0.0,
		"health_bonus": 0,
		"shield_reduction": 0.0,
	}
	for slot in [GearData.Slot.BOOTS, GearData.Slot.ACCESSORY, GearData.Slot.AMULET]:
		var item := equipped_gear(monster_id, slot)
		if item == null:
			continue
		# Окна перемножаются, остальное складывается: так два предмета
		# на окна не дают линейного взрыва прощения промахов
		total.window_scale *= item.window_scale
		total.power_bonus += item.power_bonus
		total.health_bonus += item.health_bonus
		total.shield_reduction = minf(total.shield_reduction + item.shield_reduction, 0.75)
	return total


## Кто пойдёт в лес. Если выбранный недоступен, берём первого приручённого.
func guardian_id() -> String:
	if not active_guardian_id.is_empty() and is_tamed(active_guardian_id):
		return active_guardian_id
	return tamed[0] if not tamed.is_empty() else ""


func set_guardian(monster_id: String) -> bool:
	if not is_tamed(monster_id):
		return false
	active_guardian_id = monster_id
	guardian_changed.emit(monster_id)
	return true


# --- сериализация ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"friendship": friendship.duplicate(),
		"tamed": tamed.duplicate(),
		"fruits": fruits.duplicate(),
		"silver": silver,
		"gear_owned": gear_owned.duplicate(),
		"equipped": equipped.duplicate(true),
		"active_guardian": active_guardian_id,
	}


func from_dict(d: Dictionary) -> void:
	# Схема версионируется с первого дня: миграция задним числом
	# на живых сейвах обходится куда дороже
	var version: int = int(d.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("Сейв новее игры (v%d > v%d), часть данных может пропасть"
			% [version, SAVE_VERSION])

	friendship = d.get("friendship", {})
	fruits = d.get("fruits", {})
	silver = int(d.get("silver", 0))
	gear_owned = d.get("gear_owned", {})
	active_guardian_id = d.get("active_guardian", "")

	# JSON не различает целые ключи: слоты возвращаются строками
	# и без обратного приведения экипировка молча перестала бы находиться
	equipped.clear()
	var raw: Dictionary = d.get("equipped", {})
	for monster_id: String in raw:
		var slots: Dictionary = {}
		for slot_key: Variant in raw[monster_id]:
			slots[int(slot_key)] = String(raw[monster_id][slot_key])
		equipped[monster_id] = slots

	tamed.clear()
	for id: Variant in d.get("tamed", []):
		tamed.append(String(id))
