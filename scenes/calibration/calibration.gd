extends Node2D

## Калибровка задержки. Обязательна по GDD §10.4: разброс аудиозадержки
## на Android огромен, и без поправки игра кажется сломанной у половины игроков.
##
## Игрок тапает под метроном, мы берём МЕДИАНУ отклонений — не среднее.
## Один случайный промах смещает среднее и испортил бы калибровку целиком.

signal calibrated(offset: float)

const TAPS_NEEDED := 8
const BPM := 120.0
const WARMUP_BEATS := 4

var _player: AudioStreamPlayer = null
var _label: Label = null
var _deltas: Array[float] = []
var _start_usec: int = 0
var _running := false
var _last_click_beat := -1


func _ready() -> void:
	_build_ui()
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	_player.stream = _make_click()
	add_child(_player)
	_start()


func _start() -> void:
	_deltas.clear()
	_last_click_beat = -1
	_start_usec = Time.get_ticks_usec()
	_running = true


func _sec_per_beat() -> float:
	return 60.0 / BPM


func _elapsed() -> float:
	return float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0


func _process(_delta: float) -> void:
	if not _running:
		return

	var beat_index := int(floor(_elapsed() / _sec_per_beat()))
	if beat_index > _last_click_beat:
		_last_click_beat = beat_index
		_player.play()

	var left := TAPS_NEEDED - _deltas.size()
	if _elapsed() < WARMUP_BEATS * _sec_per_beat():
		_label.text = "Слушай ритм...\n\nПотом тапай в такт"
	else:
		_label.text = "Тапай в такт\n\nОсталось: %d" % left


func _input(event: InputEvent) -> void:
	if not _running or not event.is_action_pressed("tap"):
		return
	if _elapsed() < WARMUP_BEATS * _sec_per_beat():
		return

	var t := _elapsed()
	var spb := _sec_per_beat()
	# Отклонение от ближайшей доли, со знаком: плюс — игрок опоздал
	var delta := t - roundf(t / spb) * spb
	_deltas.append(delta)

	if _deltas.size() >= TAPS_NEEDED:
		_finish()


func _finish() -> void:
	_running = false
	_deltas.sort()
	var mid := _deltas.size() / 2
	var median := _deltas[mid] if _deltas.size() % 2 == 1 \
		else (_deltas[mid - 1] + _deltas[mid]) * 0.5

	# Игрок опаздывал -> он слышит звук позже, чем думает игра.
	# Компенсируем, сдвигая часы назад ровно на медиану.
	AudioBus.set_calibration(median)
	_label.text = "Готово\n\nПоправка: %+.0f мс\n\nТапни, чтобы повторить" % (median * 1000.0)
	calibrated.emit(median)
	await get_tree().create_timer(1.0).timeout
	set_process_input(true)
	_running = false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("24391F")
	add_child(bg)

	_label = Label.new()
	_label.size = Vector2(1080, 1920)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 64)
	_label.add_theme_color_override("font_color", Color("DCC7A4"))
	add_child(_label)


## Короткий щелчок синтезируем в коде: отдельный ассет ради калибровки
## не нужен, а так гарантирован мгновенный старт без задержки декодирования.
func _make_click() -> AudioStreamWAV:
	var rate := 44100
	var length := int(rate * 0.03)
	var data := PackedByteArray()
	data.resize(length * 2)
	for i in length:
		var t := float(i) / rate
		var env: float = exp(-t * 180.0)
		var sample := int(sin(TAU * 1600.0 * t) * env * 24000.0)
		data.encode_s16(i * 2, sample)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
