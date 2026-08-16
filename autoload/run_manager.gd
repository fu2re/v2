extends Node

## Состояние забега: глубина, сквозное здоровье, добыча.
##
## Добыча копится ОТДЕЛЬНО от постоянного инвентаря и переносится в него
## только при выходе. Так работает мягкая смерть (GDD §8.4): при обнулении
## здоровья теряется половина добычи забега, но не коллекция и не дружба.

signal run_started(guardian_key: String)
signal glade_entered(glade: Glade)
signal run_ended(died: bool, kept_fruits: int, kept_seeds: int)
signal health_changed(current: int, maximum: int)

## Доля добычи, теряемая при смерти. Половина, а не всё: ребёнок должен
## уносить домой хоть что-то с каждого забега.
const DEATH_LOSS := 0.5

## Награды растут с глубиной (GDD §8.3).
const REWARD_DEPTH_SCALE := 0.15
const BASE_SEEDS := 8

## Доли грейдов, сдвиг с глубиной и пол обычных живут в таблице
## `data/drop_tables.json` и читаются через `Balance.rarity_weights`.
##
## Обычные монстры никогда не исчезают полностью: даже на самой большой
## глубине шанс редкого не достигает 100%. Встреча с легендарным обязана
## оставаться удачей, а не расписанием.

## Костёр сам по себе НЕ лечит: у него едят фрукты (GDD §8.2.3).
##
## Зелий в игре нет, и лечение стоит угощения — тот же плод мог пойти монстру
## на дружбу. Это единственное настоящее решение внутри забега; даровое
## восстановление отняло бы у него весь смысл.

var is_active: bool = false
var depth: int = 0
## Ключ экземпляра, идущего в лес. Не вид: в забег берут конкретное
## существо со своим грейдом, уровнем и снаряжением.
var guardian_key: String = ""
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


func start_run(new_guardian_key: String) -> bool:
	var guardian := GameState.instance(new_guardian_key)
	if guardian == null:
		push_error("Гуардиан не найден: %s" % new_guardian_key)
		return false

	guardian_key = new_guardian_key
	# Запас здоровья считает сам экземпляр: в нём уже учтены грейд и уровень
	max_health = guardian.max_health() \
		+ int(GameState.gear_bonuses(new_guardian_key).get("health_bonus", 0))
	health = max_health
	max_shield = BattleState.BASE_SHIELD
	shield = max_shield
	depth = 0
	run_fruits.clear()
	run_seed_bag.clear()
	run_silver = 0
	run_buffs.clear()
	current_glade = null
	is_active = true

	run_started.emit(guardian_key)
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
			# Вид и грейд роллятся НЕЗАВИСИМО (GDD §6.3): раньше грейд
			# выбирался только чтобы найти вид с таким полем, и легендарным
			# мог быть лишь тот, кого таким нарисовали. Теперь любой вид
			# может встретиться в любом грейде
			glade.monster_id = _pick_species()
			glade.grade = _pick_grade(for_depth)
		Glade.Type.WILD_BUSH:
			var fruits := Registry.all_fruits()
			if not fruits.is_empty():
				glade.fruit_id = fruits[_rng.randi_range(0, fruits.size() - 1)].id
		Glade.Type.ENCOUNTER:
			glade.encounter = _pick_encounter()
	return glade


func _pick_type() -> Glade.Type:
	var weights := Balance.glade_weights()
	var picked := _pick_key(weights)
	for type: Glade.Type in Glade.TYPE_KEYS:
		if Glade.TYPE_KEYS[type] == picked:
			return type
	return Glade.Type.BATTLE


## Кто попался на поляне-встрече. Доли — в таблице; загадка пока весит ноль,
## и её доля уходит торговцу сама собой.
func _pick_encounter() -> Glade.Encounter:
	var weights := Balance.encounter_weights()
	var picked := _pick_key(weights)
	for kind: Glade.Encounter in Glade.ENCOUNTER_KEYS:
		if Glade.ENCOUNTER_KEYS[kind] == picked:
			return kind
	return Glade.Encounter.MERCHANT


