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

## Базовый запас щита.
##
## Щит СКВОЗНОЙ, как и здоровье: забег — это испытание на выносливость,
## и буфер не обновляется на каждой поляне. Разница между ними в том,
## что щит чинится в бою нотами-щитами, а здоровье — только у костра.
const BASE_SHIELD := 40

## Рост Настроя монстра с глубиной забега (GDD §8.3).
const VIBE_DEPTH_SCALE := 0.05

## Сколько нот подряд обязана содержать серия, чтобы атака в её конце
## считалась заслуженной. Ниже — атака проходит, но слабее не бывает:
## короткие связки не должны давать тот же результат, что длинные.
const MIN_SERIES_LENGTH := 3

## Множитель атаки.
##
## Подобран так, чтобы чистое прохождение всего трека выбивало монстра
## примерно к его концу, а не на середине. Слишком крупный множитель
## обрывал бой раньше мелодии — это чинится здесь, а не в чарте.
## Охраняется тестом на длину боя.
const ATTACK_MULTIPLIER := 1.8

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

## Множитель урона монстра по грейду и множитель нашего урона от опыта.
var strike_scale: float = 1.0
var experience_scale: float = 1.0

var combo: int = 0
var max_combo: int = 0
var blocked: int = 0
var strikes_taken: int = 0

## Текущая серия. Атака в её конце сработает, только если серия чиста.
var series_length: int = 0
var series_clean: bool = true
var attacks_landed: int = 0
var attacks_wasted: int = 0

var grade_counts := {
	Judge.Grade.PERFECT: 0,
	Judge.Grade.GOOD: 0,
	Judge.Grade.EARLY_LATE: 0,
	Judge.Grade.MISS: 0,
}

var is_over: bool = false
var did_win: bool = false


func setup(new_monster: MonsterData, new_guardian: MonsterData,
		starting_health: int, run_depth: int = 0, starting_shield: int = -1) -> void:
	monster = new_monster
	guardian = new_guardian
	depth = run_depth

	# Крепость монстра складывается из трёх вещей: его собственного запаса,
	# грейда и глубины забега. Грейд — главный множитель: легендарный обязан
	# ощущаться как событие, а не как обычный бой с другой рамкой
	max_vibe = int(round(
		monster.base_vibe
		* MonsterData.rarity_vibe_scale(monster.rarity)
		* (1.0 + VIBE_DEPTH_SCALE * depth)
	))
	vibe = max_vibe

	# Урон монстра тоже растёт с грейдом
	strike_scale = MonsterData.rarity_power_scale(monster.rarity)

	# Опыт боёв против ВИДА: каждая встреча учит повадкам и добавляет урона.
	# Это то, что делает повторные встречи осмысленными, а не рутиной
	experience_scale = GameState.experience_multiplier(monster.id)

	var bonuses := GameState.gear_bonuses(guardian.id) if guardian != null else {}
	window_scale = bonuses.get("window_scale", 1.0)
	power_bonus = bonuses.get("power_bonus", 0.0)
	shield_reduction = bonuses.get("shield_reduction", 0.0)

	# Здоровье сквозное: между полянами само не восстанавливается,
	# только у костра и перекусами. В этом всё напряжение забега
	max_health = (guardian.base_health if guardian != null else 100) \
		+ int(bonuses.get("health_bonus", 0))
	health = clampi(starting_health, 0, max_health)

	# Щит переносится с прошлой поляны. -1 означает «начать с полного»
	# и нужен только для отдельных боёв вне забега: обучение, тесты
	max_shield = BASE_SHIELD
	shield = max_shield if starting_shield < 0 else clampi(starting_shield, 0, max_shield)

	combo = 0
	max_combo = 0
	blocked = 0
	strikes_taken = 0
	series_length = 0
	series_clean = true
	attacks_landed = 0
	attacks_wasted = 0
	is_over = false
	did_win = false
	for key in grade_counts:
		grade_counts[key] = 0


## Множитель урона гуардиана против жанра монстра.
func genre_multiplier() -> float:
	if guardian == null or monster == null:
		return 1.0
	return MonsterData.genre_multiplier(guardian.genre, monster.genre)


## Учесть оценку обычной ноты.
##
## Обычный бит НЕ сбивает Настрой — он копит серию. Урон наносит только
## атака в конце серии (GDD §4.3). Возвращает всегда 0 — значение оставлено
## ради единообразия вызовов, урон приходит из register_attack.
func register_hit(grade: int) -> int:
	if is_over:
		return 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		# Промах пачкает серию: атака в её конце уже не сработает
		series_clean = false
		_take_damage(MISS_DAMAGE)
		return 0

	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))
	series_length += 1
	return 0


## Атакующий бит — единственный источник урона по Настрою.
##
## Срабатывает только если серия перед ним пройдена без промахов. Иначе
## удар проходит вхолостую: смысл в том, чтобы вести связку чисто, а не
## ждать одну ноту.
func register_attack(grade: int) -> int:
	if is_over:
		return 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		series_clean = false
		_take_damage(MISS_DAMAGE)
		_reset_series()
		return 0

	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))

	if not series_clean or series_length < MIN_SERIES_LENGTH:
		attacks_wasted += 1
		_reset_series()
		return 0

	# Урон растёт от снаряжения гуардиана: собирать предметы — это и есть
	# способ бить сильнее (GDD §9.1)
	var power := (guardian.base_power if guardian != null else 4.0) + power_bonus
	var amount := int(round(
		power * ATTACK_MULTIPLIER * Judge.effect(grade)
			* Judge.combo_multiplier(combo) * genre_multiplier() * experience_scale
	))
	attacks_landed += 1
	_reset_series()
	_reduce_vibe(amount)
	return amount


## Пауза в музыке обрывает серию.
##
## Атака никогда не ставится сразу после паузы (правило разметки), поэтому
## обрыв здесь означает именно «связка кончилась», а не «игрок не успел».
func break_series() -> void:
	_reset_series()


func _reset_series() -> void:
	series_length = 0
	series_clean = true


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
	# Принятый щит продолжает серию: это тоже точное движение в такт,
	# и разрывать связку из-за него было бы несправедливо
	series_length += 1
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
	var damage := maxi(int(round(amount * strike_scale * (1.0 - shield_reduction))), 1)

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
