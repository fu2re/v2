extends Node

## Состояние забега: глубина, сквозной Ритм, добыча.
##
## Добыча копится ОТДЕЛЬНО от постоянного инвентаря и переносится в него
## только при выходе. Так работает мягкая смерть (GDD §8.4): при обнулении
## Ритма теряется половина добычи забега, но не коллекция и не дружба.

signal run_started(guardian_id: String)
signal glade_entered(glade: Glade)
signal run_ended(died: bool, kept_fruits: int, kept_seeds: int)
signal groove_changed(current: int, maximum: int)

## Доля добычи, теряемая при смерти. Половина, а не всё: ребёнок должен
## уносить домой хоть что-то с каждого забега.
const DEATH_LOSS := 0.5

## Награды растут с глубиной (GDD §8.3).
const REWARD_DEPTH_SCALE := 0.15
const BASE_SEEDS := 8

## Доли редкости на поверхности и предел сдвига вглубь (GDD §6.3).
const BASE_RARITY_WEIGHTS := [50.0, 28.0, 15.0, 6.0, 1.0]
const RARITY_SHIFT_PER_GLADES := 10.0
const MAX_RARITY_SHIFT := 3.0

const CAMPFIRE_RESTORE := 25

var is_active: bool = false
var depth: int = 0
var guardian_id: String = ""
var groove: int = 100
var max_groove: int = 100
var current_glade: Glade = null

## Добыча забега: ключ фрукта -> количество.
var run_fruits: Dictionary = {}
var run_seeds: int = 0

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
	max_groove = guardian.base_groove
	groove = max_groove
	depth = 0
	run_fruits.clear()
	run_seeds = 0
	current_glade = null
	is_active = true

	run_started.emit(guardian_id)
	groove_changed.emit(groove, max_groove)
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
	glade.seeds_reward = int(round(BASE_SEEDS * (1.0 + REWARD_DEPTH_SCALE * for_depth)))

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
		maxf(BASE_RARITY_WEIGHTS[0] - 12.0 * shift, 10.0),
		BASE_RARITY_WEIGHTS[1],
		BASE_RARITY_WEIGHTS[2] + 5.0 * shift,
		BASE_RARITY_WEIGHTS[3] + 5.0 * shift,
		BASE_RARITY_WEIGHTS[4] + 2.0 * shift,
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


# --- Ритм --------------------------------------------------------------------

func set_groove(value: int) -> void:
	groove = clampi(value, 0, max_groove)
	groove_changed.emit(groove, max_groove)


func restore_groove(amount: int) -> void:
	set_groove(groove + amount)


func rest_at_campfire() -> void:
	restore_groove(CAMPFIRE_RESTORE)


# --- добыча ------------------------------------------------------------------

func add_loot_fruit(fruit_id: String, quality: FruitData.Quality, count: int = 1) -> void:
	var key := GameState.fruit_key(fruit_id, quality)
	run_fruits[key] = run_fruits.get(key, 0) + count


func add_loot_seeds(amount: int) -> void:
	run_seeds += amount


func total_loot_fruits() -> int:
	var total := 0
	for count: int in run_fruits.values():
		total += count
	return total


# --- завершение --------------------------------------------------------------

## Уйти домой по своей воле — вся добыча сохраняется.
func go_home() -> void:
	_end(false)


## Ритм кончился. Гуардиан устал, половина добычи теряется.
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

	var kept_seeds := int(floor(run_seeds * (1.0 - DEATH_LOSS))) if died else run_seeds
	GameState.add_seeds(kept_seeds)

	is_active = false
	current_glade = null
	run_fruits.clear()
	run_seeds = 0

	SaveManager.save_game()
	run_ended.emit(died, kept_fruits, kept_seeds)
