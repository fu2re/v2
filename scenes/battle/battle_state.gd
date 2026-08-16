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
## Тяжёлая атака монстра — бывшая нота-зелье. Втрое больнее обычной:
## особая нота должна ЧУВСТВОВАТЬСЯ особой, а не отличаться силуэтом.
const HEAVY_STRIKE_DAMAGE := 30
## Урон за обычный промах. Мал намеренно: щит гасит его несколько раз подряд,
## и ребёнок успевает поймать ритм прежде, чем это станет больно.
const MISS_DAMAGE := 3

## Промах по скиллу дороже обычного (GDD §4.2.4).
##
## Особая нота требует особого внимания: если бы она стоила столько же,
## сколько бит, левая кнопка ничем не отличалась бы от правой.
const SKILL_MISS_DAMAGE := 6

## Эффекты спецдвижений по стихии гуардиана (GDD §4.2.4).
## Маленькие и мгновенные: скилл — приправа к бою, а не вторая система.
const SKILL_ATTACK_BONUS := 1.5
const SKILL_SHIELD_GAIN := 6
const SKILL_HEALTH_GAIN := 5
const SKILL_COMBO_GAIN := 5
const SKILL_WINDOW_BOOST := 1.25
const SKILL_WINDOW_BARS := 4.0
## Сколько щита возвращает попадание по ноте-щиту.
##
## Совсем немного намеренно. Щит — расходуемый буфер на весь забег, а не
## возобновляемый ресурс: когда попадание возвращало восемь, забег переставал
## быть испытанием на выносливость — буфер чинился быстрее, чем тратился.
const SHIELD_RESTORE := 2

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
const ATTACK_MULTIPLIER := 2.2

## Кто танцует. Оба — ЭКЗЕМПЛЯРЫ: грейд и уровень принадлежат существу,
## а не виду, и статы боя считаются от них (GDD §6.3, §6.5).
var monster: MonsterInstance = null
var guardian: MonsterInstance = null
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

## Спецдвижения: сколько сработало и что они оставили после себя.
var skills_used: int = 0
## Множитель следующей удавшейся атаки (Камень). Тратится при попадании.
var next_attack_bonus: float = 1.0
## До какой доли трека расширены окна (Ветер). Доля передаётся снаружи:
## BattleState остаётся чистым классом и ничего не знает про Conductor.
var window_boost_until_beat: float = -1.0

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


func setup(new_monster: MonsterInstance, new_guardian: MonsterInstance,
		starting_health: int, run_depth: int = 0, starting_shield: int = -1) -> void:
	monster = new_monster
	guardian = new_guardian
	depth = run_depth

	# Крепость монстра складывается из трёх вещей: его собственного запаса,
	# грейда с уровнем (это уже внутри `vibe()`) и глубины забега. Грейд —
	# главный множитель: легендарный обязан ощущаться как событие,
	# а не как обычный бой с другой рамкой
	max_vibe = int(round(monster.vibe() * (1.0 + VIBE_DEPTH_SCALE * depth)))
	vibe = max_vibe

	# Урон монстра растёт по СВОЕЙ шкале, круче, чем крепость: эпический
	# обязан пугать, а не просто дольше держаться (GDD §6.3)
	strike_scale = monster.strike_scale()

	# Опыт боёв против ВИДА: каждая встреча учит повадкам и добавляет урона.
	# Это то, что делает повторные встречи осмысленными, а не рутиной
	experience_scale = GameState.experience_multiplier(monster.species_id)

	var bonuses := GameState.gear_bonuses(guardian.key()) if guardian != null else {}
	window_scale = bonuses.get("window_scale", 1.0)
	power_bonus = bonuses.get("power_bonus", 0.0)
	shield_reduction = bonuses.get("shield_reduction", 0.0)

	# Здоровье сквозное: между полянами само не восстанавливается,
	# только у костра и зельями. В этом всё напряжение забега
	max_health = (guardian.max_health() if guardian != null else 100) \
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
	skills_used = 0
	next_attack_bonus = 1.0
	window_boost_until_beat = -1.0
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
	return MonsterData.genre_multiplier(guardian.genre(), monster.genre())


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
	# Сила удара экземпляра уже включает грейд и уровень
	var power := (guardian.power() if guardian != null else 4.0) + power_bonus
	var amount := int(round(
		power * ATTACK_MULTIPLIER * Judge.effect(grade)
			* Judge.combo_multiplier(combo) * genre_multiplier() * experience_scale
			* next_attack_bonus
	))
	# Топот Камня усиливает ОДИН удар и тратится на нём: иначе спецдвижение
	# в начале боя тихо усиливало бы весь бой целиком
	next_attack_bonus = 1.0
	attacks_landed += 1
	_reset_series()
	_reduce_vibe(amount)
	return amount


