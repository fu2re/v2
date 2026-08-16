extends Node2D

## Chart Forge — редактор карт нот.
##
## Живёт ВНУТРИ Godot, а не в браузере, и это не удобство, а требование
## корректности (GDD §10.3): редактор обязан использовать тот же Conductor
## и ту же модель буферизации звука, что и игра. Чарт, идеально выровненный
## во внешнем инструменте, поедет в движке.

const LANE_X := 300.0
const LANE_WIDTH := 700.0
## Разнос дорожек, как в бою: особые ноты левее центра, обычные правее.
const LANE_OFFSET := 90.0
const TIMELINE_TOP := 300.0
const TIMELINE_BOTTOM := 1560.0
## Сколько долей помещается в окно таймлайна.
const VISIBLE_BEATS := 16.0

const TYPE_COLORS := {
	ChartData.NoteType.BEAT: Color("00E5FF"),
	ChartData.NoteType.SKILL: Color("FF6BDE"),
	ChartData.NoteType.SHIELD: Color("2E9BFF"),
	ChartData.NoteType.HEAVY: Color("B87AFF"),
	# Цвет тот же, что у звезды в бою: редактор обязан показывать
	# ноту так, как её увидит игрок
	ChartData.NoteType.ATTACK: Color("FFD24D"),
}

const TYPE_NAMES := {
	ChartData.NoteType.BEAT: "Бит",
	ChartData.NoteType.SKILL: "Скилл",
	ChartData.NoteType.SHIELD: "Щит",
	ChartData.NoteType.HEAVY: "Перекус",
	ChartData.NoteType.ATTACK: "Удар",
}

@export var chart_id: String = "demo_disco"
@export var difficulty: String = "normal"

var chart: ChartData = null
var scroll_beat: float = 0.0
## Шаг привязки в долях: 1 — четверти, 0.5 — восьмые, 0.25 — шестнадцатые.
var snap: float = 0.5
var brush: int = ChartData.NoteType.BEAT

var _canvas: Control = null
var _status: Label = null
var _info: Label = null
var _problems: Array[ChartValidator.Problem] = []


func _ready() -> void:
	_build_ui()
	load_chart()


func load_chart() -> void:
	chart = ChartLoader.load_by_id(chart_id, difficulty)
	if chart == null:
		_status.text = "Не найден чарт %s [%s]" % [chart_id, difficulty]
		return
	scroll_beat = 0.0
	_revalidate()


func _revalidate() -> void:
	_problems = ChartValidator.validate(chart)
	_status.text = ChartValidator.describe_all(_problems)
	_status.add_theme_color_override("font_color",
		Color("97C46A") if _problems.is_empty() else Color("FF5C7A"))
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_info() -> void:
	if chart == null:
		return
	var counts := {}
	for t in chart.note_types:
		counts[t] = counts.get(t, 0) + 1
	var parts: Array[String] = []
	for type: int in TYPE_NAMES:
		parts.append("%s %d" % [TYPE_NAMES[type], counts.get(type, 0)])
	_info.text = "%s [%s] · %.0f BPM · %.1f сек · %s · шаг 1/%d" % [
		chart.id, chart.difficulty, chart.bpm, chart.duration,
		"  ".join(parts), int(round(1.0 / snap)),
	]


# --- отрисовка ---------------------------------------------------------------

