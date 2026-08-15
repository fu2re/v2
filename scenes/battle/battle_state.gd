class_name BattleState
extends RefCounted

## Состояние одного дэнс-баттла. Чистая логика без узлов — тестируется headless.
##
## Терминология не косметическая (GDD §4): монстр не получает урон, а «сбивается
## с ритма»; победа — он остановился и слушает. Игра для детей 7+, и это
## отражено в именах, а не только в текстах на экране.

signal vibe_changed(current: int, maximum: int)
signal health_changed(current: int, maximum: int)
signal shield_changed(current: int, maximum: int)
signal combo_changed(combo: int, multiplier: float)
signal victory()
signal defeat()

## Урон за пропущенный щит — атака монстра дошла до цели.
const STRIKE_DAMAGE := 10
## Урон за обычный промах. Мал намеренно: щит гасит его несколько раз подряд,
## и ребёнок успевает поймать ритм прежде, чем это станет больно.
const MISS_DAMAGE := 3
## Сколько щита возвращает попадание по ноте-щиту.
const SHIELD_RESTORE := 8

## Базовый запас щита. Щит — буфер ОДНОГО боя: он полон на входе на поляну
## и восстанавливается только нотами-щитами. Здоровье, в отличие от него,
## сквозное на весь забег и само не возвращается.
const BASE_SHIELD := 40

## Рост Настроя монстра с глубиной забега (GDD §8.3).
const VIBE_DEPTH_SCALE := 0.12

var monster: MonsterData = null
var guardian: MonsterData = null
var depth: int = 0

var max_vibe: int = 100
var vibe: int = 100
var max_health: int = 100
var health: int = 100
var max_shield: int = BASE_SHIELD
var shield: int = BASE_SHIELD

## Суммарный эффект надетого на гуардиана. Считается один раз на бой
## и дальше не пересчитывается — снаряжение внутри боя не меняется.
var window_scale: float = 1.0
var power_bonus: float = 0.0
var shield_reduction: float = 0.0

var combo: int = 0
var max_combo: int = 0
var blocked: int = 0
var strikes_taken: int = 0

var grade_counts := {
	Judge.Grade.PERFECT: 0,
	Judge.Grade.GOOD: 0,
	Judge.Grade.EARLY_LATE: 0,
	Judge.Grade.MISS: 0,
}

var is_over: bool = false
var did_win: bool = false


func setup(new_monster: MonsterData, new_guardian: MonsterData,
		starting_health: int, run_depth: int = 0) -> void:
	monster = new_monster
	guardian = new_guardian
	depth = run_depth

	max_vibe = int(round(monster.base_vibe * (1.0 + VIBE_DEPTH_SCALE * depth)))
	vibe = max_vibe

	var bonuses := GameState.gear_bonuses(guardian.id) if guardian != null else {}
	window_scale = bonuses.get("window_scale", 1.0)
	power_bonus = bonuses.get("power_bonus", 0.0)
	shield_reduction = bonuses.get("shield_reduction", 0.0)

	# Здоровье сквозное: между полянами само не восстанавливается,
	# только у костра и перекусами. В этом всё напряжение забега
	max_health = (guardian.base_health if guardian != null else 100) \
		+ int(bonuses.get("health_bonus", 0))
	health = clampi(starting_health, 0, max_health)

	# Щит — буфер одного боя: на каждую поляну входим с полным
	max_shield = BASE_SHIELD
	shield = max_shield

	combo = 0
	max_combo = 0
	blocked = 0
	strikes_taken = 0
	is_over = false
	did_win = false
	for key in grade_counts:
		grade_counts[key] = 0


## Множитель урона гуардиана против жанра монстра.
func genre_multiplier() -> float:
	if guardian == null or monster == null:
		return 1.0
	return MonsterData.genre_multiplier(guardian.genre, monster.genre)


## Учесть оценку обычной ноты. Возвращает, насколько сбит Настрой.
func register_hit(grade: int) -> int:
	if is_over:
		return 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		_take_damage(MISS_DAMAGE)
		return 0

	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))

	var power := (guardian.base_power if guardian != null else 4.0) + power_bonus
	var amount := int(round(
		power * Judge.effect(grade) * Judge.combo_multiplier(combo) * genre_multiplier()
	))
	_reduce_vibe(amount)
	return amount


## Щит принят вовремя — атака погашена и щит немного восстановлен.
##
## Это единственный источник восстановления щита в бою, поэтому ноты-щиты
## превращаются из угрозы в возможность: за ними следят не только чтобы
## не пропустить, но и чтобы починить буфер.
func block_strike() -> void:
	if is_over:
		return
	blocked += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))
	restore_shield(SHIELD_RESTORE)


## Щит пропущен — атака монстра дошла до цели.
func take_strike() -> void:
	if is_over:
		return
	strikes_taken += 1
	grade_counts[Judge.Grade.MISS] += 1
	combo = 0
	combo_changed.emit(combo, 1.0)
	_take_damage(STRIKE_DAMAGE)


## Урон идёт СНАЧАЛА в щит и только потом в здоровье.
##
## Щит — это прощение: пока он держится, промахи стоят внимания, но не
## прогресса. Здоровье трогается только когда буфер выбит полностью.
func _take_damage(amount: int) -> void:
	# Амулет смягчает урон, но никогда не обнуляет его: механика,
	# за которой не надо следить, перестаёт быть механикой
	var damage := maxi(int(round(amount * (1.0 - shield_reduction))), 1)

	var absorbed := mini(shield, damage)
	if absorbed > 0:
		shield -= absorbed
		damage -= absorbed
		shield_changed.emit(shield, max_shield)

	if damage <= 0:
		return

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_finish(false)


func restore_shield(amount: int) -> void:
	if is_over:
		return
	shield = mini(shield + amount, max_shield)
	shield_changed.emit(shield, max_shield)


## Перекус восстанавливает Ритм.
func restore_health(amount: int) -> void:
	if is_over:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


func _reduce_vibe(amount: int) -> void:
	vibe = maxi(vibe - amount, 0)
	vibe_changed.emit(vibe, max_vibe)
	if vibe <= 0:
		_finish(true)


func _finish(won: bool) -> void:
	is_over = true
	did_win = won
	if won:
		victory.emit()
	else:
		defeat.emit()


## Трек кончился, а Настрой не сбит. Монстр устоял — но это не поражение:
## Здоровье цело, значит забег продолжается.
func finish_by_timeout() -> void:
	if not is_over:
		_finish(false)


## S-ранг: ни одного промаха и ни одной пропущенной атаки.
## Даёт больше дружбы (GDD §6.1).
func is_perfect_run() -> bool:
	return grade_counts[Judge.Grade.MISS] == 0 and strikes_taken == 0


func accuracy() -> float:
	var total := 0
	for count: int in grade_counts.values():
		total += count
	if total == 0:
		return 0.0
	# Тип указан явно: чтение из Dictionary даёт Variant, и вывод типа через := невозможен
	var weighted: float = (
		grade_counts[Judge.Grade.PERFECT] * 1.0
		+ grade_counts[Judge.Grade.GOOD] * 0.6
		+ grade_counts[Judge.Grade.EARLY_LATE] * 0.3
	)
	return weighted / total
