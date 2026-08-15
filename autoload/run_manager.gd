extends Node

## Состояние забега: глубина, сквозное здоровье, добыча.
##
## Добыча копится ОТДЕЛЬНО от постоянного инвентаря и переносится в него
## только при выходе. Так работает мягкая смерть (GDD §8.4): при обнулении
## здоровья теряется половина добычи забега, но не коллекция и не дружба.

signal run_started(guardian_id: String)
signal glade_entered(glade: Glade)
signal run_ended(died: bool, kept_fruits: int, kept_seeds: int)
signal health_changed(current: int, maximum: int)

## Доля добычи, теряемая при смерти. Половина, а не всё: ребёнок должен
## уносить домой хоть что-то с каждого забега.
const DEATH_LOSS := 0.5

## Награды растут с глубиной (GDD §8.3).
const REWARD_DEPTH_SCALE := 0.15
const BASE_SEEDS := 8

## Доли грейдов на поверхности: обычный, необычный, редкий, уникальный,
## эпический, легендарный.
const BASE_RARITY_WEIGHTS := [52.0, 26.0, 13.0, 6.0, 2.5, 0.5]
const RARITY_SHIFT_PER_GLADES := 10.0
const MAX_RARITY_SHIFT := 3.0

## Обычные монстры никогда не исчезают полностью.
##
## Даже на самой большой глубине шанс редкого не достигает 100%: встреча
## с легендарным обязана оставаться удачей, а не расписанием. Гарантированная
## редкость обесценила бы и её саму, и радость от неё.
const MIN_COMMON_WEIGHT := 12.0

const CAMPFIRE_RESTORE := 25

var is_active: bool = false
var depth: int = 0
var guardian_id: String = ""
var health: int = 100
var max_health: int = 100
## Щит тоже сквозной: забег на выносливость, и буфер не обновляется
## на каждой поляне. Чинится только попаданиями по нотам-щитам.
var shield: int = BattleState.BASE_SHIELD
var max_shield: int = BattleState.BASE_SHIELD
var current_glade: Glade = null

## Добыча забега: ключ фрукта -> количество.
var run_fruits: Dictionary = {}
## Семена для грядок: fruit_id -> количество. Отдельно от фруктов,
## потому что это разные сущности: семя сажают, фрукт скармливают монстру.
var run_seed_bag: Dictionary = {}
var run_silver: int = 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Зерно для воспроизводимости в тестах.
func set_seed(value: int) -> void:
	_rng.seed = value


func start_run(new_guardian_id: String) -> bool:
	var guardian := Registry.monster(new_guardian_id)
	if guardian == null:
		push_error("Гуардиан не найден: %s" % new_guardian_id)
		return false

	guardian_id = new_guardian_id
	max_health = guardian.base_health \
		+ int(GameState.gear_bonuses(new_guardian_id).get("health_bonus", 0))
	health = max_health
	max_shield = BattleState.BASE_SHIELD
	shield = max_shield
	depth = 0
	run_fruits.clear()
	run_seed_bag.clear()
	run_silver = 0
	current_glade = null
	is_active = true

	run_started.emit(guardian_id)
	health_changed.emit(health, max_health)
	return true


## Следующая поляна. Свайп вверх — единственный способ идти вперёд.
func advance() -> Glade:
	if not is_active:
		return null
	depth += 1
	current_glade = _generate(depth)
	glade_entered.emit(current_glade)
	# Автосейв между полянами: игру на телефоне закрывают посреди сессии
	SaveManager.mark_dirty()
	return current_glade


func _generate(for_depth: int) -> Glade:
	var glade := Glade.new()
	glade.depth = for_depth
	glade.type = _pick_type()
	glade.silver_reward = int(round(BASE_SEEDS * (1.0 + REWARD_DEPTH_SCALE * for_depth)))

	match glade.type:
		Glade.Type.BATTLE:
			glade.monster_id = _pick_monster(for_depth)
		Glade.Type.WILD_BUSH:
			var fruits := Registry.all_fruits()
			if not fruits.is_empty():
				glade.fruit_id = fruits[_rng.randi_range(0, fruits.size() - 1)].id
	return glade


func _pick_type() -> Glade.Type:
	var total := 0.0
	for weight: int in Glade.WEIGHTS.values():
		total += weight
	var roll := _rng.randf() * total
	for type: Glade.Type in Glade.WEIGHTS:
		roll -= Glade.WEIGHTS[type]
		if roll <= 0.0:
			return type
	return Glade.Type.BATTLE


## Чем глубже, тем выше доля редких монстров. Сдвиг ограничен, иначе
## на 40-й поляне встречались бы одни легендарные и редкость обесценилась бы.
func rarity_weights(for_depth: int) -> Array:
	var shift := minf(for_depth / RARITY_SHIFT_PER_GLADES, MAX_RARITY_SHIFT)
	return [
		maxf(BASE_RARITY_WEIGHTS[0] - 11.0 * shift, MIN_COMMON_WEIGHT),
		BASE_RARITY_WEIGHTS[1],
		BASE_RARITY_WEIGHTS[2] + 3.5 * shift,
		BASE_RARITY_WEIGHTS[3] + 3.0 * shift,
		BASE_RARITY_WEIGHTS[4] + 2.0 * shift,
		BASE_RARITY_WEIGHTS[5] + 0.8 * shift,
	]


