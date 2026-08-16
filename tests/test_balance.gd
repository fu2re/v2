extends TestHarness

## Проверки баланса боя на НАСТОЯЩИХ чартах.
##
## Юнит-тесты проверяют, что механика работает; этот — что с ней можно
## играть. Бой обязан длиться почти весь трек: если монстр падает
## на середине мелодии, музыка обрывается и вся затея с ритмом рушится.

## Насколько поздно в треке должна наступать победа при чистой игре.
const MIN_CLEAN_PROGRESS := 0.6
const MAX_CLEAN_PROGRESS := 1.0

func run_tests() -> void:
	GameState.reset()

	_test_clean_run_wins_late()
	_test_sloppy_run_loses()
	_test_charts_have_enough_attacks()
	_test_new_player_beats_shallow_monsters()
	_test_deep_monsters_need_progression()


## Проиграть чарт от начала до конца с заданной точностью.
## Возвращает долю трека, на которой монстр пал, или 1.0 если устоял.
func _simulate(chart: ChartData, monster_id: String, accuracy: float) -> float:
	var state := BattleState.new()
	state.setup(MonsterInstance.create(monster_id, MonsterData.Rarity.COMMON), GameState.tame("disco_sprout", MonsterData.Rarity.COMMON), 100, 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	for i in chart.note_count():
		if state.is_over:
			return chart.note_beats[i] / maxf(chart.total_beats(), 1.0)

		# Пауза обрывает серию — ровно как в бою
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()

		var hit := rng.randf() < accuracy
		var grade := Judge.Grade.PERFECT if hit else Judge.Grade.MISS

		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(grade)
			ChartData.NoteType.SHIELD:
				if hit:
					state.block_strike()
				else:
					state.take_strike()
			_:
				state.register_hit(grade)

	return 1.0 if not state.did_win else 1.0


## Идеальная игра обязана побеждать — но ближе к концу мелодии.
## Меряем на ТЕХ чартах, в которые играют.
##
## Раньше здесь стоял demo_disco, и это подвело: в нём заметно больше
## атакующих нот, чем в боевой матрице, поэтому «нормальная длина боя»
## на нём означала непроходимый бой в игре. Живой прогон показал ровно это —
## монстр не падал никогда.
func _test_clean_run_wins_late() -> void:
	print("Чистое прохождение выбивает монстра к концу трека")
	for species_id in ["synth_slime", "bass_bear", "beat_serpent"]:
		var difficulty: String = species_id
		var chart := ChartSelect.load_for(Registry.monster(species_id),
			MonsterData.Rarity.COMMON)
		if chart == null:
			check(false, "%s: чарт загружен" % difficulty)
			continue

		var state := BattleState.new()
		state.setup(MonsterInstance.create(species_id, MonsterData.Rarity.COMMON), GameState.tame("disco_sprout", MonsterData.Rarity.COMMON), 100, 0)
		var win_at := -1.0

		for i in chart.note_count():
			if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
				state.break_series()
			match chart.note_types[i]:
				ChartData.NoteType.ATTACK:
					state.register_attack(Judge.Grade.PERFECT)
				ChartData.NoteType.SHIELD:
					state.block_strike()
				_:
					state.register_hit(Judge.Grade.PERFECT)
			if state.is_over and win_at < 0.0:
				win_at = chart.note_beats[i] / maxf(chart.total_beats(), 1.0)

		check(state.did_win, "%s: идеальная игра побеждает" % difficulty)
		if not state.did_win:
			continue

		check(win_at >= MIN_CLEAN_PROGRESS,
			"%s: победа не раньше %d%% трека (получено %d%%)"
				% [difficulty, MIN_CLEAN_PROGRESS * 100, win_at * 100])
		check(win_at <= MAX_CLEAN_PROGRESS,
			"%s: победа укладывается в трек (%d%%)" % [difficulty, win_at * 100])


## Неряшливая игра не должна побеждать: иначе точность ни на что не влияет.
func _test_sloppy_run_loses() -> void:
	print("Небрежная игра монстра не выбивает")
	var chart := ChartLoader.load_by_id("demo_disco", "normal")
	if chart == null:
		check(false, "чарт загружен")
		return

	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", MonsterData.Rarity.COMMON), GameState.tame("disco_sprout", MonsterData.Rarity.COMMON), 100, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	for i in chart.note_count():
		if state.is_over:
			break
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		# Половина промахов: серии почти никогда не бывают чистыми
		var hit := rng.randf() < 0.5
		var grade := Judge.Grade.PERFECT if hit else Judge.Grade.MISS
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(grade)
			ChartData.NoteType.SHIELD:
				if hit:
					state.block_strike()
				else:
					state.take_strike()
			_:
				state.register_hit(grade)

	check(not state.did_win,
		"с половиной промахов монстр устоял (Настрой %d из %d)"
			% [state.vibe, state.max_vibe])
	check(state.attacks_wasted > 0, "часть атак прошла вхолостую")


## В чарте должно быть достаточно атак, чтобы победа вообще была возможна.
func _test_charts_have_enough_attacks() -> void:
	print("В чартах хватает атакующих нот")
	for id in ["demo_disco", "farm_folk"]:
		for difficulty in ["easy", "normal", "hard"]:
			var chart := ChartLoader.load_by_id(id, difficulty)
			if chart == null:
				continue
			var attacks := 0
			for t in chart.note_types:
				if t == ChartData.NoteType.ATTACK:
					attacks += 1
			check(attacks >= 3,
				"%s [%s]: атак %d — победа достижима" % [id, difficulty, attacks])


## Свежий игрок обязан побеждать то, что встречает у поверхности.
##
## Иначе первый же забег превращается в череду убегающих монстров,
## а приручить можно только побеждённого — то есть игра не начинается.
func _test_new_player_beats_shallow_monsters() -> void:
	print("Новичок побеждает монстров у поверхности")
	GameState.reset()
	var chart := ChartLoader.load_by_id("demo_disco", "normal")

	for id in ["disco_sprout", "synth_slime", "bass_bear"]:
		for depth in [1, 3, 5]:
			var state := _play_clean(chart, id, "disco_sprout", depth)
			check(state.did_win,
				"%s на глубине %d побеждается чистой игрой (Настрой %d из %d)"
					% [id, depth, state.vibe, state.max_vibe])


## А вглубь без снаряжения и опыта уже не вытянуть — и это правильно.
func _test_deep_monsters_need_progression() -> void:
	print("Глубина требует снаряжения и опыта")
	GameState.reset()
	# Тот самый чарт, который зазвучит в этом бою: у легендарного он свой,
	# быстрый и с другим числом атак (GDD §10.1.1)
	var chart := ChartSelect.load_for(Registry.monster("beat_serpent"),
		MonsterData.Rarity.LEGENDARY)

	# Трудность глубины проявляется НЕ в том, что идеальная игра не побеждает:
	# чистое прохождение обязано добивать кого угодно, иначе мастерство
	# перестаёт быть решением (§4.3). Трудность в том, что глубоко перестаёт
	# хватать РЕАЛЬНОЙ игры — с промахами, — и вот её-то и вытягивает прокачка
	var top := MonsterData.Rarity.LEGENDARY
	var bare := _play_sloppy(chart, "beat_serpent", 12, top, 0.85)
	check(not bare.did_win,
		"легендарный на глубине 12 без прокачки устоял при 85%% попаданий")

	# Даём ВСЮ прокачку — уровень, снаряжение и изученность вида. Прогрессия
	# стоит на двух опорах сразу (GDD §6.5), и вершина сложности не обязана
	# сдаваться одному плащу
	var guardian := GameState.tame("disco_sprout", MonsterData.Rarity.COMMON)
	guardian.add_xp(Balance.xp_for_level(Balance.max_level()))
	GameState.add_gear("thunder_pick")
	GameState.equip(guardian.key(), "thunder_pick")
	for i in 15:
		GameState.add_battle_experience("beat_serpent")

	var ready := _play_sloppy(chart, "beat_serpent", 12, top, 0.85)
	note("здоровье %d/%d, щит %d, принято ударов %d, крит бьёт %d, обычный %d"
		% [ready.health, ready.max_health, ready.shield, ready.strikes_taken,
			int(BattleState.heavy_strike_damage() * ready.strike_scale),
			int(BattleState.strike_damage() * ready.strike_scale)])
	check(ready.did_win,
		"с плащом и опытом та же игра побеждает (Настрой %d из %d)"
			% [ready.vibe, ready.max_vibe])
	GameState.reset()


## Проиграть чарт с промахами — так, как играет живой человек.
func _play_sloppy(chart: ChartData, monster_id: String, depth: int,
		monster_grade: int, accuracy: float) -> BattleState:
	var state := BattleState.new()
	state.setup(
		MonsterInstance.create(monster_id, monster_grade),
		GameState.tame("disco_sprout", MonsterData.Rarity.COMMON),
		100, depth)

	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	for i in chart.note_count():
		if state.is_over:
			break
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		var hit: bool = rng.randf() < accuracy
		var grade: int = Judge.Grade.PERFECT if hit else Judge.Grade.MISS
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(grade)
			ChartData.NoteType.SHIELD:
				if hit:
					state.block_strike()
				else:
					state.take_strike(false)
			ChartData.NoteType.HEAVY:
				# Крит монстра: блокируется как щит, пропущенный бьёт вчетверо.
				# Раньше помощник считал его обычным битом и мерил игру,
				# которой нет
				if hit:
					state.block_strike()
				else:
					state.take_strike(true)
			ChartData.NoteType.SKILL:
				state.use_skill(grade)
			_:
				state.register_hit(grade)
	return state


## Проиграть чарт идеально и вернуть итоговое состояние.
func _play_clean(chart: ChartData, monster_id: String, guardian_id: String,
		depth: int, monster_grade := MonsterData.Rarity.COMMON) -> BattleState:
	var state := BattleState.new()
	state.setup(
		MonsterInstance.create(monster_id, monster_grade),
		GameState.tame(guardian_id, MonsterData.Rarity.COMMON),
		100, depth)
	for i in chart.note_count():
		if state.is_over:
			break
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(Judge.Grade.PERFECT)
			ChartData.NoteType.SHIELD, ChartData.NoteType.HEAVY:
				# И обычная атака монстра, и крит берутся одной кнопкой:
				# при идеальной игре обе блокируются
				state.block_strike()
			_:
				state.register_hit(Judge.Grade.PERFECT)
	return state