func _draw_timeline() -> void:
	if chart == null:
		return

	var height := TIMELINE_BOTTOM - TIMELINE_TOP
	var bpb := float(chart.beats_per_bar)

	# Сетка: сильные доли ярче слабых, чтобы такт читался без счёта
	var first := floorf(scroll_beat)
	for i in int(VISIBLE_BEATS) + 2:
		var beat := first + i
		var y := _beat_to_y(beat)
		if y < TIMELINE_TOP - 4 or y > TIMELINE_BOTTOM + 4:
			continue
		var is_bar := fmod(beat, bpb) == 0.0
		_canvas.draw_line(
			Vector2(LANE_X - 60, y), Vector2(LANE_X + LANE_WIDTH, y),
			Color(1, 1, 1, 0.35 if is_bar else 0.12), 3.0 if is_bar else 1.0)
		if is_bar:
			_canvas.draw_string(ThemeDB.fallback_font, Vector2(LANE_X - 200, y + 10),
				"такт %d" % (int(beat) / int(bpb) + 1), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 28, Color("ADA99F"))

	# Замахи монстра — за ними встают щиты, и связь должна быть видна глазом
	for i in chart.pattern_beats.size():
		var y := _beat_to_y(chart.pattern_beats[i])
		if y < TIMELINE_TOP or y > TIMELINE_BOTTOM:
			continue
		var is_windup: bool = chart.pattern_actions[i] == "windup"
		_canvas.draw_line(
			Vector2(LANE_X + LANE_WIDTH + 10, y), Vector2(LANE_X + LANE_WIDTH + 90, y),
			Color("FF5C7A") if is_windup else Color("FFD24D"), 6.0)
		_canvas.draw_string(ThemeDB.fallback_font,
			Vector2(LANE_X + LANE_WIDTH + 100, y + 10),
			"замах" if is_windup else "УДАР", HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
			Color("FF5C7A") if is_windup else Color("FFD24D"))

	# Разделитель дорожек: слева особые ноты, справа обычные — ровно как
	# в бою. Разметка должна вестись в той же картине, которую увидит игрок,
	# иначе редактор врёт о том, чем окажется чарт
	var centre := LANE_X + LANE_WIDTH * 0.5
	_canvas.draw_line(Vector2(centre, TIMELINE_TOP), Vector2(centre, TIMELINE_BOTTOM),
		Color(1, 1, 1, 0.12), 3.0)

	# Ноты
	for i in chart.note_count():
		var y := _beat_to_y(chart.note_beats[i])
		if y < TIMELINE_TOP - 30 or y > TIMELINE_BOTTOM + 30:
			continue
		var type: int = chart.note_types[i]
		var shift := LANE_OFFSET if NoteRules.primary_lane(type) == NoteRules.Lane.NORMAL \
			else -LANE_OFFSET
		_canvas.draw_circle(Vector2(centre + shift, y), 26.0, TYPE_COLORS[type])

	# Проблемы отмечаются прямо на таймлайне: список замечаний внизу читают,
	# а красную метку на такте видят сразу
	for problem in _problems:
		var y := _beat_to_y(problem.beat)
		if y < TIMELINE_TOP or y > TIMELINE_BOTTOM:
			continue
		_canvas.draw_rect(Rect2(LANE_X - 60, y - 3, LANE_WIDTH + 60, 6),
			Color("FF2E63"))


func _beat_to_y(beat: float) -> float:
	var height := TIMELINE_BOTTOM - TIMELINE_TOP
	return TIMELINE_TOP + (beat - scroll_beat) / VISIBLE_BEATS * height


func _y_to_beat(y: float) -> float:
	var height := TIMELINE_BOTTOM - TIMELINE_TOP
	return scroll_beat + (y - TIMELINE_TOP) / height * VISIBLE_BEATS


# --- правка ------------------------------------------------------------------

func _canvas_input(event: InputEvent) -> void:
	if chart == null:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return

	var mb := event as InputEventMouseButton
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			scroll_beat = maxf(scroll_beat - 1.0, 0.0)
			_canvas.queue_redraw()
		MOUSE_BUTTON_WHEEL_DOWN:
			scroll_beat = minf(scroll_beat + 1.0, chart.total_beats())
			_canvas.queue_redraw()
		MOUSE_BUTTON_LEFT:
			_place_note(_snapped(_y_to_beat(mb.position.y)))
		MOUSE_BUTTON_RIGHT:
			_erase_note(_snapped(_y_to_beat(mb.position.y)))


func _snapped(beat: float) -> float:
	return maxf(roundf(beat / snap) * snap, 0.0)


func _find_note(beat: float) -> int:
	for i in chart.note_count():
		if absf(chart.note_beats[i] - beat) < snap * 0.4:
			return i
	return -1


func _place_note(beat: float) -> void:
	var existing := _find_note(beat)
	if existing >= 0:
		# Повторный клик по существующей ноте меняет её тип, а не плодит дубли
		chart.note_types[existing] = brush
		_revalidate()
		return

	var beats := chart.note_beats
	var types := chart.note_types
	var index := 0
	while index < beats.size() and beats[index] < beat:
		index += 1
	beats.insert(index, beat)
	types.insert(index, brush)
	chart.note_beats = beats
	chart.note_types = types
	_revalidate()


func _erase_note(beat: float) -> void:
	var index := _find_note(beat)
	if index < 0:
		return
	var beats := chart.note_beats
	var types := chart.note_types
	beats.remove_at(index)
	types.remove_at(index)
	chart.note_beats = beats
	chart.note_types = types
	_revalidate()


