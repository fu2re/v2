extends Node

## Постоянный прогресс игрока: коллекция, дружба, инвентарь.
##
## Дружба здесь ключевая: она НИКОГДА не сбрасывается — ни при смерти,
## ни между забегами. Худший исход встречи с монстром — «стало ближе»,
## а не «не получилось» (GDD §6.1). Это главная защита от детской фрустрации.

signal friendship_changed(monster_id: String, value: int, threshold: int)
signal monster_tamed(monster_id: String)
signal fruits_changed()
signal seeds_changed(amount: int)

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
## Мягкая валюта.
var seeds: int = 0


func reset() -> void:
	friendship.clear()
	tamed.clear()
	fruits.clear()
	seeds = 0


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


func add_seeds(amount: int) -> void:
	seeds = maxi(seeds + amount, 0)
	seeds_changed.emit(seeds)


# --- сериализация ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"friendship": friendship.duplicate(),
		"tamed": tamed.duplicate(),
		"fruits": fruits.duplicate(),
		"seeds": seeds,
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
	seeds = int(d.get("seeds", 0))

	tamed.clear()
	for id: Variant in d.get("tamed", []):
		tamed.append(String(id))
