extends CanvasLayer

## Главный артефакт Фазы 0.
##
## Вопрос фазы — «работает ли тайминг» — должен получить ответ числом,
## а не ощущением. Оверлей показывает дрейф аудиочасов и статистику попаданий:
## если среднее отклонение уползает к концу трека, ядро сломано, и это видно.

const SAMPLE_LIMIT := 200

@export var battle_path: NodePath

var _label: Label = null
var _battle: Node = null

var _deltas: PackedFloat32Array = PackedFloat32Array()
var _last_grade := ""
var _last_delta := 0.0
var _clock_jitter_max := 0.0


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(24, 24)
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_color", Color("FFFFFF"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 8)
	add_child(_label)

	if not battle_path.is_empty():
		_battle = get_node_or_null(battle_path)
	if _battle == null:
		_battle = get_parent()
	if _battle != null and _battle.has_signal("note_judged"):
		_battle.note_judged.connect(_on_note_judged)


func _process(_delta: float) -> void:
	if not Conductor.is_playing:
		_label.text = "Conductor остановлен"
		return

	_clock_jitter_max = maxf(_clock_jitter_max, absf(Conductor.clock_drift))

	_label.text = "\n".join([
		"FPS            %d" % Engine.get_frames_per_second(),
		"song_position  %7.3f сек" % Conductor.song_position,
		"song_beat      %7.3f" % Conductor.song_beat,
		"дрейф часов    %7.2f мс (макс)" % (_clock_jitter_max * 1000.0),
		"задержка вывода %6.1f мс" % (AudioServer.get_output_latency() * 1000.0),
		"калибровка     %+7.1f мс" % (AudioBus.calibration_offset * 1000.0),
		"",
		"последняя      %s  %+.1f мс" % [_last_grade, _last_delta * 1000.0],
		"среднее        %+7.1f мс" % (_mean() * 1000.0),
		"СКО            %7.1f мс" % (_stddev() * 1000.0),
		"попаданий      %d" % _deltas.size(),
		"",
		_counts_line(),
		"комбо          %d (макс %d)" % [_battle.combo, _battle.max_combo] if _battle != null else "",
	])


func _on_note_judged(grade: int, delta: float) -> void:
	_last_grade = Judge.grade_name(grade)
	_last_delta = delta
	# Промахи в статистику точности не идут: они не измеряют тайминг,
	# а лишь фиксируют, что ноту не тронули
	if grade == Judge.Grade.MISS:
		return
	_deltas.append(delta)
	if _deltas.size() > SAMPLE_LIMIT:
		_deltas.remove_at(0)


func _mean() -> float:
	if _deltas.is_empty():
		return 0.0
	var sum := 0.0
	for d in _deltas:
		sum += d
	return sum / _deltas.size()


func _stddev() -> float:
	if _deltas.size() < 2:
		return 0.0
	var m := _mean()
	var acc := 0.0
	for d in _deltas:
		acc += (d - m) * (d - m)
	return sqrt(acc / (_deltas.size() - 1))


func _counts_line() -> String:
	if _battle == null:
		return ""
	var c: Dictionary = _battle.grade_counts
	return "P %d   G %d   E/L %d   MISS %d" % [
		c[Judge.Grade.PERFECT], c[Judge.Grade.GOOD],
		c[Judge.Grade.EARLY_LATE], c[Judge.Grade.MISS],
	]