## Тап мимо всякой ноты.
##
## Не бьёт по здоровью — ребёнок, который просто пробует экран, не должен
## терять забег. Но рвёт серию и сбрасывает комбо, и этого достаточно:
## без чистой связки атака не проходит вовсе (§4.2.1), поэтому долбить
## обе кнопки подряд становится строго хуже, чем ждать свою ноту.
##
## До этого лишний тап не стоил ничего, и найденный на живом прогоне приём
## «спамить обе кнопки» давал попадание по каждой ноте бесплатно —
## то есть отменял ритм-игру целиком.
func register_stray_tap() -> void:
	if is_over:
		return
	series_clean = false
	if combo != 0:
		combo = 0
		combo_changed.emit(combo, 1.0)


## Пауза в музыке обрывает серию.
##
## Атака никогда не ставится сразу после паузы (правило разметки), поэтому
## обрыв здесь означает именно «связка кончилась», а не «игрок не успел».
func break_series() -> void:
	_reset_series()


func _reset_series() -> void:
	series_length = 0
	series_clean = true


## Спецдвижение гуардиана: эффект определяется его СТИХИЕЙ (GDD §4.2.4).
##
## Текущая доля трека нужна Ветру, чей эффект длится четыре такта. Она
## передаётся аргументом, а не берётся у Conductor: класс обязан оставаться
## чистым, иначе его нельзя гонять headless.
##
## Без гуардиана (интро, §15.5) скилл ведёт себя как обычный бит: своей
## стихии у героя нет, и выдумывать ей эффект значило бы учить игрока тому,
## что перестанет быть правдой, как только у него появится защитник.
func use_skill(grade: int, current_beat: float = 0.0, beats_per_bar: int = 4) -> void:
	if is_over:
		return

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		series_clean = false
		_take_damage(SKILL_MISS_DAMAGE)
		return

	combo += 1
	max_combo = maxi(max_combo, combo)
	series_length += 1
	skills_used += 1

	if guardian == null:
		combo_changed.emit(combo, Judge.combo_multiplier(combo))
		return

	match guardian.genre():
		MonsterData.Genre.ROCK:
			# Камень: топот — следующая удавшаяся атака бьёт сильнее
			next_attack_bonus = SKILL_ATTACK_BONUS
		MonsterData.Genre.DISCO:
			# Солнце: вспышка чинит буфер прощения
			restore_shield(SKILL_SHIELD_GAIN)
		MonsterData.Genre.FOLK:
			# Листва: дыхание леса возвращает немного сил
			restore_health(SKILL_HEALTH_GAIN)
		MonsterData.Genre.ELECTRO:
			# Искра: разряд подбрасывает комбо
			combo += SKILL_COMBO_GAIN
			max_combo = maxi(max_combo, combo)
		MonsterData.Genre.LATIN:
			# Ветер: порыв ненадолго расширяет окна попадания
			window_boost_until_beat = current_beat + float(beats_per_bar) * SKILL_WINDOW_BARS

	combo_changed.emit(combo, Judge.combo_multiplier(combo))


## Ширина окон с учётом снаряжения и действующего порыва Ветра.
func effective_window_scale(current_beat: float = 0.0) -> float:
	if current_beat <= window_boost_until_beat:
		return window_scale * SKILL_WINDOW_BOOST
	return window_scale


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
## Пропущенная атака монстра. `heavy` — та же атака, но заметно больнее:
## тяжёлый удар обязан ощущаться иначе, иначе особая нота не отличается
## от обычной ничем, кроме формы (GDD §4.2.3).
func take_strike(heavy: bool = false) -> int:
	if is_over:
		return 0
	strikes_taken += 1
	grade_counts[Judge.Grade.MISS] += 1
	combo = 0
	combo_changed.emit(combo, 1.0)
	return _take_damage(HEAVY_STRIKE_DAMAGE if heavy else STRIKE_DAMAGE)


## Урон идёт СНАЧАЛА в щит и только потом в здоровье.
##
## Щит — это прощение: пока он держится, промахи стоят внимания, но не
## прогресса. Здоровье трогается только когда буфер выбит полностью.
##
## Возвращает, сколько урона было нанесено ВСЕГО — это число вылетает
## на экране, и считать его второй раз в подаче значило бы завести
## второй источник правды.
func _take_damage(amount: int) -> int:
	# Амулет смягчает урон, но никогда не обнуляет его: механика,
	# за которой не надо следить, перестаёт быть механикой
	var damage := maxi(int(round(amount * strike_scale * (1.0 - shield_reduction))), 1)
	var total := damage

	var absorbed := mini(shield, damage)
	if absorbed > 0:
		shield -= absorbed
		damage -= absorbed
		shield_changed.emit(shield, max_shield)

	if damage <= 0:
		return total

	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_finish(false)
	return total


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
