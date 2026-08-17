extends TestHarness

## Связь монстра и его музыки (GDD §10.1.1).
##
## Матрица «стихия × мотив × грейд» генерируется отдельным инструментом,
## и сама игра о ней ничего не знает — она лишь собирает имя файла. Значит
## разъехаться эти две половины могут молча: непроставленный мотив, забытый
## жанр, недогенерированный грейд. Эти тесты — единственное место, где такое
## видно раньше, чем игрок останется без музыки в бою.


func run_tests() -> void:
	ChartSelect.forget()

	_test_every_monster_has_motif()
	_test_every_grade_has_chart()
	_test_charts_load_and_have_audio()
	_test_tempo_grows_with_grade()
	_test_real_charts_are_winnable()
	_test_missing_motif_falls_back()


func _test_every_monster_has_motif() -> void:
	print("У каждого монстра есть мотив")
	for monster in Registry.all_monsters():
		check(not monster.motif_id.is_empty(),
			"%s: мотив проставлен" % monster.id)


## Для каждой встречи, которую может выдать лента, должен найтись трек.
func _test_every_grade_has_chart() -> void:
	print("Для каждого монстра и грейда есть трек")
	for monster in Registry.all_monsters():
		for grade in MonsterData.RARITY_NAMES.size():
			var stem := ChartSelect.chart_stem(monster, grade)
			check(not stem.is_empty(), "%s / %s: трек найден"
				% [monster.id, MonsterData.rarity_name(grade)])


func _test_charts_load_and_have_audio() -> void:
	print("Треки читаются, и аудио на месте")
	for monster in Registry.all_monsters():
		for grade in [MonsterData.Rarity.COMMON, MonsterData.Rarity.LEGENDARY]:
			var chart := ChartSelect.load_for(monster, grade)
			var label := "%s / %s" % [monster.id, MonsterData.rarity_name(grade)]

			check(chart != null, "%s: чарт загрузился" % label)
			if chart == null:
				continue

			check(chart.note_count() > 0, "%s: в чарте есть ноты" % label)
			check(chart.bpm > 0.0, "%s: темп задан" % label)
			check(ResourceLoader.exists(chart.audio_path),
				"%s: аудио '%s' существует" % [label, chart.audio_path])

			# Первая нота не раньше такта: игроку нужно услышать сетку
			check(chart.note_beats[0] >= float(chart.beats_per_bar),
				"%s: вступление на месте" % label)


## Чем реже монстр, тем быстрее он ведёт танец — это и есть сложность
## (GDD §10.1.1), а не подкрученные числа.
func _test_tempo_grows_with_grade() -> void:
	print("Темп растёт с грейдом")
	for monster in Registry.all_monsters():
		var previous := 0.0
		for grade in MonsterData.RARITY_NAMES.size():
			var chart := ChartSelect.load_for(monster, grade)
			if chart == null:
				continue
			check(chart.bpm > previous,
				"%s / %s: темп выше предыдущего грейда (%.0f)"
					% [monster.id, MonsterData.rarity_name(grade), chart.bpm])
			previous = chart.bpm


## Бой на НАСТОЯЩЕМ чарте встречи должен быть выигрываемым.
##
## Раньше все бои шли на одном demo_disco, и баланс проверялся только на нём.
## Теперь у каждого грейда свой трек вдвое быстрее предыдущего — а число нот
## и длина серий в них другие. Непроходимый легендарный выглядел бы
## не как «трудно», а как «сломано», и заметить это без такой проверки
## можно было бы только на живом прогоне.
func _test_real_charts_are_winnable() -> void:
	print("Реальные чарты проходимы чистой игрой")
	GameState.reset()

	# Подготовленный игрок: снаряжение и изученные повадки — то, ради чего
	# собирают прогрессию (GDD §6.5). Гуардиан — ТОГО ЖЕ грейда, что монстр:
	# здесь меряется играбельность чарта, а стена грейдов (§6.3) намеренно
	# делает бой «через ступень» непроходимым — это не поломка чарта
	for monster in Registry.all_monsters():
		for grade in [MonsterData.Rarity.COMMON, MonsterData.Rarity.LEGENDARY]:
			var chart := ChartSelect.load_for(monster, grade)
			if chart == null:
				continue

			var guardian := GameState.tame("disco_sprout", grade)
			GameState.add_gear("thunder_pick")
			GameState.equip(guardian.key(), "thunder_pick")
			for i in 15:
				GameState.add_battle_experience(monster.id)

			var state := BattleState.new()
			state.setup(MonsterInstance.create(monster.id, grade), guardian, 100, 0)
			_play_clean(chart, state)

			check(state.did_win or state.vibe < state.max_vibe / 2,
				"%s / %s: чистая игра добивает или почти добивает (осталось %d из %d)"
					% [monster.id, MonsterData.rarity_name(grade),
						state.vibe, state.max_vibe])

	GameState.reset()


## Проиграть чарт без единого промаха, как это делает боевая сцена.
func _play_clean(chart: ChartData, state: BattleState) -> void:
	for i in chart.note_count():
		if state.is_over:
			return
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(Judge.Grade.PERFECT)
			ChartData.NoteType.SHIELD:
				state.block_strike()
			_:
				state.register_hit(Judge.Grade.PERFECT)


## Монстр без мотива не должен ронять бой: играет запасной трек.
func _test_missing_motif_falls_back() -> void:
	print("Без мотива играет запасной трек")
	var orphan := MonsterData.new()
	orphan.id = "no_such_monster"
	orphan.motif_id = ""
	orphan.genre = MonsterData.Genre.DISCO

	check_eq(ChartSelect.chart_stem(orphan, MonsterData.Rarity.COMMON), "",
		"трека для безмотивного монстра нет")
	var chart := ChartSelect.load_for(orphan, MonsterData.Rarity.COMMON)
	check(chart != null, "но бой всё равно получил чарт")
	if chart != null:
		check(chart.note_count() > 0, "и в нём есть ноты")