func _add_windup_for_shields() -> void:
	## Расставить замахи под все щиты. Ручная разметка каждого — рутина,
	## а правило «щит без замаха нечестен» нарушать нельзя.
	var beats := PackedFloat32Array()
	var actions := PackedStringArray()
	for i in chart.note_count():
		if chart.note_types[i] != ChartData.NoteType.SHIELD:
			continue
		beats.append(chart.note_beats[i] - ChartValidator.WINDUP_LEAD)
		actions.append("windup")
		beats.append(chart.note_beats[i])
		actions.append("strike")
	chart.pattern_beats = beats
	chart.pattern_actions = actions
	_revalidate()


# --- сохранение и плейтест ---------------------------------------------------

func _save() -> void:
	if chart == null:
		return
	if not _problems.is_empty():
		_status.text = "Не сохранено: сначала почини замечания\n" \
			+ ChartValidator.describe_all(_problems)
		return

	var notes: Array = []
	for i in chart.note_count():
		notes.append({
			"beat": snappedf(chart.note_beats[i], 0.001),
			"type": _type_key(chart.note_types[i]),
		})

	var pattern: Array = []
	for i in chart.pattern_beats.size():
		pattern.append({
			"beat": snappedf(chart.pattern_beats[i], 0.001),
			"action": chart.pattern_actions[i],
		})

	var data := {
		"id": chart.id,
		"genre": chart.genre,
		"bpm": chart.bpm,
		"difficulty": chart.difficulty,
		"duration": chart.duration,
		"audio": chart.audio_path,
		"beats_per_bar": chart.beats_per_bar,
		"offset": chart.offset,
		"notes": notes,
		"monster_pattern": pattern,
	}

	var path := "res://charts/%s_%s.json" % [chart.id, chart.difficulty]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status.text = "Не удалось записать %s" % path
		return
	file.store_string(JSON.stringify(data, "  "))
	_status.text = "Сохранено: %s" % path


static func _type_key(type: int) -> String:
	for key: String in ChartData.TYPE_NAMES:
		if ChartData.TYPE_NAMES[key] == type:
			return key
	return "beat"


## Плейтест в НАСТОЯЩЕМ бою, а не в приближении. В этом весь смысл того,
## что редактор живёт внутри движка.
func _playtest() -> void:
	if chart == null:
		return
	_save()
	get_tree().change_scene_to_file("res://scenes/battle/DanceBattle.tscn")


# --- интерфейс ---------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("1B2A33")
	add_child(bg)

	var title := Label.new()
	title.position = Vector2(40, 30)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color("DCC7A4"))
	title.text = "Chart Forge"
	add_child(title)

	_info = Label.new()
	_info.position = Vector2(40, 100)
	_info.size = Vector2(1000, 60)
	_info.add_theme_font_size_override("font_size", 26)
	_info.add_theme_color_override("font_color", Color("ADA99F"))
	add_child(_info)

	_canvas = Control.new()
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(1080, 1920)
	_canvas.draw.connect(_draw_timeline)
	_canvas.gui_input.connect(_canvas_input)
	add_child(_canvas)

	var tools := HBoxContainer.new()
	tools.position = Vector2(40, 170)
	tools.add_theme_constant_override("separation", 12)
	add_child(tools)

	for type: int in TYPE_NAMES:
		var button := Button.new()
		button.text = TYPE_NAMES[type]
		button.custom_minimum_size = Vector2(160, 70)
		button.add_theme_font_size_override("font_size", 26)
		button.add_theme_color_override("font_color", TYPE_COLORS[type])
		button.pressed.connect(func():
			brush = type
			_refresh_info())
		tools.add_child(button)

	var snaps := HBoxContainer.new()
	snaps.position = Vector2(40, 1600)
	snaps.add_theme_constant_override("separation", 12)
	add_child(snaps)

	for step in [1.0, 0.5, 0.25]:
		var button := Button.new()
		button.text = "1/%d" % int(round(1.0 / step))
		button.custom_minimum_size = Vector2(120, 70)
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(func():
			snap = step
			_refresh_info())
		snaps.add_child(button)

	var actions := HBoxContainer.new()
	actions.position = Vector2(40, 1690)
	actions.add_theme_constant_override("separation", 12)
	add_child(actions)

	for entry in [
		["Замахи под щиты", _add_windup_for_shields],
		["Сохранить", _save],
		["Плейтест", _playtest],
		["Перечитать", load_chart],
	]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(230, 80)
		button.add_theme_font_size_override("font_size", 28)
		button.pressed.connect(entry[1])
		actions.add_child(button)

	_status = Label.new()
	_status.position = Vector2(40, 1790)
	_status.size = Vector2(1000, 110)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 24)
	add_child(_status)
