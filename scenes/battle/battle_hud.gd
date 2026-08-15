class_name BattleHUD
extends CanvasLayer

## Шкалы боя и комбо.
##
## Цвета берутся из зарезервированного набора GAMEPLAY (art/palette.json):
## они не встречаются в окружении, поэтому шкала читается мгновенно
## даже на пёстрой поляне (GDD §11.1.1).

const VIBE_COLOR := Color("FF57C4")     # Настрой монстра
const HEALTH_COLOR := Color("1ED8FF")   # здоровье игрока, сквозное на забег
const SHIELD_COLOR := Color("2E9BFF")   # щит, буфер одного боя
const WINDUP_COLOR := Color("FF5C7A")   # тревога: монстр замахнулся
const TRACK_COLOR := Color(0, 0, 0, 0.45)

const BAR_HEIGHT := 34.0
const MARGIN := 40.0

const FRAME_THICKNESS := 46.0

var _vibe_fill: ColorRect = null
var _health_fill: ColorRect = null
var _shield_fill: ColorRect = null
var _combo_label: Label = null
var _vibe_label: Label = null
var _shield_label: Label = null
var _health_label: Label = null
var _warning_parts: Array[ColorRect] = []
var _vibe_width := 0.0
var _health_width := 0.0
var _shield_width := 0.0


func _ready() -> void:
	layer = 10
	var width := 1080.0 - MARGIN * 2.0
	_vibe_width = width
	_health_width = width
	_shield_width = width

	_vibe_fill = _make_bar(Vector2(MARGIN, 120.0), width, VIBE_COLOR)
	_vibe_label = _add_caption(Vector2(MARGIN, 62.0), "", VIBE_COLOR)

	# Щит над здоровьем: урон съедает его первым, и порядок сверху вниз
	# повторяет порядок, в котором они теряются.
	# У каждой полоски своя подпись С ЧИСЛОМ — без неё тёмная подложка
	# читалась как ещё одна непонятная шкала
	_shield_fill = _make_bar(Vector2(MARGIN, 1700.0), width, SHIELD_COLOR)
	_health_fill = _make_bar(Vector2(MARGIN, 1790.0), width, HEALTH_COLOR)
	_shield_label = _add_caption(Vector2(MARGIN, 1660.0), "", SHIELD_COLOR)
	_health_label = _add_caption(Vector2(MARGIN, 1750.0), "", HEALTH_COLOR)

	_combo_label = Label.new()
	_combo_label.position = Vector2(MARGIN, 1570.0)
	_combo_label.add_theme_font_size_override("font_size", 56)
	_combo_label.add_theme_color_override("font_color", HEALTH_COLOR)
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_combo_label.add_theme_constant_override("outline_size", 10)
	add_child(_combo_label)

	_build_warning_frame()


func _make_bar(pos: Vector2, width: float, color: Color) -> ColorRect:
	var track := ColorRect.new()
	track.position = pos
	track.size = Vector2(width, BAR_HEIGHT)
	track.color = TRACK_COLOR
	add_child(track)

	var fill := ColorRect.new()
	fill.position = pos
	fill.size = Vector2(width, BAR_HEIGHT)
	fill.color = color
	add_child(fill)
	return fill


func _add_caption(pos: Vector2, text: String, colour: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	add_child(label)
	return label


func bind(state: BattleState) -> void:
	state.vibe_changed.connect(_on_vibe_changed)
	state.health_changed.connect(_on_health_changed)
	state.shield_changed.connect(_on_shield_changed)
	state.combo_changed.connect(_on_combo_changed)
	_on_vibe_changed(state.vibe, state.max_vibe)
	_on_health_changed(state.health, state.max_health)
	_on_shield_changed(state.shield, state.max_shield)
	_on_combo_changed(state.combo, 1.0)


func _on_vibe_changed(current: int, maximum: int) -> void:
	_set_fill(_vibe_fill, _vibe_width, current, maximum)
	_vibe_label.text = "Настрой монстра   %d / %d" % [current, maximum]


func _on_health_changed(current: int, maximum: int) -> void:
	_set_fill(_health_fill, _health_width, current, maximum)
	_health_label.text = "Здоровье   %d / %d" % [current, maximum]


func _on_shield_changed(current: int, maximum: int) -> void:
	_set_fill(_shield_fill, _shield_width, current, maximum)
	_shield_label.text = "Щит   %d / %d" % [current, maximum]


func _set_fill(fill: ColorRect, full_width: float, current: int, maximum: int) -> void:
	var ratio := clampf(float(current) / maxf(maximum, 1.0), 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(fill, "size:x", full_width * ratio, 0.15)


func _on_combo_changed(combo: int, multiplier: float) -> void:
	if combo < 2:
		_combo_label.text = ""
		return
	_combo_label.text = "%d  x%.1f" % [combo, multiplier]


## Тревога рисуется РАМКОЙ по краям, а не заливкой всего экрана.
##
## Заливка легла бы поверх нот и разбавила зарезервированные цвета — ровно то,
## что запрещает GDD §11.1.1. Рамка ловится боковым зрением и не трогает центр,
## где игрок читает ноты.
func _build_warning_frame() -> void:
	var w := 1080.0
	var h := 1920.0
	var t := FRAME_THICKNESS
	var rects := [
		Rect2(0, 0, w, t),
		Rect2(0, h - t, w, t),
		Rect2(0, t, t, h - t * 2.0),
		Rect2(w - t, t, t, h - t * 2.0),
	]
	for r: Rect2 in rects:
		var part := ColorRect.new()
		part.position = r.position
		part.size = r.size
		part.color = Color(WINDUP_COLOR.r, WINDUP_COLOR.g, WINDUP_COLOR.b, 0.0)
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(part)
		_warning_parts.append(part)


## Вспышка тревоги на замахе монстра. Держится ровно до удара,
## чтобы игрок связал сигнал с последствием.
func flash_windup(duration: float) -> void:
	for part in _warning_parts:
		var tween := create_tween()
		tween.tween_property(part, "color:a", 0.85, duration * 0.4)
		tween.tween_property(part, "color:a", 0.0, duration * 0.6)
