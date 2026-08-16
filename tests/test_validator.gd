extends TestHarness

## Проверки правил разметки в редакторе.
##
## Валидатор Godot и валидатор Python реализуют ОДИН И ТОТ ЖЕ свод правил,
## описанный в .claude/skills/chart/SKILL.md. Эти тесты следят, чтобы
## редакторская половина не разошлась с ним.

func run_tests() -> void:

	_test_shipped_charts_are_valid()
	_test_catches_untelegraphed_shield()
	_test_catches_shields_too_close()
	_test_catches_dense_intro()
	_test_catches_early_first_note()
	_test_catches_shield_collision()
	_test_density_limit_by_difficulty()
	_test_catches_notes_closer_than_tap_window()
	_test_forge_knows_every_note_type()


func _make(beats: Array, types: Array, difficulty := "normal") -> ChartData:
	var chart := ChartData.new()
	chart.id = "synthetic"
	chart.difficulty = difficulty
	chart.bpm = 120.0
	chart.beats_per_bar = 4
	chart.duration = 60.0

	var b := PackedFloat32Array()
	var t := PackedByteArray()
	for i in beats.size():
		b.append(beats[i])
		t.append(types[i])
	chart.note_beats = b
	chart.note_types = t
	return chart


func _with_windups(chart: ChartData) -> ChartData:
	var beats := PackedFloat32Array()
	var actions := PackedStringArray()
	for i in chart.note_count():
		if chart.note_types[i] != ChartData.NoteType.SHIELD:
			continue
		beats.append(chart.note_beats[i] - ChartValidator.WINDUP_LEAD)
		actions.append("windup")
	chart.pattern_beats = beats
	chart.pattern_actions = actions
	return chart


func _has_problem(chart: ChartData) -> bool:
	return not ChartValidator.validate(chart).is_empty()


## Всё, что лежит в charts/, обязано проходить проверку. Если этот тест упал,
## значит в репозиторий попал нечестный чарт.
func _test_shipped_charts_are_valid() -> void:
	print("Чарты в репозитории проходят проверку")
	for id in ["demo_disco", "farm_folk"]:
		for difficulty in ["easy", "normal", "hard"]:
			var chart := ChartLoader.load_by_id(id, difficulty)
			if chart == null:
				continue
			var problems := ChartValidator.validate(chart)
			check(problems.is_empty(), "%s [%s]: %s"
				% [id, difficulty, ChartValidator.describe_all(problems)])


func _test_catches_untelegraphed_shield() -> void:
	print("Ловит щит без замаха")
	var B := ChartData.NoteType.BEAT
	var S := ChartData.NoteType.SHIELD
	var chart := _make([4.0, 8.0, 12.0], [B, B, S])
	check(_has_problem(chart), "щит без замаха отклонён")

	check(not _has_problem(_with_windups(chart)), "с замахом тот же чарт проходит")

	# Замах впритык не считается: телеграф обязан быть заранее
	chart.pattern_beats = PackedFloat32Array([11.0])
	chart.pattern_actions = PackedStringArray(["windup"])
	check(_has_problem(chart), "замах за одну долю — слишком поздно")


func _test_catches_shields_too_close() -> void:
	print("Ловит щиты подряд")
	var B := ChartData.NoteType.BEAT
	var S := ChartData.NoteType.SHIELD
	var chart := _with_windups(_make([4.0, 8.0, 9.0], [B, S, S]))
	check(_has_problem(chart), "щиты через одну долю отклонены")

	var ok := _with_windups(_make([4.0, 8.0, 10.0], [B, S, S]))
	check(not _has_problem(ok), "щиты через две доли проходят")


func _test_catches_dense_intro() -> void:
	print("Ловит плотный вход в бой")
	var B := ChartData.NoteType.BEAT
	check(_has_problem(_make([4.0, 4.5, 6.0], [B, B, B])),
		"восьмые в первых двух тактах отклонены")
	check(not _has_problem(_make([4.0, 5.0, 6.0, 8.5, 9.0], [B, B, B, B, B])),
		"четверти во вступлении и восьмые после — проходит")


func _test_catches_early_first_note() -> void:
	print("Ловит слишком ранний старт")
	var B := ChartData.NoteType.BEAT
	check(_has_problem(_make([2.0, 5.0, 6.0], [B, B, B])),
		"нота на второй доле отклонена — игрок не поймал ритм")
	check(not _has_problem(_make([4.0, 5.0, 6.0], [B, B, B])),
		"нота ровно на четвёртой доле проходит")


func _test_catches_shield_collision() -> void:
	print("Ловит щит поверх другой ноты")
	var B := ChartData.NoteType.BEAT
	var S := ChartData.NoteType.SHIELD
	var chart := _with_windups(_make([4.0, 8.0, 8.0], [B, S, B]))
	check(_has_problem(chart), "щит и бит на одной доле отклонены")


func _test_density_limit_by_difficulty() -> void:
	print("Предел плотности зависит от сложности")
	var B := ChartData.NoteType.BEAT
	# Шаг 0.3 доли при 120 BPM = 150 мс: интервал (правило 8) соблюдён,
	# перегружена только средняя плотность — тест мерит ровно её
	var beats: Array = []
	var types: Array = []
	for i in 16:
		beats.append(8.0 + i * 0.3)
		types.append(B)
	var dense_beats: Array = [4.0, 5.0, 6.0, 7.0] + beats
	var dense_types: Array = [B, B, B, B] + types

	check(_has_problem(_make(dense_beats, dense_types, "easy")),
		"плотный поток на лёгкой сложности отклонён")
	check(_has_problem(_make(dense_beats, dense_types, "normal")),
		"плотный поток на нормальной отклонён")
	check(not _has_problem(_make(dense_beats, dense_types, "hard")),
		"на сложной та же плотность допустима")


## Правило 8: соседние ноты не ближе окна GOOD с запасом. Средняя плотность
## пары впритык не ловит — окно одного тапа накрывало обе, и вторая уходила
## в промах, в котором игрок не виноват.
func _test_catches_notes_closer_than_tap_window() -> void:
	print("Ловит ноты ближе окна тапа")
	var B := ChartData.NoteType.BEAT
	# 0.25 доли при 120 BPM = 125 мс — меньше минимума в 132 мс
	check(_has_problem(_make([4.0, 5.0, 6.0, 7.0, 8.0, 8.25], [B, B, B, B, B, B])),
		"пара нот в 125 мс отклонена")
	# 0.3 доли = 150 мс — уже честно
	check(not _has_problem(_make([4.0, 5.0, 6.0, 7.0, 8.0, 8.3], [B, B, B, B, B, B])),
		"150 мс между нотами — годно")


## Редактор обязан знать КАЖДЫЙ тип ноты из enum.
##
## Атакующие ноты добавили в ChartData, а таблицы Chart Forge не тронули —
## и редактор падал на отрисовке любого настоящего чарта:
## «Out of bounds get index '4' (on base: 'Dictionary')». Ошибка вылезала
## в логе, но не роняла ни один тест, потому что никто не сверял таблицы
## с enum. Теперь сверяет.
func _test_forge_knows_every_note_type() -> void:
	print("Chart Forge знает все типы нот")
	var forge_script := load("res://tools/chart_forge/chart_forge.gd")
	var colors: Dictionary = forge_script.TYPE_COLORS
	var names: Dictionary = forge_script.TYPE_NAMES

	for type_name: String in ChartData.NoteType.keys():
		var value: int = ChartData.NoteType[type_name]
		check(colors.has(value), "у типа %s есть цвет в редакторе" % type_name)
		check(names.has(value), "у типа %s есть подпись в редакторе" % type_name)
