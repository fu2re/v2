extends CanvasLayer

## Танец растению: короткая ритм-фраза на 8 долей.
##
## Тот же Conductor и тот же Judge, что в бою — единый язык взаимодействия
## во всей игре (GDD §1). Отличие одно: здесь нельзя проиграть.

signal finished(level: DanceGrade.Level)

const PHRASE_NOTES := 8
## Пауза перед первой нотой: игроку нужно поймать темп
const LEAD_IN_BEATS := 4.0
const APPROACH_BEATS := 2.0
const JUDGE_Y := 1420.0
const SPAWN_Y := 500.0
const LANE_X := 540.0

var _chart: ChartData = null
var _pool: NotePool = null
var _active: Array[Note] = []
var _next_index: int = 0
var _perfect := 0
var _good := 0
var _running := false

var _title: Label = null
var _feedback: Label = null


func _ready() -> void:
	layer = 40
	visible = false
	# Интерфейс строится ПЕРВЫМ, пул нот добавляется после.
	# Соседи рисуются в порядке дерева, и фон во весь экран, добавленный
	# позже, просто закрывал ноты — они были, но их не было видно
	_build_ui()
	_pool = NotePool.new()
	add_child(_pool)
	Conductor.finished.connect(_on_track_finished)


func start(plant_name: String) -> void:
	_chart = _build_phrase_chart()
	if _chart == null:
		finished.emit(DanceGrade.Level.SKIPPED)
		return

	_perfect = 0
	_good = 0
	_next_index = 0
	_running = true
	_pool.release_all()
	_active.clear()

	_title.text = "Станцуй для %s" % plant_name
	_feedback.text = ""
	visible = true
	Conductor.play(_chart)


## Фраза строится в коде, а не берётся из charts/.
##
## Это ритуал с фиксированным рисунком — ровно одна нота на долю, восемь раз.
## Авторский чарт здесь только добавил бы разнообразия там, где нужна
## предсказуемость: ребёнок должен схватить рисунок с первого раза.
func _build_phrase_chart() -> ChartData:
	var source := ChartLoader.load_by_id("farm_folk", "easy")
	if source == null:
		push_error("Не найден трек фермы farm_folk")
		return null

	var chart := ChartData.new()
	chart.id = "farm_dance"
	chart.genre = source.genre
	chart.bpm = source.bpm
	chart.offset = source.offset
	chart.duration = source.duration
	chart.beats_per_bar = source.beats_per_bar
	chart.audio_path = source.audio_path

	var beats := PackedFloat32Array()
	var types := PackedByteArray()
	for i in PHRASE_NOTES:
		beats.append(LEAD_IN_BEATS + i)
		types.append(ChartData.NoteType.BEAT)
	chart.note_beats = beats
	chart.note_types = types
	return chart


func _process(_delta: float) -> void:
	if not _running or not Conductor.is_playing:
		return

	var horizon := Conductor.song_beat + APPROACH_BEATS
	while _next_index < _chart.note_count() and _chart.note_beats[_next_index] <= horizon:
		var note := _pool.acquire(_chart.note_beats[_next_index], _chart.note_types[_next_index])
		if note != null:
			note.position = Vector2(LANE_X, SPAWN_Y)
			_active.append(note)
		_next_index += 1

	var travel := JUDGE_Y - SPAWN_Y
	for note in _active:
		var beats_left := note.beat - Conductor.song_beat
		note.position.y = SPAWN_Y + (1.0 - beats_left / APPROACH_BEATS) * travel

	var t := Conductor.song_position
	var i := 0
	while i < _active.size():
		var note: Note = _active[i]
		if note.is_judged or t - _chart.beat_to_time(note.beat) > Judge.LATE_WINDOW:
			_pool.release(note)
			_active.remove_at(i)
		else:
			i += 1

	# Фраза кончилась — дальше слушать трек незачем
	if _next_index >= _chart.note_count() and _active.is_empty():
		_finish()


func _input(event: InputEvent) -> void:
	if not _running or not event.is_action_pressed("tap"):
		return

	var t := Conductor.now()
	var best: Note = null
	var best_delta := 0.0
	for note in _active:
		if note.is_judged:
			continue
		var delta := t - _chart.beat_to_time(note.beat)
		if not Judge.in_range(delta):
			continue
		if best == null or absf(delta) < absf(best_delta):
			best = note
			best_delta = delta

	if best == null:
		return

	best.is_judged = true
	var grade := Judge.grade(best_delta)
	match grade:
		Judge.Grade.PERFECT:
			_perfect += 1
			_feedback.text = "Идеально!"
		Judge.Grade.GOOD:
			_good += 1
			_feedback.text = "Хорошо!"
		_:
			_feedback.text = "Почти!"


func _on_track_finished() -> void:
	if _running:
		_finish()


func _finish() -> void:
	if not _running:
		return
	_running = false
	Conductor.stop()
	_pool.release_all()
	_active.clear()

	var level := DanceGrade.level_for(_perfect, _good, PHRASE_NOTES)
	_title.text = DanceGrade.level_name(level)
	_feedback.text = "Растение потянулось к солнцу"

	await get_tree().create_timer(1.1).timeout
	visible = false
	finished.emit(level)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("24391F").darkened(0.15)
	# Подстраховка на случай перестановки узлов: фон всегда позади
	bg.z_index = -10
	add_child(bg)

	_title = Label.new()
	_title.position = Vector2(60, 200)
	_title.size = Vector2(960, 160)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 62)
	_title.add_theme_color_override("font_color", Color("DCC7A4"))
	add_child(_title)

	_feedback = Label.new()
	_feedback.position = Vector2(60, 1560)
	_feedback.size = Vector2(960, 120)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_font_size_override("font_size", 48)
	_feedback.add_theme_color_override("font_color", Color("1ED8FF"))
	add_child(_feedback)

	var line := Line2D.new()
	line.add_point(Vector2(60, JUDGE_Y))
	line.add_point(Vector2(1020, JUDGE_Y))
	line.width = 6.0
	line.default_color = Color("1ED8FF")
	add_child(line)
