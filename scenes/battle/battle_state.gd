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

## Все числа боя — в data/battle.json (читает Balance), там же прозой
## дизайн-обоснования каждого. Здесь только короткие делегаты: `const`
## не может звать функции, а вызывающим удобнее короткое имя класса боя.

static func strike_damage() -> int:
	return Balance.strike_damage()


static func crit_multiplier() -> int:
	return Balance.crit_multiplier()


static func heavy_strike_damage() -> int:
	return Balance.heavy_strike_damage()


static func miss_damage() -> int:
	return Balance.miss_damage()


static func skill_miss_damage() -> int:
	return Balance.skill_miss_damage()


static func skill_attack_bonus() -> float:
	return Balance.skill_attack_bonus()


static func skill_shield_gain() -> int:
	return Balance.skill_shield_gain()


static func skill_health_gain() -> int:
	return Balance.skill_health_gain()


static func skill_combo_gain() -> int:
	return Balance.skill_combo_gain()


static func skill_window_boost() -> float:
	return Balance.skill_window_boost()


static func skill_window_bars() -> float:
	return Balance.skill_window_bars()


static func shield_restore() -> int:
	return Balance.shield_restore()


static func max_blow_share() -> float:
	return Balance.max_blow_share()


static func stray_free_taps() -> int:
	return Balance.stray_free_taps()


static func stray_tap_damage() -> int:
	return Balance.stray_tap_damage()


static func base_shield() -> int:
	return Balance.base_shield()


static func min_series_length() -> int:
	return Balance.min_series_length()


static func attack_multiplier() -> float:
	return Balance.attack_multiplier()

## Кто танцует. Оба — ЭКЗЕМПЛЯРЫ: грейд и уровень принадлежат существу,
## а не виду, и статы боя считаются от них (GDD §6.3, §6.5).
var monster: MonsterInstance = null
var guardian: MonsterInstance = null
var depth: int = 0

