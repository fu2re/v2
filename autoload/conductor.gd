extends Node

## Единственный источник музыкального времени в игре.
##
## ЖЕЛЕЗНОЕ ПРАВИЛО: никакой игровой код не считает ритм через delta или Timer.
## Накопление delta уплывает от аудиопотока и привязывает геймплей к FPS —
## именно так ломается большинство ритм-игр.
##
## Время берётся у аудиодрайвера:
##   get_playback_position()      ступенчато, обновляется на границах микс-буфера
##   + get_time_since_last_mix()  сглаживает внутри буфера
##   - get_output_latency()       компенсирует задержку вывода
##   - calibration_offset         персональная поправка игрока

signal beat(index: int)
signal finished()

var chart: ChartData = null
var is_playing: bool = false

## Позиция в треке в секундах, по аудиочасам.
var song_position: float = 0.0
## Позиция в долях. Дробная — ноты живут между долями.
var song_beat: float = 0.0

## Насколько шаг аудиочасов за кадр разошёлся с реальным временем кадра.
## Это и есть измеряемый ответ Фазы 0: если значение уползает, ядро сломано.
var clock_drift: float = 0.0

## Первые кадры после play() в замер не идут: аудиодрайвер ещё раскручивается,
## и один стартовый скачок травил бы максимум за весь трек.
const WARMUP_FRAMES := 8

var _player: AudioStreamPlayer = null
var _last_beat: int = -1
var _last_position: float = 0.0
var _frames_since_play: int = 0


func _ready() -> void:
	# Conductor обязан обновиться раньше всех потребителей: если бой прочитает
	# song_position до пересчёта, ноты отстанут ровно на кадр
	process_priority = -100
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)


func play(new_chart: ChartData, from_beat: float = 0.0) -> void:
	if new_chart == null:
		push_error("Conductor.play вызван с null-чартом")
		return

	var stream := new_chart.audio()
	if stream == null:
		push_error("У чарта %s не загрузилось аудио: %s" % [new_chart.id, new_chart.audio_path])
		return

	if chart != null and chart != new_chart:
		chart.release_audio()

	chart = new_chart
	_player.stream = stream
	_last_beat = int(floor(from_beat)) - 1

	var from_time := chart.beat_to_time(from_beat)
	song_position = from_time
	song_beat = from_beat
	_last_position = from_time
	clock_drift = 0.0
	_frames_since_play = 0

	_player.play(from_time)
	is_playing = true


func stop() -> void:
	is_playing = false
	_player.stop()


## Аудиопоток надо отпустить явно: иначе AudioStreamPlayer и кеш в ChartData
## держат Ogg-ресурс до самого выхода, и движок ругается на утечку.
func _exit_tree() -> void:
	stop()
	_player.stream = null
	chart = null


func _process(delta: float) -> void:
	if not is_playing:
		return

	if not _player.playing:
		is_playing = false
		finished.emit()
		return

	song_position = now()
	song_beat = chart.time_to_beat(song_position)

	# Аудиочасы должны идти вровень с реальным временем. Расхождение —
	# это и есть та величина, ради измерения которой существует Фаза 0.
	_frames_since_play += 1
	clock_drift = 0.0 if _frames_since_play <= WARMUP_FRAMES \
		else (song_position - _last_position) - delta
	_last_position = song_position

	_emit_grid_signals()


## Свежее время прямо сейчас, без ожидания следующего кадра.
##
## Оценивать тап по кэшированному song_position нельзя: _input вызывается ДО
## _process, поэтому кэш отстаёт на кадр — до 16 мс при 60 FPS, треть окна
## Perfect. Ввод обязан спрашивать время здесь.
func now() -> float:
	if not is_playing:
		return song_position
	var t := _player.get_playback_position()
	t += AudioServer.get_time_since_last_mix()
	t -= AudioServer.get_output_latency()
	t -= AudioBus.calibration_offset
	return t


func _emit_grid_signals() -> void:
	var current_beat := int(floor(song_beat))
	while _last_beat < current_beat:
		_last_beat += 1
		beat.emit(_last_beat)
