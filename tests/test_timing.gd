extends TestHarness

## Headless-проверки ритм-ядра.
##
## Запуск:
##   godot --headless --path E:/v2 tests/test_timing.tscn
##
## Выход ненулевым кодом при провале — чтобы падало в CI, а не молча.

func run_tests() -> void:
	_test_judge_windows()
	_test_combo()
	_test_chart_loading()
	_test_beat_time_roundtrip()
	_test_chart_sorted()
	_test_chart_playable()
	await _test_no_leak_on_chart_switch()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _test_judge_windows() -> void:
	print("Judge: границы окон")
	# Границы берутся из таблицы, а не литералами: правка battle.json
	# не должна краснить тест — он проверяет ЛОГИКУ окон, а не их ширину
	var perfect := Judge.perfect_window()
	var good := Judge.good_window()
	var late := Judge.late_window()
	check(perfect < good and good < late, "окна строго упорядочены")
	check_eq(Judge.grade(0.0), Judge.Grade.PERFECT, "точное попадание")
	check_eq(Judge.grade(perfect - 0.001), Judge.Grade.PERFECT, "у самой границы Perfect")
	check_eq(Judge.grade(-(perfect - 0.001)), Judge.Grade.PERFECT, "Perfect симметричен по знаку")
	check_eq(Judge.grade(perfect + 0.001), Judge.Grade.GOOD, "сразу за границей Perfect")
	check_eq(Judge.grade(good - 0.001), Judge.Grade.GOOD, "у границы Good")
	check_eq(Judge.grade(good + 0.001), Judge.Grade.EARLY_LATE, "за границей Good")
	check_eq(Judge.grade(late + 0.001), Judge.Grade.MISS, "за окном оценки")
	check_eq(Judge.grade(-(late + 0.001)), Judge.Grade.MISS, "промах симметричен")

	# Обувь расширяет окна (GDD §9.1) — то, что раньше было Good, станет Perfect:
	# полтора окна Perfect при вдвое расширенных окнах — всегда Perfect
	check_eq(Judge.grade(perfect * 1.5, 2.0), Judge.Grade.PERFECT,
		"расширенное окно от снаряжения")

	check(Judge.in_range(late), "край окна ещё в зоне оценки")
	check(not Judge.in_range(late + 0.001), "за краем уже вне зоны")


func _test_combo() -> void:
	print("Judge: множитель комбо")
	# Ступени сверяются с сырым battle.json: тест ловит «таблица не читается»,
	# но не мешает дизайнеру двигать пороги
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/battle.json"))
	var battle: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var judge: Dictionary = battle.get("judge", {})
	var steps: Array = judge.get("combo_steps", [])
	if steps.is_empty():
		check(false, "combo_steps есть в battle.json")
		return

	check_eq(Judge.combo_multiplier(0), 1.0, "комбо 0")
	var first: Dictionary = steps[0]
	check_eq(Judge.combo_multiplier(int(first.get("combo", 0)) - 1), 1.0,
		"до первого порога без бонуса")
	for entry: Variant in steps:
		var step: Dictionary = entry
		check_eq(Judge.combo_multiplier(int(step.get("combo", 0))),
			float(step.get("multiplier", 0.0)),
			"комбо %d по таблице" % int(step.get("combo", 0)))
	var last: Dictionary = steps[steps.size() - 1]
	check_eq(Judge.combo_multiplier(9999), float(last.get("multiplier", 0.0)),
		"потолок множителя")


func _test_chart_loading() -> void:
	print("ChartLoader: разбор demo_disco")
	var chart := ChartLoader.load_by_id("demo_disco", "normal")
	check(chart != null, "чарт загрузился")
	if chart == null:
		return

	check_eq(chart.bpm, 120.0, "BPM")
	check_eq(chart.beats_per_bar, 4, "долей в такте")
	check_eq(chart.duration, 34.0, "длительность")
	check(chart.note_count() > 0, "ноты разобраны")
	check_eq(chart.note_beats.size(), chart.note_types.size(), "массивы нот совпадают по длине")
	check(chart.audio() != null, "аудио загрузилось: %s" % chart.audio_path)

	var shields := 0
	for t in chart.note_types:
		if t == ChartData.NoteType.SHIELD:
			shields += 1
	check(shields > 0, "в чарте есть щиты")


