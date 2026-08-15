extends Node

## Проверки баланса боя на НАСТОЯЩИХ чартах.
##
## Юнит-тесты проверяют, что механика работает; этот — что с ней можно
## играть. Бой обязан длиться почти весь трек: если монстр падает
## на середине мелодии, музыка обрывается и вся затея с ритмом рушится.

## Насколько поздно в треке должна наступать победа при чистой игре.
const MIN_CLEAN_PROGRESS := 0.6
const MAX_CLEAN_PROGRESS := 1.0

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()

	_test_clean_run_wins_late()
	_test_sloppy_run_loses()
	_test_charts_have_enough_attacks()

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


## Проиграть чарт от начала до конца с заданной точностью.
## Возвращает долю трека, на которой монстр пал, или 1.0 если устоял.
func _simulate(chart: ChartData, monster_id: String, accuracy: float) -> float:
	var state := BattleState.new()
	state.setup(Registry.monster(monster_id), Registry.monster("disco_sprout"), 100, 0)

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
func _test_clean_run_wins_late() -> void:
	print("Чистое прохождение выбивает монстра к концу трека")
	for difficulty in ["easy", "normal", "hard"]:
		var chart := ChartLoader.load_by_id("demo_disco", difficulty)
		if chart == null:
			check(false, "%s: чарт загружен" % difficulty)
			continue

		var state := BattleState.new()
		state.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100, 0)
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
	state.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100, 0)
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
