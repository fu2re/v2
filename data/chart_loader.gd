class_name ChartLoader
extends RefCounted

## Разбор чартов из JSON, которые пишет tools/chartgen.
##
## JSON, а не .tres, потому что чарты порождаются внешним инструментом
## и должны читаться в диффах git.

const CHARTS_DIR := "res://charts"


## Загрузить чарт. Возвращает null и пишет ошибку, если файл битый —
## падать на разборе данных нельзя, чарт может прийти из тулы.
static func load_chart(path: String) -> ChartData:
	if not FileAccess.file_exists(path):
		push_error("Чарт не найден: %s" % path)
		return null

	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Чарт не разобрался как JSON-объект: %s" % path)
		return null

	return _from_dict(parsed as Dictionary, path)


static func load_by_id(id: String, difficulty: String = "normal") -> ChartData:
	return load_chart("%s/%s_%s.json" % [CHARTS_DIR, id, difficulty])


static func _from_dict(d: Dictionary, source: String) -> ChartData:
	var chart := ChartData.new()
	chart.id = d.get("id", "")
	chart.genre = d.get("genre", "")
	chart.difficulty = d.get("difficulty", "normal")
	chart.bpm = float(d.get("bpm", 120.0))
	chart.offset = float(d.get("offset", 0.0))
	chart.duration = float(d.get("duration", 0.0))
	chart.beats_per_bar = int(d.get("beats_per_bar", 4))
	chart.audio_path = d.get("audio", "")

	if chart.bpm <= 0.0:
		push_error("Чарт %s: некорректный BPM %f" % [source, chart.bpm])
		return null

	var beats := PackedFloat32Array()
	var types := PackedByteArray()
	for entry: Variant in d.get("notes", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var note: Dictionary = entry
		var type_name: String = note.get("type", "beat")
		if not ChartData.TYPE_NAMES.has(type_name):
			push_warning("Чарт %s: неизвестный тип ноты '%s', пропущена" % [source, type_name])
			continue
		beats.append(float(note.get("beat", 0.0)))
		types.append(ChartData.TYPE_NAMES[type_name])

	# Порядок гарантируем здесь, а не доверяем файлу: бой полагается на то,
	# что ноты отсортированы, и проверять это каждый кадр слишком дорого
	_sort_by_beat(beats, types)
	chart.note_beats = beats
	chart.note_types = types

	var p_beats := PackedFloat32Array()
	var p_actions := PackedStringArray()
	for entry: Variant in d.get("monster_pattern", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = entry
		p_beats.append(float(event.get("beat", 0.0)))
		p_actions.append(event.get("action", ""))
	chart.pattern_beats = p_beats
	chart.pattern_actions = p_actions

	return chart


## Сортировка вставками: чарты приходят почти отсортированными,
## на таких данных это быстрее общей сортировки и не требует временных массивов.
static func _sort_by_beat(beats: PackedFloat32Array, types: PackedByteArray) -> void:
	for i in range(1, beats.size()):
		var beat := beats[i]
		var type := types[i]
		var j := i - 1
		while j >= 0 and beats[j] > beat:
			beats[j + 1] = beats[j]
			types[j + 1] = types[j]
			j -= 1
		beats[j + 1] = beat
		types[j + 1] = type
