extends TestHarness

## Правила, без которых игру можно обойти.
##
## Все три найдены на живом прогоне, и каждое ломало игру по-своему:
## спам обеими кнопками давал попадание по любой ноте бесплатно, уникальный
## встречался на второй поляне, а редкого можно было приручить, ни разу
## не встретив обычного.

const COMMON := MonsterData.Rarity.COMMON
const UNCOMMON := MonsterData.Rarity.UNCOMMON
const RARE := MonsterData.Rarity.RARE


func run_tests() -> void:
	_test_spam_earns_nothing()
	_test_stray_tap_does_not_hurt_health()
	_test_surface_is_almost_all_common()
	_test_high_grades_unlock_with_depth()
	_test_taming_goes_step_by_step()
	_test_locked_step_accepts_nothing()
	_test_damage_grows_sharply_with_grade()
	_test_shield_and_campfire_are_stingy()


# ─────────────────────────── спам кнопками ──────────────────────────────────

## Долбить обе кнопки подряд не должно давать ничего.
##
## Раньше лишний тап просто игнорировался, поэтому можно было бить по экрану
## как попало и попадать по каждой ноте — ритм-игра отменялась целиком.
func _test_spam_earns_nothing() -> void:
	print("Спам кнопками не приносит урона")
	GameState.reset()
	var guardian := GameState.tame("bass_bear", COMMON)

	var honest := BattleState.new()
	honest.setup(MonsterInstance.create("synth_slime", COMMON), guardian, 100)
	for i in BattleState.MIN_SERIES_LENGTH:
		honest.register_hit(Judge.Grade.PERFECT)
	var honest_damage := honest.register_attack(Judge.Grade.PERFECT)
	check(honest_damage > 0, "честная связка бьёт (%d)" % honest_damage)

	# Тот же путь, но между нотами игрок долбит по пустому месту
	var spammer := BattleState.new()
	spammer.setup(MonsterInstance.create("synth_slime", COMMON), guardian, 100)
	for i in BattleState.MIN_SERIES_LENGTH:
		spammer.register_hit(Judge.Grade.PERFECT)
		spammer.register_stray_tap()
		spammer.register_stray_tap()
	var spam_damage := spammer.register_attack(Judge.Grade.PERFECT)

	check_eq(spam_damage, 0, "связка, испорченная спамом, не бьёт вовсе")
	check_eq(spammer.vibe, spammer.max_vibe, "Настрой не тронут")
	check(spammer.attacks_wasted > 0, "атака ушла вхолостую")


## Но спам не должен ОТНИМАТЬ забег: цена — прогресс, а не здоровье.
## Ребёнок, который просто пробует экран, не обязан за это платить.
func _test_stray_tap_does_not_hurt_health() -> void:
	print("Тап мимо не бьёт по здоровью")
	GameState.reset()
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON),
		GameState.tame("bass_bear", COMMON), 100)

	var health := state.health
	var shield := state.shield
	for i in 30:
		state.register_stray_tap()

	check_eq(state.health, health, "здоровье цело после тридцати лишних тапов")
	check_eq(state.shield, shield, "щит тоже цел")
	check(not state.series_clean, "но серия испорчена")
	check_eq(state.combo, 0, "и комбо сброшено")


# ────────────────────────────── редкость ────────────────────────────────────

## У поверхности почти всё обычное.
##
## На живом прогоне уникальный попался на второй поляне: новичок утыкался
## в непроходимый бой, не успев понять правила.
func _test_surface_is_almost_all_common() -> void:
	print("У поверхности почти всё обычное")
	var weights := Balance.rarity_weights(0)
	var total := 0.0
	for w: float in weights:
		total += w

	var common_share := weights[COMMON] / total * 100.0
	check(common_share >= 85.0, "обычных не меньше 85%% (сейчас %.0f%%)" % common_share)

	var uncommon_share := weights[UNCOMMON] / total * 100.0
	check(uncommon_share <= 15.0, "необычных немного (%.0f%%)" % uncommon_share)

	# Всё, что выше редкого, на поверхности не встречается вовсе
	for grade in [MonsterData.Rarity.UNIQUE, MonsterData.Rarity.EPIC,
			MonsterData.Rarity.LEGENDARY]:
		check_eq(weights[grade], 0.0,
			"%s у поверхности не встречается" % MonsterData.rarity_name(grade))


