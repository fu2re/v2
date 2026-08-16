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


## Сколько раз игрок успевает ткнуть в кнопку между двумя нотами, если долбит.
##
## Пять — оценка снизу: палец ребёнка выдаёт 5–10 нажатий в секунду, а нот
## в чарте от двух до восьми в секунду. Занижено намеренно: если приём
## не работает даже при пяти, при десяти он тем более не работает.
const MASH_TAPS_BETWEEN_NOTES := 5


func run_tests() -> void:
	_test_spam_earns_nothing()
	_test_stray_tap_does_not_hurt_health()
	_test_one_button_does_not_survive()
	_test_mashing_is_worse_than_rhythm()
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


## Одной кнопкой бой не проходится.
##
## Живой отчёт: «могу просто всегда жать вправо и не получать урона».
## Предыдущая проверка спама работала на голом состоянии и такого не видела —
## она мерила связку из трёх нот, а не НАСТОЯЩИЙ чарт, где важно, сколько
## в нём атак монстра и доходят ли они. Здесь чарт прогоняется целиком
## ровно так, как это делает бой: правая кнопка берёт только `beat`,
## всё остальное уходит в промах по истечении окна.
func _test_one_button_does_not_survive() -> void:
	print("Одной кнопкой бой не проходится")
	GameState.reset()
	var guardian := GameState.tame("bass_bear", COMMON)

	for grade in [COMMON, MonsterData.Rarity.RARE, MonsterData.Rarity.EPIC]:
		var chart := ChartSelect.load_for(Registry.monster("synth_slime"), grade)
		if chart == null:
			check(false, "чарт грейда %s не загрузился" % MonsterData.rarity_name(grade))
			continue

		var state := BattleState.new()
		state.setup(MonsterInstance.create("synth_slime", grade), guardian, 100, 0)
		var strikes := 0
		for i in chart.note_count():
			if state.is_over:
				break
			if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
				state.break_series()
			var type: int = chart.note_types[i]
			if NoteRules.accepts(type, NoteRules.Lane.NORMAL):
				# Правая кнопка нажата всегда и всегда идеально. И между
				# нотами она тоже нажата — это и есть спам: кнопку долбят,
				# а не жмут по одной ноте
				for s in MASH_TAPS_BETWEEN_NOTES:
					state.register_stray_tap()
				state.register_hit(Judge.Grade.PERFECT)
				continue
			# Особая нота не взята: она истекает и судится промахом
			strikes += 1
			match type:
				ChartData.NoteType.SHIELD:
					state.take_strike(false)
				ChartData.NoteType.HEAVY:
					state.take_strike(true)
				ChartData.NoteType.ATTACK:
					state.register_attack(Judge.Grade.MISS)
				ChartData.NoteType.SKILL:
					state.use_skill(Judge.Grade.MISS)

		var name := MonsterData.rarity_name(grade)
		note("%s: пропущено особых %d, здоровье %d/%d, щит %d, Настрой %d/%d"
			% [name, strikes, state.health, state.max_health, state.shield,
				state.vibe, state.max_vibe])
		# Проверяется НАБЛЮДАЕМЫЙ исход: держать кнопку нельзя. Не «сколько
		# урона прошло» и не «сколько нот пропущено» — те цифры можно
		# подкрутить, оставив приём рабочим
		check(not state.did_win, "%s: спам одной кнопкой не побеждает" % name)
		check(state.health <= 0, "%s: спам одной кнопкой доводит до поражения" % name)


