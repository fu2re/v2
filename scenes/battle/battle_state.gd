class_name BattleState
extends RefCounted

## Состояние одного дэнс-баттла. Чистая логика без узлов — тестируется headless.
##
## Терминология не косметическая (GDD §4): монстр не получает урон, а «сбивается
## с ритма»; победа — он остановился и слушает. Игра для детей 7+, и это
## отражено в именах, а не только в текстах на экране.

signal vibe_changed(current: int, maximum: int)
signal groove_changed(current: int, maximum: int)
signal combo_changed(combo: int, multiplier: float)
signal victory()
signal defeat()

## Урон по Ритму за пропущенный щит. Единственный способ потерять Ритм:
## обычный промах не наказывает, а лишь замедляет (GDD §4.3).
const STRIKE_DAMAGE := 12

## Рост Настроя монстра с глубиной забега (GDD §8.3).
const VIBE_DEPTH_SCALE := 0.12

var monster: MonsterData = null
var guardian: MonsterData = null
var depth: int = 0

var max_vibe: int = 100
var vibe: int = 100
var max_groove: int = 100
var groove: int = 100

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
		starting_groove: int, run_depth: int = 0) -> void:
	monster = new_monster
	guardian = new_guardian
	depth = run_depth

	max_vibe = int(round(monster.base_vibe * (1.0 + VIBE_DEPTH_SCALE * depth)))
	vibe = max_vibe

	var bonuses := GameState.gear_bonuses(guardian.id) if guardian != null else {}
	window_scale = bonuses.get("window_scale", 1.0)
	power_bonus = bonuses.get("power_bonus", 0.0)
	shield_reduction = bonuses.get("shield_reduction", 0.0)

	# Ритм сквозной: он НЕ восстанавливается между полянами сам по себе,
	# только перекусами и событиями. В этом всё напряжение забега (GDD §4.4)
	max_groove = (guardian.base_groove if guardian != null else 100) \
		+ int(bonuses.get("groove_bonus", 0))
	groove = clampi(starting_groove, 0, max_groove)

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


## Щит принят вовремя — атака монстра погашена.
func block_strike() -> void:
	if is_over:
		return
	blocked += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))


## Щит пропущен — единственная ситуация, где игрок теряет Ритм.
func take_strike() -> void:
	if is_over:
		return
	strikes_taken += 1
	grade_counts[Judge.Grade.MISS] += 1
	combo = 0
	combo_changed.emit(combo, 1.0)

	# Амулет смягчает пропущенную атаку, но никогда не обнуляет её:
	# щит обязан оставаться механикой, за которой следят
	var damage := maxi(int(round(STRIKE_DAMAGE * (1.0 - shield_reduction))), 1)
	groove = maxi(groove - damage, 0)
	groove_changed.emit(groove, max_groove)
	if groove <= 0:
		_finish(false)


## Перекус восстанавливает Ритм.
func restore_groove(amount: int) -> void:
	if is_over:
		return
	groove = mini(groove + amount, max_groove)
	groove_changed.emit(groove, max_groove)


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
## Ритм цел, значит забег продолжается.
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