var max_vibe: int = 100
var vibe: int = 100
var max_health: int = 100
var health: int = 100
var max_shield: int = Balance.base_shield()
var shield: int = Balance.base_shield()

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
## Сколько лишних тапов подряд без единой взятой ноты (см. stray_tap_damage).
var stray_run: int = 0
var blocked: int = 0
var strikes_taken: int = 0

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
	max_vibe = int(round(monster.vibe() * (1.0 + Balance.vibe_depth_scale() * depth)))
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

	# Бафы съеденных за забег фруктов (GDD §8.2.3) — поверх снаряжения.
	# Семантика у них разная, и это надо привести к одной: окно у фрукта
	# записано ДОЛЕЙ (0.15 = «+15%»), у снаряжения — множителем (1.15).
	# Потолки самих бафов уже применены при накоплении (Balance.fruit_buff_cap),
	# общий предел смягчения — тот же, что у снаряжения: урон не обнуляется
	window_scale *= 1.0 + RunManager.buff("window_scale")
	power_bonus += RunManager.buff("power_bonus")
	shield_reduction = minf(shield_reduction + RunManager.buff("shield_reduction"), 0.75)

	# Здоровье сквозное: между полянами само не восстанавливается,
	# только фруктами у костра. В этом всё напряжение забега
	max_health = (guardian.max_health() if guardian != null else 100) \
		+ int(bonuses.get("health_bonus", 0))
	health = clampi(starting_health, 0, max_health)

	# Щит переносится с прошлой поляны. -1 означает «начать с полного»
	# и нужен только для отдельных боёв вне забега: обучение, тесты
	max_shield = Balance.base_shield()
	shield = max_shield if starting_shield < 0 else clampi(starting_shield, 0, max_shield)

	combo = 0
	max_combo = 0
	stray_run = 0
	blocked = 0
	strikes_taken = 0
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
	# Взятая нота обрывает счёт лишних тапов: спам — это тапы ПОДРЯД,
	# а не их общее число за бой
	stray_run = 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		# Промах пачкает серию: атака в её конце уже не сработает
		series_clean = false
		# Возвращаем урон СО ЗНАКОМ МИНУС: вызывающему надо отличить
		# «попал и снял столько-то с монстра» от «промазал и получил сам»,
		# а иначе цифра над героем и цифра над монстром неразличимы
		return -_take_damage(Balance.miss_damage())

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
	# Взятая нота обрывает счёт лишних тапов: спам — это тапы ПОДРЯД,
	# а не их общее число за бой
	stray_run = 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		series_clean = false
		_take_damage(Balance.miss_damage())
		_reset_series()
		return 0

	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))

	if not series_clean or series_length < Balance.min_series_length():
		attacks_wasted += 1
		_reset_series()
		return 0

	# Урон растёт от снаряжения гуардиана: собирать предметы — это и есть
	# способ бить сильнее (GDD §9.1)
	# Сила удара экземпляра уже включает грейд и уровень
	var power := (guardian.power() if guardian != null else 4.0) + power_bonus
	var amount := int(round(
		power * Balance.attack_multiplier() * Judge.effect(grade)
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
func register_stray_tap() -> int:
	if is_over:
		return 0
	series_clean = false
	if combo != 0:
		combo = 0
		combo_changed.emit(combo, 1.0)

	# Считаются тапы ПОДРЯД, и счёт обнуляет любая взятая нота. Разница между
	# «потыкал в экран» и «долблю кнопку» именно в этом: первое обрывается
	# попаданием, второе — нет
	stray_run += 1
	if stray_run <= Balance.stray_free_taps():
		return 0
	return -_take_damage(Balance.stray_tap_damage())


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
func use_skill(grade: int, current_beat: float = 0.0, beats_per_bar: int = 4) -> int:
	if is_over:
		return 0
	# Взятая нота обрывает счёт лишних тапов: спам — это тапы ПОДРЯД,
	# а не их общее число за бой
	stray_run = 0

	grade_counts[grade] += 1

	if grade == Judge.Grade.MISS:
		combo = 0
		combo_changed.emit(combo, 1.0)
		series_clean = false
		return -_take_damage(Balance.skill_miss_damage())

	combo += 1
	max_combo = maxi(max_combo, combo)
	series_length += 1

	if guardian == null:
		combo_changed.emit(combo, Judge.combo_multiplier(combo))
		return 0

	match guardian.genre():
		MonsterData.Genre.ROCK:
			# Камень: топот — следующая удавшаяся атака бьёт сильнее
			next_attack_bonus = Balance.skill_attack_bonus()
		MonsterData.Genre.DISCO:
			# Солнце: вспышка чинит буфер прощения
			restore_shield(Balance.skill_shield_gain())
		MonsterData.Genre.FOLK:
			# Листва: дыхание леса возвращает немного сил
			restore_health(Balance.skill_health_gain())
		MonsterData.Genre.ELECTRO:
			# Искра: разряд подбрасывает комбо
			combo += Balance.skill_combo_gain()
			max_combo = maxi(max_combo, combo)
		MonsterData.Genre.LATIN:
			# Ветер: порыв ненадолго расширяет окна попадания
			window_boost_until_beat = current_beat + float(beats_per_bar) * Balance.skill_window_bars()

	combo_changed.emit(combo, Judge.combo_multiplier(combo))
	# Удачный скилл урона по герою не наносит — цифре взяться неоткуда
	return 0


## Ширина окон с учётом снаряжения и действующего порыва Ветра.
func effective_window_scale(current_beat: float = 0.0) -> float:
	if current_beat <= window_boost_until_beat:
		return window_scale * Balance.skill_window_boost()
	return window_scale


## Щит принят вовремя — атака погашена и щит немного восстановлен.
##
## Это единственный источник восстановления щита в бою, поэтому ноты-щиты
## превращаются из угрозы в возможность: за ними следят не только чтобы
## не пропустить, но и чтобы починить буфер.
func block_strike() -> void:
	if is_over:
		return
	# Взятая нота обрывает счёт лишних тапов: спам — это тапы ПОДРЯД,
	# а не их общее число за бой
	stray_run = 0

	blocked += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_changed.emit(combo, Judge.combo_multiplier(combo))
	# Принятый щит продолжает серию: это тоже точное движение в такт,
	# и разрывать связку из-за него было бы несправедливо
	series_length += 1
	restore_shield(Balance.shield_restore())


## Щит пропущен — атака монстра дошла до цели.
## Пропущенная атака монстра. `heavy` — та же атака, но заметно больнее:
## тяжёлый удар обязан ощущаться иначе, иначе особая нота не отличается
## от обычной ничем, кроме формы (GDD §4.2.3).
func take_strike(heavy: bool = false) -> int:
	if is_over:
		return 0
	# Взятая нота обрывает счёт лишних тапов: спам — это тапы ПОДРЯД,
	# а не их общее число за бой
	stray_run = 0

	strikes_taken += 1
	grade_counts[Judge.Grade.MISS] += 1
	combo = 0
	combo_changed.emit(combo, 1.0)
	return _take_damage(Balance.heavy_strike_damage() if heavy else Balance.strike_damage())


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

	# Ни один удар не отнимает больше доли запаса — с полного здоровья
	# забег не может кончиться одним пропуском (см. max_blow_share).
	# На низких грейдах порог не достаётся вовсе: там крит и так меньше
	var cap := maxi(int(round(max_health * Balance.max_blow_share())), 1)
	if damage > cap:
		total -= damage - cap
		damage = cap

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