## Старшие грейды открываются постепенно, а не все сразу.
func _test_high_grades_unlock_with_depth() -> void:
	print("Старшие грейды открываются с глубиной")
	var previous_depth := -1
	for grade in [MonsterData.Rarity.UNIQUE, MonsterData.Rarity.EPIC,
			MonsterData.Rarity.LEGENDARY]:
		var first := -1
		for depth in 60:
			if Balance.rarity_weights(depth)[grade] > 0.0:
				first = depth
				break
		check(first > previous_depth,
			"%s появляется глубже предыдущего грейда (с поляны %d)"
				% [MonsterData.rarity_name(grade), first])
		previous_depth = first

	# И доля редких растёт, а не скачет
	var shallow := Balance.rarity_weights(3)
	var deep := Balance.rarity_weights(25)
	check(deep[RARE] > shallow[RARE], "редких вглубь становится больше")
	check(deep[COMMON] < shallow[COMMON], "обычных — меньше")
	check(deep[COMMON] > 0.0, "но они не исчезают")


# ────────────────────────── лестница приручения ─────────────────────────────

## Через ступень приручать нельзя: сначала обычный, потом необычный и так далее.
func _test_taming_goes_step_by_step() -> void:
	print("Приручение идёт по ступеням")
	GameState.reset()

	check(GameState.can_tame("banjo_moth", COMMON), "обычный доступен сразу")
	check(not GameState.can_tame("banjo_moth", UNCOMMON),
		"необычный закрыт, пока нет обычного")
	check(not GameState.can_tame("banjo_moth", RARE), "редкий тем более")

	# Набиваем шкалу редкого до отказа — приручения не будет
	var rare_threshold := GameState.friendship_threshold(RARE)
	var tamed := GameState.add_friendship("banjo_moth", RARE, rare_threshold * 2)
	check(not tamed, "полная шкала редкого не приручает через ступень")
	check(not GameState.has_instance("banjo_moth", RARE), "редкого в коллекции нет")

	# Открываем ступени снизу
	GameState.add_friendship("banjo_moth", COMMON,
		GameState.friendship_threshold(COMMON))
	check(GameState.has_instance("banjo_moth", COMMON), "обычный приручён")
	check(GameState.can_tame("banjo_moth", UNCOMMON), "необычный открылся")
	check(not GameState.can_tame("banjo_moth", RARE), "редкий всё ещё закрыт")

	GameState.add_friendship("banjo_moth", UNCOMMON,
		GameState.friendship_threshold(UNCOMMON))
	check(GameState.has_instance("banjo_moth", UNCOMMON), "необычный приручён")
	check(GameState.can_tame("banjo_moth", RARE), "теперь открыт и редкий")

	# А вот накопить «про запас» было нельзя: пока ступень закрыта, вклад
	# не принимается вовсе. Шкала редкого стоит на нуле, и набивать её
	# придётся заново — зато ни один фрукт не ушёл в пустоту
	check_eq(GameState.get_friendship("banjo_moth", RARE), 0,
		"в закрытую ступень ничего не накопилось")
	check(not GameState.add_friendship("banjo_moth", RARE, GameState.FRIENDSHIP_WIN),
		"одной победы по открывшейся ступени мало — шкала начинается с нуля")
	check(GameState.get_friendship("banjo_moth", RARE) > 0,
		"но теперь дружба пошла")


## Пока ступень закрыта, дружба НЕ копится — и это защита, а не запрет.
##
## Раньше копилась «про запас»: полоска ползла, фрукты списывались,
## а приручение всё равно не наступало. Двигать шкалу, с которой ничего
## нельзя сделать, — то же самое, что выбрасывать угощение.
func _test_locked_step_accepts_nothing() -> void:
	print("В закрытую ступень дружба не копится")
	GameState.reset()

	check(not GameState.add_friendship("bass_bear", RARE, 40),
		"вклад в закрытую ступень отклонён")
	check_eq(GameState.get_friendship("bass_bear", RARE), 0,
		"шкала осталась на нуле")
	check(not GameState.has_instance("bass_bear", RARE), "друга, конечно, нет")

	# Игра обязана назвать недостающую ступень, а не молчать
	check_eq(GameState.missing_step("bass_bear", RARE), UNCOMMON,
		"игра знает, какой ступени не хватает")
	check_eq(GameState.missing_step("bass_bear", COMMON), -1,
		"для обычного ступеней не требуется")