## Розыгрыш по словарю «ключ -> вес». Возвращает ключ.
func _pick_key(weights: Dictionary) -> String:
	var total := 0.0
	for weight: float in weights.values():
		total += weight
	if total <= 0.0:
		return ""

	var roll := _rng.randf() * total
	for key: String in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return key
	return ""


## Чем глубже, тем выше доля редких монстров. Сдвиг ограничен, иначе
## на 40-й поляне встречались бы одни легендарные и редкость обесценилась бы.
func rarity_weights(for_depth: int) -> Array:
	var weights := Balance.rarity_weights(for_depth)
	var out: Array = []
	for w: float in weights:
		out.append(w)
	return out


## Какой вид встретился. Все виды равновероятны: редкость — свойство
## экземпляра, а не вида, и «редких видов» больше не существует.
func _pick_species() -> String:
	var pool := Registry.all_monsters()
	if pool.is_empty():
		return ""
	return pool[_rng.randi_range(0, pool.size() - 1)].id


## В каком грейде встретился. Чем глубже, тем выше доля редких.
func _pick_grade(for_depth: int) -> int:
	var weights := Balance.rarity_weights(for_depth)
	var total := 0.0
	for w: float in weights:
		total += w

	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return MonsterData.Rarity.COMMON


# --- здоровье --------------------------------------------------------------------

func set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	health_changed.emit(health, max_health)


func set_shield(value: int) -> void:
	shield = clampi(value, 0, max_shield)


func restore_health(amount: int) -> void:
	set_health(health + amount)


## Бафы, набранные за забег: ключ -> суммарная величина.
##
## Держатся до конца забега, а не одного боя: съеденный фрукт должен
## ощущаться вложением. Каждый упирается в свой потолок из таблицы —
## иначе достаточно съесть десяток яблок, и окно попадания перестаёт
## что-либо значить.
var run_buffs: Dictionary = {}


func add_buff(buff: Dictionary) -> void:
	for key: String in buff:
		var cap := Balance.fruit_buff_cap(key)
		var value := float(run_buffs.get(key, 0.0)) + float(buff[key])
		run_buffs[key] = minf(value, cap) if cap > 0.0 else value


func buff(key: String) -> float:
	return float(run_buffs.get(key, 0.0))


## Сменить гуардиана у костра — единственная точка смены внутри забега.
##
## Здоровье переносится ДОЛЕЙ, а не числом: иначе смена на существо с большим
## запасом лечила бы бесплатно, и костёр превратился бы в кнопку хила.
func swap_guardian(instance_key: String) -> bool:
	if not is_active:
		return false
	var guardian := GameState.instance(instance_key)
	if guardian == null:
		return false

	var ratio := float(health) / maxf(max_health, 1.0)
	guardian_key = instance_key
	max_health = guardian.max_health() \
		+ int(GameState.gear_bonuses(instance_key).get("health_bonus", 0))
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


## Шансы выпадения снаряжения за победу живут в `data/drop_tables.json`
## (секция `victory_chest`).
##
## Это НЕ платный лутбокс: он не покупается и не связан с деньгами, поэтому
## регуляторные правила лутбоксов к нему не относятся. Но принцип «открытие
## не пропадает впустую» действует и здесь — сундук всегда что-то даёт.


## Начислить гуардиану опыт за бой. Возвращает, сколько уровней взято.
##
## Опыт получает ТОТ, КТО ДРАЛСЯ, и растёт он от грейда противника: победа
## над легендарным обязана значить больше, чем над обычным, иначе выгоднее
## фармить самых безопасных (GDD §6.5).
##
## За убежавшего монстра опыт тоже идёт, только меньше. Без этого новичок
## запирается: бой с незнакомым видом обязателен, добить его пока нечем,
## а гуардиан от этих боёв не растёт — то есть не станет сильнее никогда.
## Танцевал — значит учился.
func reward_guardian_xp(enemy_grade: int, perfect: bool, won: bool = true) -> int:
	var guardian := GameState.instance(guardian_key)
	if guardian == null:
		return 0
	var amount := Balance.xp_for_victory(enemy_grade, perfect) if won \
		else Balance.xp_for_defeat(enemy_grade)
	var gained := guardian.add_xp(amount)
	if gained > 0:
		SaveManager.mark_dirty()
	return gained