func _test_beat_time_roundtrip() -> void:
	print("ChartData: перевод долей и секунд")
	var chart := ChartData.new()
	chart.bpm = 120.0
	chart.offset = 0.0

	check_eq(chart.sec_per_beat(), 0.5, "120 BPM = 0.5 сек на долю")
	check_eq(chart.beat_to_time(4.0), 2.0, "доля 4 = 2 сек")
	check_eq(chart.time_to_beat(2.0), 4.0, "2 сек = доля 4")

	# Смещение не должно ломать обратимость
	chart.offset = 0.317
	for beat in [0.0, 1.5, 63.75]:
		var back: float = chart.time_to_beat(chart.beat_to_time(beat))
		check(absf(back - beat) < 0.0001, "обратимость на доле %f со смещением" % beat)


func _test_chart_sorted() -> void:
	print("ChartLoader: ноты отсортированы")
	var chart := ChartLoader.load_by_id("demo_disco", "hard")
	if chart == null:
		check(false, "hard-чарт загрузился")
		return
	var ok := true
	for i in range(1, chart.note_beats.size()):
		if chart.note_beats[i] < chart.note_beats[i - 1]:
			ok = false
			break
	check(ok, "доли идут по возрастанию — бой на это полагается")


func _test_chart_playable() -> void:
	print("Чарт: играбельность")
	for difficulty in ["easy", "normal", "hard"]:
		var chart := ChartLoader.load_by_id("demo_disco", difficulty)
		if chart == null:
			check(false, "%s загрузился" % difficulty)
			continue

		# Первая нота не раньше конца первого такта — иначе игрок
		# не успевает поймать ритм (GDD, правило разметки 5)
		check(chart.note_beats[0] >= float(chart.beats_per_bar) - 0.001,
			"%s: первая нота не раньше такта 2" % difficulty)

		# Ни одна нота не выходит за длительность трека
		check(chart.note_beats[chart.note_count() - 1] <= chart.total_beats(),
			"%s: последняя нота внутри трека" % difficulty)

		# Щиты не ближе 2 долей друг к другу — ребёнок не успеет
		var last_shield := -1000.0
		var gap_ok := true
		for i in chart.note_count():
			if chart.note_types[i] != ChartData.NoteType.SHIELD:
				continue
			if chart.note_beats[i] - last_shield < 2.0:
				gap_ok = false
				break
			last_shield = chart.note_beats[i]
		check(gap_ok, "%s: щиты не ближе 2 долей" % difficulty)


## Забег бесконечен, и каждый бой грузит свой трек. Если смена чарта копит
## объекты, игра умрёт на длинной сессии — именно там, где должна блистать.
## Проверка идёт по реальному пути: свежий ChartData на каждый бой, как в игре.
func _test_no_leak_on_chart_switch() -> void:
	print("Conductor: смена чарта не копит объекты")
	const ROUNDS := 12
	var names := ["easy", "normal", "hard"]

	# Прогрев: первая загрузка наполняет кеш ресурсов, её в замер брать нельзя
	Conductor.play(ChartLoader.load_by_id("demo_disco", "normal"))
	await _frames(3)
	Conductor.stop()
	await _frames(3)

	var baseline := Performance.get_monitor(Performance.OBJECT_COUNT)

	for i in ROUNDS:
		Conductor.play(ChartLoader.load_by_id("demo_disco", names[i % names.size()]))
		await _frames(2)
		Conductor.stop()
	await _frames(5)

	var growth := Performance.get_monitor(Performance.OBJECT_COUNT) - baseline
	check(growth < ROUNDS,
		"за %d смен чарта прирост объектов %d — должен быть меньше %d"
			% [ROUNDS, growth, ROUNDS])

	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	check_eq(orphans, 0, "нет осиротевших узлов после смены чартов")

	Conductor.stop()
