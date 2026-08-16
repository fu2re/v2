class_name ChartLoader
extends RefCounted

## Разбор чартов из JSON, которые пишет tools/chartgen.
##
## JSON, а не .tres, потому что чарты порождаются внешним инструментом
## и должны читаться в диффах git.

const CHARTS_DIR := "res://charts"

## Индекс каталога: "<трек>_<грейд>" -> полный путь к файлу.
##
## Нужен потому, что в имени файла теперь есть ещё и темп
## (`disco_zarya_legendary_240.json`), и путь больше не собирается склейкой
## строк. Индекс строится один раз при первом обращении: каталог на триста
## файлов сканируется за миллисекунды, а альтернатива — держать таблицу
## темпов ещё и в GDScript, где она немедленно разойдётся с генератором.
static var _index: Dictionary = {}
static var _indexed := false


static func _build_index() -> void:
	if _indexed:
		return
	_indexed = true
	var dir := DirAccess.open(CHARTS_DIR)
	if dir == null:
		push_warning("Каталог чартов не найден: %s" % CHARTS_DIR)
		return

	for file_name in dir.get_files():
		# В экспортированной сборке ресурсы лежат как .remap
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".json"):
			continue
		var stem := clean.trim_suffix(".json")
		var parts := stem.split("_")
		# Хвост из темпа отбрасываем: ключ — это трек и грейд, а темп
		# в имени существует для человека, который смотрит на папку.
		if parts.size() >= 2 and parts[parts.size() - 1].is_valid_int():
			stem = stem.substr(0, stem.length() - parts[parts.size() - 1].length() - 1)
		_index[stem] = "%s/%s" % [CHARTS_DIR, clean]


## Сбросить индекс. Нужен инструментам, которые пишут чарты на лету:
## Chart Forge сохраняет файл и тут же перечитывает его.
static func refresh() -> void:
	_indexed = false
	_index.clear()


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
	_build_index()
	var key := "%s_%s" % [id, difficulty]
	if not _index.has(key):
		push_error("Чарт не найден: %s" % key)
		return null
	return load_chart(_index[key])


## Все доступные грейды трека, по возрастанию сложности.
## Пустой массив означает, что трека нет вовсе, — это ошибка данных,
## а не «монстр без музыки»: бой без чарта не начнётся.
static func grades_for(id: String) -> PackedStringArray:
	_build_index()
	var out := PackedStringArray()
	for grade in ChartData.GRADE_ORDER:
		if _index.has("%s_%s" % [id, grade]):
			out.append(grade)
	return out


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
