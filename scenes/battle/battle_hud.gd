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

## Зоны тапа: правая половина — обычный бит, левая — особый (GDD §4.1).
const LANE_HINT_TOP := 1500.0
const LANE_HINT_HEIGHT := 130.0
const NORMAL_LANE_COLOR := Color("00E5FF")
const SPECIAL_LANE_COLOR := Color("FF6BDE")

var _vibe_fill: ColorRect = null
var _health_fill: ColorRect = null
var _shield_fill: ColorRect = null
var _combo_label: Label = null
var _vibe_label: Label = null
var _monster_label: Label = null
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
	_monster_label = _add_caption(Vector2(MARGIN, 14.0), "", Color.WHITE)
	_monster_label.add_theme_font_size_override("font_size", 40)
	_vibe_label = _add_caption(Vector2(MARGIN, 62.0), "", VIBE_COLOR)

	_build_lane_hints()

	# Щит над здоровьем: урон съедает его первым, и порядок сверху вниз
	# повторяет порядок, в котором они теряются.
	# У каждой полоски своя подпись С ЧИСЛОМ — без неё тёмная подложка
	# читалась как ещё одна непонятная шкала
	_shield_fill = _make_bar(Vector2(MARGIN, 1700.0), width, SHIELD_COLOR)
	_health_fill = _make_bar(Vector2(MARGIN, 1790.0), width, HEALTH_COLOR)
	_shield_label = _add_caption(Vector2(MARGIN, 1660.0), "", SHIELD_COLOR)
	_health_label = _add_caption(Vector2(MARGIN, 1750.0), "", HEALTH_COLOR)

	# Комбо по центру и крупно. Раньше оно стояло в углу за танцорами
	# и его попросту не замечали — а это главный показатель того,
	# что серия идёт чисто
	_combo_label = Label.new()
	# Слева и ниже монстра: по центру оно налезало на него, а дорожка нот
	# идёт посередине — единственное свободное место это левый край
	_combo_label.position = Vector2(MARGIN, 640.0)
	_combo_label.size = Vector2(400, 140)
	_combo_label.add_theme_font_size_override("font_size", 80)
	_combo_label.add_theme_color_override("font_color", Color("FFD24D"))
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_combo_label.add_theme_constant_override("outline_size", 10)
	add_child(_combo_label)

	_build_warning_frame()


## Две полосы внизу: правая — обычный бит, левая — особый.
##
## Живут в HUD, а не в сцене боя, намеренно: CanvasLayer не наследует
## трансформ родителя, поэтому подсказки стоят на месте, когда экран
## трясётся от пропущенного удара. Зона тапа не должна прыгать.
func _build_lane_hints() -> void:
	var half := 1080.0 * 0.5
	var pairs := [
		[NoteRules.Lane.SPECIAL, 0.0, SPECIAL_LANE_COLOR],
		[NoteRules.Lane.NORMAL, half, NORMAL_LANE_COLOR],
	]

	for pair: Array in pairs:
		var lane: int = pair[0]
		var left: float = pair[1]
		var colour: Color = pair[2]

		var zone := ColorRect.new()
		zone.position = Vector2(left, LANE_HINT_TOP)
		zone.size = Vector2(half, LANE_HINT_HEIGHT)
		# Едва заметная заливка: подсказка, а не украшение. Ноты обязаны
		# оставаться самым ярким на экране (GDD §11.1.1)
		zone.color = Color(colour.r, colour.g, colour.b, 0.10)
		zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(zone)

		var caption := _add_caption(
			Vector2(left + 40.0, LANE_HINT_TOP + 30.0),
			NoteRules.lane_name(lane), colour)
		caption.add_theme_font_size_override("font_size", 34)
		caption.size.x = half - 80.0
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Разделитель посередине: граница половин должна быть видна глазом,
	# иначе игрок узнаёт о ней только по незасчитанному попаданию
	var divider := ColorRect.new()
	divider.position = Vector2(half - 3.0, LANE_HINT_TOP)
	divider.size = Vector2(6.0, LANE_HINT_HEIGHT)
	divider.color = Color(1, 1, 1, 0.25)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)


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


## Подпись монстра: имя и грейд.
##
## Слово «Обычный» не пишем — оно ничего не сообщает и лишь занимает место.
## Грейд должен бросаться в глаза именно тогда, когда он есть.
func set_monster(monster: MonsterInstance) -> void:
	if monster == null:
		return
	var suffix := ""
	if monster.grade > MonsterData.Rarity.COMMON:
		suffix = " · " + monster.grade_name()
	_monster_label.text = monster.display_name() + suffix
	_monster_label.add_theme_color_override("font_color", monster.grade_color())


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
	_combo_label.text = "%d  ×%.1f" % [combo, multiplier]
	# Толчок на каждом шаге: растущее число замечают, статичное — нет
	var tween := create_tween()
	tween.tween_property(_combo_label, "scale", Vector2(1.18, 1.18), 0.05)
	tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.12)


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


## Вспышка по экрану от удавшейся атаки.
##
## Отличается от тревоги замаха и цветом, и тем, что гаснет быстро:
## это награда, а не предупреждение, и задерживаться она не должна.
func flash_hit() -> void:
	for part in _warning_parts:
		var tween := create_tween()
		tween.tween_property(part, "color", Color(1.0, 0.82, 0.30, 0.9), 0.05)
		tween.tween_property(part, "color", Color(WINDUP_COLOR.r, WINDUP_COLOR.g,
			WINDUP_COLOR.b, 0.0), 0.25)