func _pick_monster(for_depth: int) -> String:
	var weights := rarity_weights(for_depth)
	var total := 0.0
	for w: float in weights:
		total += w

	var roll := _rng.randf() * total
	var chosen := 0
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			chosen = i
			break

	# Если монстров выбранной редкости нет, спускаемся вниз, а не падаем:
	# контент добавляется постепенно, и дыра в пуле не должна ломать забег
	for rarity in range(chosen, -1, -1):
		var pool := Registry.monsters_of_rarity(rarity)
		if not pool.is_empty():
			return pool[_rng.randi_range(0, pool.size() - 1)].id

	var all := Registry.all_monsters()
	return all[0].id if not all.is_empty() else ""


# --- здоровье --------------------------------------------------------------------

func set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	health_changed.emit(health, max_health)


func set_shield(value: int) -> void:
	shield = clampi(value, 0, max_shield)


func restore_health(amount: int) -> void:
	set_health(health + amount)


func rest_at_campfire() -> void:
	restore_health(CAMPFIRE_RESTORE)


## Сменить гуардиана у костра — единственная точка смены внутри забега.
##
## Здоровье переносится ДОЛЕЙ, а не числом: иначе смена на существо с большим
## запасом лечила бы бесплатно, и костёр превратился бы в кнопку хила.
func swap_guardian(monster_id: String) -> bool:
	if not is_active or not GameState.is_tamed(monster_id):
		return false
	var monster := Registry.monster(monster_id)
	if monster == null:
		return false

	var ratio := float(health) / maxf(max_health, 1.0)
	guardian_id = monster_id
	max_health = monster.base_health + int(GameState.gear_bonuses(monster_id).get("health_bonus", 0))
	set_health(int(round(max_health * ratio)))
	return true


# --- добыча ------------------------------------------------------------------

func add_loot_fruit(fruit_id: String, quality: FruitData.Quality, count: int = 1) -> void:
	var key := GameState.fruit_key(fruit_id, quality)
	run_fruits[key] = run_fruits.get(key, 0) + count


func add_loot_seed(fruit_id: String, count: int = 1) -> void:
	run_seed_bag[fruit_id] = run_seed_bag.get(fruit_id, 0) + count


func add_loot_silver(amount: int) -> void:
	run_silver += amount


func total_loot_fruits() -> int:
	var total := 0
	for count: int in run_fruits.values():
		total += count
	return total


# --- завершение --------------------------------------------------------------

## Уйти домой по своей воле — вся добыча сохраняется.
func go_home() -> void:
	_end(false)


## Здоровье кончилось. Гуардиан устал, половина добычи теряется.
func die() -> void:
	_end(true)


func _end(died: bool) -> void:
	if not is_active:
		return

	var kept_fruits := 0
	for key: String in run_fruits:
		var count: int = run_fruits[key]
		var kept := int(floor(count * (1.0 - DEATH_LOSS))) if died else count
		if kept <= 0:
			continue
		var parts := key.split(":")
		GameState.add_fruit(parts[0], int(parts[1]) as FruitData.Quality, kept)
		kept_fruits += kept

	var kept_seeds := int(floor(run_silver * (1.0 - DEATH_LOSS))) if died else run_silver
	GameState.add_silver(kept_seeds)

	# Семена новых культур переживают смерть целиком.
	# Потерять только что открытый вид — это откат прогресса, а не потеря
	# добычи, и ребёнок воспримет это как наказание за попытку
	for fruit_id: String in run_seed_bag:
		FarmState.add_seed(fruit_id, run_seed_bag[fruit_id])

	is_active = false
	current_glade = null
	run_fruits.clear()
	run_seed_bag.clear()
	run_silver = 0

	SaveManager.save_game()
	run_ended.emit(died, kept_fruits, kept_seeds)


## Шансы выпадения снаряжения за победу, по грейду монстра.
##
## Это НЕ платный лутбокс: он не покупается и не связан с деньгами, поэтому
## регуляторные правила §12.3 к нему не относятся. Но принцип «открытие
## не пропадает впустую» действует и здесь — сундук всегда что-то даёт.
const VICTORY_DROP_ODDS := {
	MonsterData.Rarity.COMMON: [70.0, 25.0, 5.0],
	MonsterData.Rarity.UNCOMMON: [55.0, 33.0, 12.0],
	MonsterData.Rarity.RARE: [40.0, 38.0, 22.0],
	MonsterData.Rarity.UNIQUE: [25.0, 42.0, 33.0],
	MonsterData.Rarity.EPIC: [15.0, 40.0, 45.0],
	MonsterData.Rarity.LEGENDARY: [5.0, 35.0, 60.0],
}


## Выдать снаряжение за побеждённого монстра. Возвращает id или пустую строку.
##
## Чем выше грейд монстра, тем выше шанс дорогой вещи. Награда обязана
## отражать риск: иначе редкие монстры не стоят того, чтобы за ними идти.
func roll_victory_gear(monster: MonsterData) -> String:
	if monster == null:
		return ""
	var odds: Array = VICTORY_DROP_ODDS.get(monster.rarity, [70.0, 25.0, 5.0])

	var total := 0.0
	for w: float in odds:
		total += w
	var roll := _rng.randf() * total
	var tier := 0
	for i in odds.size():
		roll -= odds[i]
		if roll <= 0.0:
			tier = i
			break

	# Снаряжение отсортировано по цене — она и есть мера ценности
	var pool := Registry.all_gear()
	if pool.is_empty():
		return ""
	var per_tier := maxi(pool.size() / odds.size(), 1)
	var from := mini(tier * per_tier, pool.size() - 1)
	var to := mini(from + per_tier, pool.size())
	var item: GearData = pool[_rng.randi_range(from, to - 1)]
	GameState.add_gear(item.id)
	return item.id