# --- встречи -----------------------------------------------------------------

## Потрясти куст с гостинцами. Возвращает текст о добыче.
##
## Куст никогда не бывает пустым: «потряс и ничего» — это обещание,
## которое игра не сдержала, а для ребёнка такое обиднее, чем скромный приз.
func shake_bush(for_depth: int) -> String:
	var weights := Balance.loot_bush_weights()
	var picked := _pick_key(weights) if not weights.is_empty() else "silver_handful"

	match picked:
		"seed_random_known":
			var fruits := Registry.all_fruits()
			if not fruits.is_empty():
				var fruit: FruitData = fruits[_rng.randi_range(0, fruits.size() - 1)]
				add_loot_seed(fruit.id, 1)
				return "Семя: %s" % fruit.display_name
		"gear_chest_like_victory":
			var prize := roll_victory_gear(MonsterData.Rarity.COMMON)
			var item := Registry.gear(prize)
			if item != null:
				return "Сундук в ветвях: %s!" % item.display_name

	# Горсть серебра — и запасной вариант, если чего-то из пула не оказалось
	var silver := int(round(5.0 * (1.0 + REWARD_DEPTH_SCALE * for_depth)))
	add_loot_silver(silver)
	return "Горсть серебра: +%d" % silver


## Сколько просит бабушка. НИКОГДА не больше, чем есть у игрока.
func granny_request() -> int:
	if run_silver <= 0:
		return 0
	var fraction := Balance.granny_ask_fraction()
	var share := _rng.randf_range(fraction.x, fraction.y)
	return clampi(int(ceil(run_silver * share)), 1, run_silver)


## Отдать бабушке серебро и получить подарок. Возвращает текст о подарке.
func pay_granny(amount: int) -> String:
	var given := clampi(amount, 0, run_silver)
	add_loot_silver(-given)

	var weights := Balance.granny_gift_weights()
	var picked := _pick_key(weights) if not weights.is_empty() else "seed_high_tier"

	match picked:
		"seed_tier_up":
			var fruits := Registry.all_fruits()
			if not fruits.is_empty():
				# Семя повыше тиром: подарок должен быть чем-то, чего игрок
				# сам пока не вырастил
				var best: FruitData = fruits[0]
				for fruit in fruits:
					if fruit.tier > best.tier:
						best = fruit
				add_loot_seed(best.id, 1)
				return "Семя: %s" % best.display_name
		"gear_mid_tier":
			var prize := roll_victory_gear(MonsterData.Rarity.RARE)
			var item := Registry.gear(prize)
			if item != null:
				return "Свёрток: %s" % item.display_name

	# Зелье не влезло — бабушка даёт серебро. Подарок обязан быть
	# материальным: «тёплое слово» после того, как игрок отдал ей деньги,
	# читается как обман, а не как трогательность
	var coins := 12
	add_loot_silver(coins)
	return "Горсть монеток на дорожку: +%d" % coins


## Выдать снаряжение за побеждённого монстра. Возвращает id или пустую строку.
##
## Чем выше грейд монстра, тем выше шанс дорогой вещи. Награда обязана
## отражать риск: иначе редкие монстры не стоят того, чтобы за ними идти.
## Принимает ГРЕЙД, а не монстра: сундук зависит от того, насколько опасен был
## конкретный экземпляр, и вызывающему не нужно тащить сюда весь объект.
func roll_victory_gear(grade: int) -> String:
	# Сначала — выпадет ли сундук ВООБЩЕ. Пока он падал за каждую победу,
	# снаряжение перестало быть событием: вещей в ленте набиралось больше,
	# чем игрок успевал надеть, а торговец стал не нужен
	if _rng.randf() >= Balance.victory_chest_chance(grade):
		return ""

	var odds := Balance.victory_chest_odds(grade)

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
