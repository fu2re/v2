extends Node2D

## Дэнс-баттл, скоуп Фазы 0: падающие ноты, оценка тайминга, комбо.
## Щиты, шкалы Ритма и Настроя, победа — Фаза 1.

signal note_judged(grade: int, delta_seconds: float)

const JUDGE_Y := 1480.0
const SPAWN_Y := 420.0
const LANE_X := 540.0
## За сколько долей до попадания нота появляется. Это и есть «скорость скролла».
const APPROACH_BEATS := 2.0

@export var chart_id: String = "demo_disco"
@export var difficulty: String = "normal"
@export var autostart: bool = true

var chart: ChartData = null
var combo: int = 0
var max_combo: int = 0
var grade_counts := {
	Judge.Grade.PERFECT: 0,
	Judge.Grade.GOOD: 0,
	Judge.Grade.EARLY_LATE: 0,
	Judge.Grade.MISS: 0,
}

var _pool: NotePool = null
var _active: Array[Note] = []
var _next_index: int = 0
var _monster: Sprite2D = null


func _ready() -> void:
	_pool = NotePool.new()
	add_child(_pool)
	_build_stage()

	Conductor.beat.connect(_on_beat)
	Conductor.finished.connect(_on_finished)

	if autostart:
		start()


func start() -> void:
	chart = ChartLoader.load_by_id(chart_id, difficulty)
	if chart == null:
		push_error("Не удалось загрузить чарт %s [%s]" % [chart_id, difficulty])
		return

	_reset()
	Conductor.play(chart)


func _reset() -> void:
	_pool.release_all()
	_active.clear()
	_next_index = 0
	combo = 0
	max_combo = 0
	for key in grade_counts:
		grade_counts[key] = 0


func _process(_delta: float) -> void:
	if not Conductor.is_playing or chart == null:
		return
	_spawn_due_notes()
	_update_positions()
	_expire_missed()


## Нота появляется, когда до её доли осталось APPROACH_BEATS.
func _spawn_due_notes() -> void:
	var horizon := Conductor.song_beat + APPROACH_BEATS
	while _next_index < chart.note_count() and chart.note_beats[_next_index] <= horizon:
		var note := _pool.acquire(chart.note_beats[_next_index], chart.note_types[_next_index])
		if note != null:
			note.position = Vector2(LANE_X, SPAWN_Y)
			_active.append(note)
		_next_index += 1


## Позиция считается ОТ музыкального времени каждый кадр, а не интегрируется.
## Интегрирование накапливает дрейф и привязывает ноты к частоте кадров.
func _update_positions() -> void:
	var travel := JUDGE_Y - SPAWN_Y
	for note in _active:
		var beats_left := note.beat - Conductor.song_beat
		var progress := 1.0 - beats_left / APPROACH_BEATS
		note.position.y = SPAWN_Y + progress * travel


## Нота, ушедшая за окно оценки, считается промахом автоматически.
func _expire_missed() -> void:
	var t := Conductor.song_position
	var i := 0
	while i < _active.size():
		var note: Note = _active[i]
		if not note.is_judged and t - chart.beat_to_time(note.beat) > Judge.LATE_WINDOW:
			_apply_grade(Judge.Grade.MISS, t - chart.beat_to_time(note.beat))
			_retire(i)
		elif note.is_judged:
			_retire(i)
		else:
			i += 1


func _retire(index: int) -> void:
	_pool.release(_active[index])
	_active.remove_at(index)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("tap"):
		return
	if not Conductor.is_playing or chart == null:
		return
	_judge_tap()


func _judge_tap() -> void:
	# Время спрашиваем свежее: кэш Conductor отстаёт на кадр, а это треть
	# окна Perfect
	var t := Conductor.now()

	var best: Note = null
	var best_delta := 0.0
	for note in _active:
		if note.is_judged:
			continue
		var delta := t - chart.beat_to_time(note.beat)
		if not Judge.in_range(delta):
			continue
		if best == null or absf(delta) < absf(best_delta):
			best = note
			best_delta = delta

	if best == null:
		return  # тап в пустоту не наказывается: игра для детей

	best.is_judged = true
	_apply_grade(Judge.grade(best_delta), best_delta)


func _apply_grade(grade: int, delta: float) -> void:
	grade_counts[grade] += 1
	if grade == Judge.Grade.MISS:
		combo = 0
	else:
		combo += 1
		max_combo = maxi(max_combo, combo)
	note_judged.emit(grade, delta)


func _on_beat(index: int) -> void:
	if _monster == null:
		return
	# Покачивание монстра в такт. В Фазе 1 сменится скелетной анимацией
	var dir := 1.0 if index % 2 == 0 else -1.0
	var tween := create_tween()
	tween.tween_property(_monster, "rotation", dir * 0.06, 0.12)
	tween.tween_property(_monster, "rotation", 0.0, 0.12)


func _on_finished() -> void:
	_pool.release_all()
	_active.clear()


func _build_stage() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	# Фон боя притемнён — иначе земляная палитра спорит с нотами (GDD §11.1.1)
	bg.color = Color("33512A").darkened(0.30)
	bg.z_index = -10
	add_child(bg)

	var line := Line2D.new()
	line.add_point(Vector2(60, JUDGE_Y))
	line.add_point(Vector2(1020, JUDGE_Y))
	line.width = 6.0
	line.default_color = Color("1ED8FF")
	add_child(line)

	_monster = Sprite2D.new()
	var tex := load("res://art/placeholder/monster_synth_slime.png") as Texture2D
	if tex != null:
		_monster.texture = tex
		_monster.scale = Vector2(4, 4)
	_monster.position = Vector2(LANE_X, 260)
	add_child(_monster)
