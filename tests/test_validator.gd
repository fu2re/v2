extends Node

## Проверки правил разметки в редакторе.
##
## Валидатор Godot и валидатор Python реализуют ОДИН И ТОТ ЖЕ свод правил,
## описанный в .claude/skills/chart/SKILL.md. Эти тесты следят, чтобы
## редакторская половина не разошлась с ним.

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()

	_test_shipped_charts_are_valid()
	_test_catches_untelegraphed_shield()
	_test_catches_shields_too_close()
	_test_catches_dense_intro()
	_test_catches_early_first_note()
	_test_catches_shield_collision()
	_test_density_limit_by_difficulty()
	_test_forge_knows_every_note_type()

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


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
	# Шестнадцатые: 8 нот в секунду при 120 BPM
	var beats: Array = []
	var types: Array = []
	for i in 16:
		beats.append(8.0 + i * 0.25)
		types.append(B)
	var dense_beats: Array = [4.0, 5.0, 6.0, 7.0] + beats
	var dense_types: Array = [B, B, B, B] + types

	check(_has_problem(_make(dense_beats, dense_types, "easy")),
		"шестнадцатые на лёгкой сложности отклонены")
	check(_has_problem(_make(dense_beats, dense_types, "normal")),
		"шестнадцатые на нормальной отклонены")
	check(not _has_problem(_make(dense_beats, dense_types, "hard")),
		"на сложной та же плотность допустима")


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