## Долбить кнопку строго хуже, чем жать по ноте.
##
## Это ГЛАВНОЕ утверждение про спам, и проверка выше его не делает: бой одной
## кнопкой проигрывается и без штрафа за долбёжку — просто потому, что атаки
## монстра доходят. Здесь обе игры одинаково точны по нотам, и разница ровно
## одна: во второй между нотами кнопку долбят.
func _test_mashing_is_worse_than_rhythm() -> void:
	print("Долбёжка хуже игры по такту")
	GameState.reset()
	var guardian := GameState.tame("bass_bear", COMMON)
	var chart := ChartSelect.load_for(Registry.monster("synth_slime"), COMMON)
	check(chart != null, "чарт загрузился")
	if chart == null:
		return

	var clean := _play_perfect(chart, guardian, 0)
	var mashed := _play_perfect(chart, guardian, MASH_TAPS_BETWEEN_NOTES)

	note("по такту: здоровье %d, щит %d, победа %s"
		% [clean.health, clean.shield, "да" if clean.did_win else "нет"])
	note("с долбёжкой: здоровье %d, щит %d, победа %s"
		% [mashed.health, mashed.shield, "да" if mashed.did_win else "нет"])

	check(clean.did_win, "точная игра побеждает")
	check(clean.health + clean.shield > mashed.health + mashed.shield,
		"долбёжка стоит запаса (%d против %d)"
			% [mashed.health + mashed.shield, clean.health + clean.shield])
	# И не только запаса: испорченная серия отнимает собственный урон игрока
	check(mashed.attacks_wasted > clean.attacks_wasted,
		"и атаки уходят вхолостую (%d против %d)"
			% [mashed.attacks_wasted, clean.attacks_wasted])


## Идеальное прохождение чарта. `mash` — сколько лишних тапов игрок успевает
## воткнуть между нотами; ноль означает игру ровно по нотам.
func _play_perfect(chart: ChartData, guardian: MonsterInstance,
		mash: int) -> BattleState:
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON), guardian, 100, 0)
	for i in chart.note_count():
		if state.is_over:
			break
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		for s in mash:
			state.register_stray_tap()
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(Judge.Grade.PERFECT)
			ChartData.NoteType.SHIELD, ChartData.NoteType.HEAVY:
				state.block_strike()
			ChartData.NoteType.SKILL:
				state.use_skill(Judge.Grade.PERFECT)
			_:
				state.register_hit(Judge.Grade.PERFECT)
	return state


## Любопытство бесплатно, долбёжка — нет.
##
## Раньше здесь стояло «тап мимо НЕ бьёт по здоровью», и это оказалось дырой:
## рваная серия отнимала у игрока только его собственный урон, поэтому долбить
## правую кнопку было строго выгодно — каждый бит попадал в своё окно сам
## собой, а промахи между ними не стоили ничего. Отсюда две разные вещи:
## первые тапы прощаются, тапы ПОДРЯД — нет.
func _test_stray_tap_does_not_hurt_health() -> void:
	print("Потыкать в экран бесплатно, долбить — нет")
	GameState.reset()
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON),
		GameState.tame("bass_bear", COMMON), 100)

	var health := state.health
	var shield := state.shield
	for i in BattleState.STRAY_FREE_TAPS:
		state.register_stray_tap()

	check_eq(state.health, health, "здоровье цело: ребёнок пробует экран")
	check_eq(state.shield, shield, "щит тоже цел")
	check(not state.series_clean, "но серия уже испорчена")
	check_eq(state.combo, 0, "и комбо сброшено")

	# Дальше — платно
	state.register_stray_tap()
	check(state.shield < shield, "четвёртый тап подряд уже стоит")

	# И счёт обрывается взятой нотой: пауза с попаданием возвращает прощение
	state.register_hit(Judge.Grade.PERFECT)
	var after_hit := state.shield
	for i in BattleState.STRAY_FREE_TAPS:
		state.register_stray_tap()
	check_eq(state.shield, after_hit,
		"после взятой ноты счёт лишних тапов начинается заново")


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

	# Разрыв обязан быть РАЗЫ, а не проценты: иначе игрок его не почувствует.
	#
	# Порог опущен с трёх раз до двух с половиной, и это осознанный размен.
	# По живой игре обычный монстр не кусался вовсе, и пол лестницы подняли
	# в полтора раза (1.0 → 1.5). Потолок при этом остался на 5.0: он
	# перемножается с ×4 за крит, и растянутая лестница убивала полностью
	# прокачанного гуардиана с одного пропуска. Широкий разрыв и высокий пол
	# несовместимы — выбран пол, потому что низкие грейды игрок встречает
	# в сто раз чаще эпических
	var top := float(damage[MonsterData.Rarity.EPIC])
	var bottom := float(damage[COMMON])
	check(top / bottom >= 2.5,
		"эпический бьёт вдвое с лишним сильнее обычного (%.1f×)" % (top / bottom))

	# И это видно по тому, сколько ошибок игрок может себе позволить
	check(survived[COMMON] >= survived[MonsterData.Rarity.EPIC] * 2,
		"против обычного ошибиться можно вдвое чаще (%d против %d)"
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