# ──────────────────────── ощутимость грейда в бою ───────────────────────────

## Урон монстра растёт КРУЧЕ его крепости.
##
## Пока обе величины шли по одной шкале, эпический бил лишь чуть сильнее
## обычного: грейд читался подписью в углу, а не тем, что происходит
## на экране. Здесь проверяется, что разрыв действительно ощутим.
func _test_damage_grows_sharply_with_grade() -> void:
	print("Урон монстра резко растёт с грейдом")
	GameState.reset()
	var guardian := GameState.tame("disco_sprout", COMMON)

	var damage: Array[int] = []
	var survived: Array[int] = []

	for grade in MonsterData.RARITY_NAMES.size():
		var hit := BattleState.new()
		hit.setup(MonsterInstance.create("synth_slime", grade), guardian, 100)
		var before := hit.shield + hit.health
		hit.take_strike()
		damage.append(before - (hit.shield + hit.health))

		# Сколько пропущенных атак подряд выдержит игрок
		var endurance := BattleState.new()
		endurance.setup(MonsterInstance.create("synth_slime", grade), guardian, 100)
		var blows := 0
		while not endurance.is_over and blows < 999:
			blows += 1
			endurance.take_strike()
		survived.append(blows)

	for grade in range(1, damage.size()):
		check(damage[grade] > damage[grade - 1],
			"%s бьёт больнее предыдущего (%d против %d)"
				% [MonsterData.rarity_name(grade), damage[grade], damage[grade - 1]])

	# Разрыв обязан быть РАЗЫ, а не проценты: иначе игрок его не почувствует
	var top := float(damage[MonsterData.Rarity.EPIC])
	var bottom := float(damage[COMMON])
	check(top / bottom >= 3.0,
		"эпический бьёт минимум втрое сильнее обычного (%.1f×)" % (top / bottom))

	# И это видно по тому, сколько ошибок игрок может себе позволить
	check(survived[COMMON] >= survived[MonsterData.Rarity.EPIC] * 3,
		"против обычного ошибиться можно втрое чаще (%d против %d)"
			% [survived[COMMON], survived[MonsterData.Rarity.EPIC]])

	# Урон растёт круче, чем крепость: это две РАЗНЫЕ шкалы
	var strike_gap := Balance.grade_strike_scale(MonsterData.Rarity.EPIC) \
		/ Balance.grade_strike_scale(COMMON)
	var stat_gap := Balance.grade_stat_scale(MonsterData.Rarity.EPIC) \
		/ Balance.grade_stat_scale(COMMON)
	check(strike_gap > stat_gap,
		"злость растёт круче крепости (%.1f× против %.1f×)" % [strike_gap, stat_gap])


## Щит и костёр возвращают мало.
##
## Забег — испытание на выносливость (GDD §4.4): и буфер, и здоровье сквозные.
## Когда нота-щита возвращала восемь, а костёр двадцать пять, глубина
## переставала накапливаться и решение «идти дальше или уйти» обесценивалось.
func _test_shield_and_campfire_are_stingy() -> void:
	print("Щит и костёр возвращают понемногу")
	check(BattleState.SHIELD_RESTORE <= 3,
		"нота-щит возвращает совсем немного (%d)" % BattleState.SHIELD_RESTORE)
	check(BattleState.SHIELD_RESTORE > 0, "но всё же возвращает")

	# Костёр сам по себе не лечит вовсе: у него едят фрукты, и цена лечения —
	# упущенное угощение (GDD §8.2.3)
	var cheapest := Balance.fruit_heal(0)
	check(cheapest <= 20,
		"самый простой фрукт лечит не больше двадцати (%d)" % cheapest)

	# Починка щита обязана быть дешевле пропущенной атаки, иначе выгодно
	# ловить удары ради восстановления
	check(BattleState.SHIELD_RESTORE < BattleState.STRIKE_DAMAGE,
		"починка дешевле пропущенного удара")

	GameState.reset()
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON),
		GameState.tame("disco_sprout", COMMON), 100)

	# Даже бесконечная починка не делает щит вечным: удар снимает больше
	state.shield = 10
	var before := state.shield
	state.restore_shield(BattleState.SHIELD_RESTORE)
	state.take_strike()
	check(state.shield + state.health < before + state.max_health,
		"после удара с починкой запас всё равно меньше")
