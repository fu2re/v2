extends Node2D

## Первая встреча в лесу (GDD §15.5).
##
## Фраза на фоне леса, потом бой — и так до победы. Проигрыш не наказывается
## и не пропускается: та же фраза, тот же монстр, бой заново. Выйти из интро
## можно только победой, потому что победа и есть первый друг.
##
## Текстом здесь становится ТОЛЬКО повествовательная рамка — две фразы.
## Всё, что учит механике, по-прежнему показывается кольцом и пальцем:
## ребёнок, который не читает бегло, видит монстра и одну кнопку «дальше».

## Настрой первого монстра занижен: первый опыт обязан кончиться победой.
const LESSON_VIBE := 40
const SERIES_BEATS := 3
const LEAD_IN_BEATS := 4.0

## Обе фразы — через локализацию, а не литералами по коду (GDD §15.6).
const MET_TEXT := "Однажды гуляя в лесу\nвы встретили\n%s"
const FRIEND_TEXT := "Теперь %s\nваш защитник"

@onready var _phrase: Label = $Phrase
@onready var _monster_art: Sprite2D = $MonsterArt
@onready var _continue: Button = $ContinueButton
@onready var _forest: Sprite2D = $Forest

## Кого встретили. Выбирается ОДИН раз на весь цикл: при поражении игрок
## возвращается к тому же монстру, а не знакомится заново — иначе история
## рассыпается, и фраза «однажды вы встретили» звучит второй раз про другого.
var _species: MonsterData = null
var _battle: Node2D = null


func _ready() -> void:
	_species = _pick_starter()
	if _species == null:
		# Без монстров игру не начать; уходим во двор, чтобы не запереть игрока
		push_error("Нет ни одного монстра для интро")
		_go_home()
		return

	# Лес первой встречи тоже разный — но выбирается ОДИН раз на всё интро:
	# при поражении показывается та же фраза и тот же монстр, и менять
	# под ними декорацию значило бы сказать, что игрок ушёл в другое место
	UIUtil.set_screen_background(_forest, ForestScenery.next_path())

	_continue.pressed.connect(_start_battle)
	_show_meeting()


## Первый монстр — случайный, но ВСЕГДА обычного грейда: первый бой обязан
## быть посильным, а первый друг — не легендарным с порога.
func _pick_starter() -> MonsterData:
	var pool := Registry.all_monsters()
	if pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return pool[rng.randi_range(0, pool.size() - 1)]


func _show_meeting() -> void:
	_phrase.text = MET_TEXT % _species.display_name
	_monster_art.texture = _species.sprite_for_grade(MonsterData.Rarity.COMMON)
	_monster_art.visible = true
	_continue.text = "Дальше"
	_continue.visible = true
	_phrase.visible = true
	_forest.visible = true


func _start_battle() -> void:
	_phrase.visible = false
	_continue.visible = false
	_monster_art.visible = false
	# Лес ОСТАЁТСЯ: первый бой игрок танцует там же, где встретил монстра.
	# Пока фон гасился, обучение шло на пустой заливке — единственный бой
	# в игре без леса за спиной, и выглядел он как незагрузившийся экран

	_battle = preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	_battle.autostart = false
	_battle.monster_id = _species.id
	_battle.monster_grade = MonsterData.Rarity.COMMON
	# Гуардиана нет: первый бой игрок танцует один
	_battle.guardian_key = ""
	_battle.battle_finished.connect(_on_battle_finished)
	add_child(_battle)

	# Тренер — тот же слой поверх настоящего боя, а не отдельный урок
	_battle.enable_coach()

	# Оверлей замеров в обучении не нужен: он для отладки, а не для ребёнка
	var overlay := _battle.get_node_or_null("TimingOverlay")
	if overlay != null:
		overlay.queue_free()

	var chart := _build_lesson_chart()
	if chart == null:
		_go_home()
		return
	_battle.begin(chart, LESSON_VIBE)


## Урок: спокойный трек, связки «три бита и звезда» до конца мелодии.
##
## Чарт строится в коде, а не берётся из charts/: это фиксированный сценарий
## обучения, и разнообразие здесь только помешает.
func _build_lesson_chart() -> ChartData:
	var source := ChartLoader.load_by_id("farm_folk", "easy")
	if source == null:
		return null

	var chart := ChartData.new()
	chart.id = "lesson"
	chart.genre = source.genre
	chart.difficulty = "common"
	chart.bpm = source.bpm
	chart.offset = source.offset
	chart.duration = source.duration
	chart.beats_per_bar = source.beats_per_bar
	chart.audio_path = source.audio_path

	var beats := PackedFloat32Array()
	var types := PackedByteArray()
	var in_series := 0
	var beat := LEAD_IN_BEATS
	while beat < source.total_beats() - 1.0:
		in_series += 1
		beats.append(beat)
		# Каждая четвёртая — звезда: связка «три бита и удар» показывает
		# правило серии раньше, чем его получится объяснить словами
		if in_series > SERIES_BEATS:
			types.append(ChartData.NoteType.ATTACK)
			in_series = 0
		else:
			types.append(ChartData.NoteType.BEAT)
		beat += 1.0

	chart.note_beats = beats
	chart.note_types = types
	return chart


func _on_battle_finished(won: bool, _state: BattleState) -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null

	Jukebox.play_cue("victory" if won else "defeat")

	if won:
		_celebrate()
		return

	# Поражение ничего не отнимает и ничего не засчитывает: та же фраза,
	# тот же монстр, бой заново. Обучение считается пройденным ТОЛЬКО
	# после победы — иначе игрок ушёл бы в игру, не научившись
	await get_tree().create_timer(1.2).timeout
	_show_meeting()


func _celebrate() -> void:
	# Монстр присоединяется сразу, минуя шкалу дружбы: это единственное
	# исключение из §6.1, и оно нужно, чтобы игре было с кем начаться
	var friend := GameState.tame(_species.id, MonsterData.Rarity.COMMON)
	GameState.set_guardian(friend.key())
	OnboardingState.mark_done()
	SaveManager.save_game()

	_phrase.text = FRIEND_TEXT % _species.display_name
	_monster_art.texture = friend.sprite()
	_monster_art.visible = true
	_phrase.visible = true
	_forest.visible = true
	_continue.text = "Домой"
	_continue.visible = true

	# Кнопка теперь ведёт домой, а не в бой
	if _continue.pressed.is_connected(_start_battle):
		_continue.pressed.disconnect(_start_battle)
	_continue.pressed.connect(_go_home)


## Дом — это двор усадьбы (§7.4), а не сразу огород.
func _go_home() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)
