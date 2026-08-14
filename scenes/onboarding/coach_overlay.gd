extends CanvasLayer

## Наглядный тренер. Ни одного слова — только форма, ритм и движение.
##
## Текст исключён намеренно (GDD §15.5): игру должен понять семилетний,
## который читает по слогам, и взрослый, у которого выключен звук.
## Всё, чему учит этот слой, показывается, а не рассказывается.

## Сколько нот тренер отрабатывает вместе с игроком, прежде чем отойти.
const DEMO_NOTES := 6

var judge_y: float = 1480.0
var lane_x: float = 540.0

var _canvas: Control = null
var _pulse: float = 0.0
var _hand_alpha: float = 1.0
var _hand_scale: float = 1.0
var _notes_hit: int = 0
var _active := true


func _ready() -> void:
	layer = 30
	_canvas = Control.new()
	_canvas.size = Vector2(1080, 1920)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_coach)
	add_child(_canvas)

	Conductor.beat.connect(_on_beat)


func _process(_delta: float) -> void:
	if not _active:
		return
	_canvas.queue_redraw()


## Кольцо сжимается к линии удара ровно за одну долю.
##
## Это главный обучающий приём: игрок видит НЕ «нажми сюда», а «нажми
## в этот момент». Размер кольца — визуальный метроном, и он читается
## раньше, чем ребёнок успевает подумать словами.
func _draw_coach() -> void:
	if not _active or not Conductor.is_playing:
		return

	var phase := fmod(Conductor.song_beat, 1.0)
	var radius := 150.0 - 100.0 * phase
	var alpha := 0.25 + 0.5 * phase
	_canvas.draw_arc(Vector2(lane_x, judge_y), radius, 0.0, TAU, 48,
		Color(0.12, 0.85, 1.0, alpha), 7.0, true)

	# Постоянная цель на линии — куда именно возвращается кольцо
	_canvas.draw_arc(Vector2(lane_x, judge_y), 50.0, 0.0, TAU, 48,
		Color(0.12, 0.85, 1.0, 0.85), 5.0, true)

	if _notes_hit < DEMO_NOTES:
		_draw_hand(phase)


## Призрачный палец опускается к линии в такт. Показывает «как»,
## пока игрок не попал несколько раз сам.
func _draw_hand(phase: float) -> void:
	var press := 1.0 - phase
	var centre := Vector2(lane_x, judge_y + 130.0 + 90.0 * phase)
	var col := Color(1, 1, 1, _hand_alpha * (0.4 + 0.6 * press))

	_canvas.draw_circle(centre, 34.0 * _hand_scale, col)
	_canvas.draw_line(centre + Vector2(0, 30), centre + Vector2(0, 110),
		Color(col.r, col.g, col.b, col.a * 0.7), 16.0)


func _on_beat(_index: int) -> void:
	if not _active:
		return
	# Лёгкий отклик на каждую долю, чтобы связь «звук — движение» читалась
	var tween := create_tween()
	tween.tween_property(self, "_hand_scale", 1.25, 0.06)
	tween.tween_property(self, "_hand_scale", 1.0, 0.14)


## Игрок попал — тренер постепенно отходит в сторону.
func note_hit() -> void:
	_notes_hit += 1
	if _notes_hit == DEMO_NOTES:
		var tween := create_tween()
		tween.tween_property(self, "_hand_alpha", 0.0, 0.6)


func finish() -> void:
	_active = false
	_canvas.queue_redraw()
