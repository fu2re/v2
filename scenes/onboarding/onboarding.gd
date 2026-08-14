extends Node2D

## Первые 60 секунд игры.
##
## Учит ритму НАСТОЯЩИМ боем, а не отдельной песочницей: всё, что игрок
## освоит здесь, останется правдой в игре. Отличия только в щадящих
## параметрах — редкие ноты, спокойный трек, отсутствие щитов.
##
## Ни одного слова (GDD §15.5). Объясняет пульсирующее кольцо и призрачный
## палец, а не подпись на экране.

const NOTE_COUNT := 16
const LEAD_IN_BEATS := 4.0

var _battle: Node2D = null
var _coach: CanvasLayer = null


func _ready() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("24391F")
	bg.z_index = -20
	add_child(bg)

	_battle = preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	_battle.autostart = false
	_battle.monster_id = "disco_sprout"
	_battle.guardian_id = "disco_sprout"
	_battle.note_judged.connect(_on_note_judged)
	_battle.battle_finished.connect(_on_finished)
	add_child(_battle)

	_coach = preload("res://scenes/onboarding/CoachOverlay.tscn").instantiate()
	_coach.judge_y = _battle.JUDGE_Y
	_coach.lane_x = _battle.LANE_X
	add_child(_coach)

	# Оверлей замеров в обучении не нужен: он для отладки, а не для ребёнка
	var overlay := _battle.get_node_or_null("TimingOverlay")
	if overlay != null:
		overlay.queue_free()

	_start()


func _start() -> void:
	var chart := _build_lesson_chart()
	if chart == null:
		_go_to_farm()
		return

	# Настрой занижен так, чтобы урок закончился победой к концу фразы:
	# первый опыт игрока обязан завершиться успехом
	_battle.begin(chart, 40)


## Урок: одна нота на долю, спокойный трек фермы, никаких щитов.
##
## Строится в коде, а не берётся из charts/, потому что это фиксированный
## сценарий обучения. Разнообразие здесь только помешает.
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

	var beats := PackedFloat32Array()
	var types := PackedByteArray()
	for i in NOTE_COUNT:
		beats.append(LEAD_IN_BEATS + i)
		types.append(ChartData.NoteType.BEAT)
	chart.note_beats = beats
	chart.note_types = types
	return chart


func _on_note_judged(grade: int, _delta: float) -> void:
	if grade != Judge.Grade.MISS:
		_coach.note_hit()


func _on_finished(_won: bool, _state: BattleState) -> void:
	_coach.finish()
	OnboardingState.mark_done()
	await get_tree().create_timer(1.2).timeout
	_go_to_farm()


func _go_to_farm() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")
