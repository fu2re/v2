extends Node2D

## Первые 60 секунд игры.
##
## Обучение — это ТА ЖЕ сцена боя с дополнительным слоем-тренером, а не
## отдельный экран. Иначе игрок учился бы на одном, а играл в другое,
## и любое расхождение между ними всплывало бы у него на экране.
##
## Ни одного слова (GDD §15.5). Объясняет пульсирующее кольцо и призрачный
## палец, а не подпись.

## Длина связки в уроке: три обычных бита и звезда в конце —
## ровно тот же рисунок, что в настоящем бою.
const SERIES_BEATS := 3
const LEAD_IN_BEATS := 4.0
## Настрой занижен, чтобы урок заведомо кончился победой: первый опыт
## игрока обязан быть успешным.
const LESSON_VIBE := 40

var _battle: Node2D = null


func _ready() -> void:
	_battle = preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	_battle.autostart = false
	_battle.monster_id = "disco_sprout"
	_battle.guardian_id = "disco_sprout"
	_battle.battle_finished.connect(_on_finished)
	add_child(_battle)

	# Тренер — просто ещё один слой поверх боя
	_battle.enable_coach()

	# Оверлей замеров в обучении не нужен: он для отладки, а не для ребёнка
	var overlay := _battle.get_node_or_null("TimingOverlay")
	if overlay != null:
		overlay.queue_free()

	var chart := _build_lesson_chart()
	if chart == null:
		_go_to_farm()
		return
	_battle.begin(chart, LESSON_VIBE)


## Урок: спокойный трек фермы, связки «три бита и звезда» до конца мелодии.
##
## Строится в коде, а не берётся из charts/, потому что это фиксированный
## сценарий обучения — разнообразие здесь только помешает.
func _build_lesson_chart() -> ChartData:
	var source := ChartLoader.load_by_id("farm_folk", "easy")
	if source == null:
		push_error("Не найден трек обучения farm_folk")
		return null

	var chart := ChartData.new()
	chart.id = "lesson"
	chart.genre = source.genre
	chart.bpm = source.bpm
	chart.offset = source.offset
	chart.duration = source.duration
	chart.beats_per_bar = source.beats_per_bar
	chart.audio_path = source.audio_path

	# Ноты идут ДО КОНЦА трека. Раньше урок обрывался на шестнадцатой ноте,
	# и вторая половина мелодии играла в пустоту — ребёнок решал, что сломалось.
	var beats := PackedFloat32Array()
	var types := PackedByteArray()
	var beat := LEAD_IN_BEATS
	var in_series := 0
	var last := chart.total_beats() - 1.0

	while beat <= last:
		in_series += 1
		# Каждая четвёртая нота — звезда: связка из трёх и удар.
		# Без атакующих нот урок вообще нельзя было выиграть
		if in_series > SERIES_BEATS:
			types.append(ChartData.NoteType.ATTACK)
			in_series = 0
		else:
			types.append(ChartData.NoteType.BEAT)
		beats.append(beat)
		beat += 1.0

	chart.note_beats = beats
	chart.note_types = types
	return chart


func _on_finished(_won: bool, _state: BattleState) -> void:
	OnboardingState.mark_done()
	await get_tree().create_timer(1.4).timeout
	_go_to_farm()


func _go_to_farm() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")
