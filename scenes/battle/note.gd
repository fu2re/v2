class_name Note
extends Node2D

## Визуал одной ноты. Узел переиспользуется из пула и никогда не удаляется
## во время боя: queue_free/instantiate при 8 нотах в секунду дают
## заметный джиттер на слабых телефонах.

const RADIUS := 46.0

## Цвета из art/palette.json, набор GAMEPLAY. Эти цвета зарезервированы
## и не встречаются в окружении — иначе ноту не найти взглядом (GDD §11.1.1).
const COLORS := {
	ChartData.NoteType.BEAT: Color("00E5FF"),
	ChartData.NoteType.SKILL: Color("FF6BDE"),
	ChartData.NoteType.SHIELD: Color("2E9BFF"),
	ChartData.NoteType.HEAVY: Color("FF3B5C"),
	# Атака — единственная нота, наносящая урон. Она обязана отличаться
	# и цветом, и формой: игрок должен узнавать её краем глаза
	ChartData.NoteType.ATTACK: Color("FFD24D"),
}

var beat: float = 0.0
var type: int = ChartData.NoteType.BEAT
var is_judged: bool = false
## Испорчена ли серия перед этой атакой. Серая звезда сразу говорит,
## что удар уже не сработает — гадать не придётся.
var is_dulled: bool = false
## Дорожка: обычные ноты падают правее центра, особые левее, и каждая
## съезжает к своей кнопке. Подсказка «куда жать» встроена в траекторию,
## а не написана словами (GDD §4.1).
var lane: int = NoteRules.Lane.NORMAL


var _color: Color = COLORS[ChartData.NoteType.BEAT]


func setup(note_beat: float, note_type: int) -> void:
	beat = note_beat
	type = note_type
	lane = NoteRules.primary_lane(note_type)
	is_judged = false
	is_dulled = false
	_color = COLORS.get(note_type, COLORS[ChartData.NoteType.BEAT])
	visible = true
	queue_redraw()


func release() -> void:
	visible = false
	is_judged = true


func _draw() -> void:
	match type:
		ChartData.NoteType.SKILL:
			_draw_diamond()
		ChartData.NoteType.SHIELD:
			_draw_shield()
		ChartData.NoteType.ATTACK:
			_draw_star()
		ChartData.NoteType.HEAVY:
			_draw_crit()
		_:
			draw_circle(Vector2.ZERO, RADIUS, _color)
			draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, _color.lightened(0.4), 5.0, true)


func _draw_diamond() -> void:
	var r := RADIUS * 1.1
	var points := PackedVector2Array([
		Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0),
	])
	draw_colored_polygon(points, _color)
	draw_polyline(points + PackedVector2Array([points[0]]), _color.lightened(0.4), 5.0, true)


## Звезда — форма атаки. Серая означает «серия испорчена, удар вхолостую».
func _draw_star() -> void:
	# Светло-серый, а не тёмный: на тёмном фоне тёмная звезда сливалась
	var colour := Color("C9C4B8") if is_dulled else _color
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + i * PI / 5.0
		var r := RADIUS * 1.25 if i % 2 == 0 else RADIUS * 0.5
		points.append(Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, colour)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 4.0, true)


func _draw_shield() -> void:
	var r := RADIUS
	var points := PackedVector2Array([
		Vector2(0, -r), Vector2(r * 0.85, -r * 0.4),
		Vector2(r * 0.7, r * 0.55), Vector2(0, r),
		Vector2(-r * 0.7, r * 0.55), Vector2(-r * 0.85, -r * 0.4),
	])
	draw_colored_polygon(points, _color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 5.0, true)


## Крит монстра — шипастый щит с восклицательным знаком.
##
## Форма нарочно похожа на обычный щит (это тоже атака, и берётся той же
## особой кнопкой), но с шипами и красная: пропущенный крит бьёт вчетверо,
## и его нельзя спутать с обычным ударом. Пока здесь стояла бутылочка,
## оставшаяся от упразднённых зелий, игрок ждал лечения и получал по лбу.
func _draw_crit() -> void:
	var r := RADIUS * 1.15
	var light := _color.lightened(0.45)

	# Шипы: восемь лучей наружу — силуэт «опасно» без единого слова
	var spikes := PackedVector2Array()
	for i in 16:
		var angle := -PI * 0.5 + i * PI / 8.0
		var radius := r * 1.35 if i % 2 == 0 else r * 0.95
		spikes.append(Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(spikes, _color)
	draw_polyline(spikes + PackedVector2Array([spikes[0]]), light, 4.0, true)

	# Восклицательный знак внутри
	draw_rect(Rect2(Vector2(-r * 0.12, -r * 0.55),
		Vector2(r * 0.24, r * 0.72)), Color.WHITE, true)
	draw_circle(Vector2(0, r * 0.45), r * 0.15, Color.WHITE)
