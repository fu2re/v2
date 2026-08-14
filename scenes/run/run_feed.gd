extends Node2D

## Лента полян. Свайп вверх — следующая поляна, как в ленте коротких видео.
##
## Никакой карты и выбора маршрута: только «дальше» или «домой». Главное
## решение игры — свайпнуть ещё раз или уйти с добычей — повторяется
## десятки раз за забег (GDD §3).

const SWIPE_THRESHOLD := 140.0
const BATTLE_SCENE := preload("res://scenes/battle/DanceBattle.tscn")

@export var guardian_id: String = "disco_sprout"

var _card: Control = null
var _headline: Label = null
var _subline: Label = null
var _hint: Label = null
var _depth_label: Label = null
var _groove_fill: ColorRect = null
var _home_button: Button = null

var _battle: Node2D = null
var _taming: CanvasLayer = null
var _drag_start := 0.0
var _dragging := false
var _busy := false
## Забег окончен, ждём тап для нового. Флаг, а не цикл с await:
## опрос в корутине пережил бы выгрузку сцены и остался бы висеть.
var _awaiting_restart := false


func _ready() -> void:
	_build_ui()

	_taming = preload("res://scenes/battle/TamingScreen.tscn").instantiate()
	add_child(_taming)
	_taming.finished.connect(_on_taming_finished)

	RunManager.groove_changed.connect(_on_groove_changed)
	RunManager.run_ended.connect(_on_run_ended)

	_start_run()


func _start_run() -> void:
	# Гуардиан по умолчанию доступен с самого начала: без стартового
	# существа в лес не выйти, а игрок ещё никого не приручил
	if not RunManager.start_run(guardian_id):
		return
	_on_groove_changed(RunManager.groove, RunManager.max_groove)
	_show_glade(RunManager.advance())


func _show_glade(glade: Glade) -> void:
	if glade == null:
		return
	_busy = false
	_depth_label.text = "Поляна %d" % glade.depth
	_headline.text = glade.headline()

	match glade.type:
		Glade.Type.BATTLE:
			var monster := Registry.monster(glade.monster_id)
			var wants := Registry.fruit(monster.favorite_fruit_id) if monster != null else null
			# Чего монстр хочет, видно ДО боя — игрок решает, стоит ли
			# останавливаться (GDD §6.2)
			_subline.text = "%s · %s\nЛюбит: %s" % [
				MonsterData.genre_name(monster.genre),
				MonsterData.rarity_name(monster.rarity),
				wants.display_name if wants != null else "?",
			]
			_headline.add_theme_color_override("font_color",
				MonsterData.rarity_color(monster.rarity))
			_hint.text = "Тапни, чтобы танцевать\nСвайп вверх — пройти мимо"
		Glade.Type.WILD_BUSH:
			_subline.text = "Здесь можно собрать семена"
			_headline.add_theme_color_override("font_color", Color("97C46A"))
			_hint.text = "Тапни, чтобы собрать"
		Glade.Type.CAMPFIRE:
			_subline.text = "Можно перевести дух\n+%d к Ритму" % RunManager.CAMPFIRE_RESTORE
			_headline.add_theme_color_override("font_color", Color("FF5C7A"))
			_hint.text = "Тапни, чтобы отдохнуть"
		_:
			_subline.text = "Здесь что-то есть"
			_headline.add_theme_color_override("font_color", Color("DCC7A4"))
			_hint.text = "Тапни, чтобы посмотреть"


func _input(event: InputEvent) -> void:
	if _busy or _battle != null or (_taming != null and _taming.visible):
		return

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _dragging:
			return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos_y: float = event.position.y
		if pressed:
			_drag_start = pos_y
			_dragging = true
		elif _dragging:
			_dragging = false
			var travel := pos_y - _drag_start
			if _awaiting_restart:
				if absf(travel) < 40.0:
					_awaiting_restart = false
					_return_to_farm()
				return
			if travel < -SWIPE_THRESHOLD:
				_next_glade()
			elif absf(travel) < 40.0:
				_resolve_glade()


## Забег кончился — возвращаемся на ферму. Именно там добыча превращается
## в новые посадки, и контур замыкается (GDD §7.3).
func _return_to_farm() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")


func _next_glade() -> void:
	_show_glade(RunManager.advance())


## Разрешить поляну: вступить в бой или собрать награду.
func _resolve_glade() -> void:
	var glade := RunManager.current_glade
	if glade == null:
		return
	_busy = true

	match glade.type:
		Glade.Type.BATTLE:
			_start_battle(glade)
		Glade.Type.WILD_BUSH:
			# Куст даёт и фрукты, и СЕМЕНА нового вида. Семена — единственный
			# способ завести новую культуру, и он замыкает контур лес→ферма
			RunManager.add_loot_fruit(glade.fruit_id, FruitData.Quality.PLAIN, 2)
			RunManager.add_loot_seed(glade.fruit_id, 1)
			RunManager.add_loot_seeds(glade.seeds_reward)
			var fruit := Registry.fruit(glade.fruit_id)
			var name := fruit.display_name if fruit != null else glade.fruit_id
			var known := FarmState.known_seeds.has(glade.fruit_id)
			_hint.text = "%s: 2 плода и семя!\nСвайп вверх — дальше" % name if known \
				else "Новый вид: %s!\nСемя пойдёт на грядку.\nСвайп вверх — дальше" % name
			_busy = false
		Glade.Type.CAMPFIRE:
			RunManager.rest_at_campfire()
			_hint.text = "Отдохнул.\nСвайп вверх — дальше"
			_busy = false
		_:
			RunManager.add_loot_seeds(glade.seeds_reward)
			_hint.text = "+%d семечек\nСвайп вверх — дальше" % glade.seeds_reward
			_busy = false


func _start_battle(glade: Glade) -> void:
	_card.visible = false
	_home_button.visible = false

	_battle = BATTLE_SCENE.instantiate()
	_battle.chart_id = "demo_disco"
	_battle.difficulty = "normal"
	_battle.monster_id = glade.monster_id
	_battle.guardian_id = RunManager.guardian_id
	_battle.starting_groove = RunManager.groove
	_battle.depth = glade.depth
	_battle.autostart = true
	_battle.battle_finished.connect(_on_battle_finished)
	add_child(_battle)


func _on_battle_finished(won: bool, state: BattleState) -> void:
	# Ритм сквозной: сколько осталось после боя, столько и уходит на следующую поляну
	RunManager.set_groove(state.groove)

	var monster := state.monster
	var perfect := state.is_perfect_run()

	if _battle != null:
		_battle.queue_free()
		_battle = null
	_card.visible = true
	_home_button.visible = true

	if RunManager.groove <= 0:
		RunManager.die()
		return

	if won:
		RunManager.add_loot_seeds(RunManager.current_glade.seeds_reward)
		_taming.show_for(monster, perfect)
	else:
		# Монстр устоял, но Ритм цел — забег продолжается
		_hint.text = "%s устоял.\nСвайп вверх — дальше" % monster.display_name
		_busy = false


func _on_taming_finished() -> void:
	_hint.text = "Свайп вверх — следующая поляна"
	_busy = false


func _on_groove_changed(current: int, maximum: int) -> void:
	if _groove_fill == null:
		return
	var ratio := clampf(float(current) / maxf(maximum, 1.0), 0.0, 1.0)
	_groove_fill.size.x = 900.0 * ratio


func _on_run_ended(died: bool, kept_fruits: int, kept_seeds: int) -> void:
	_card.visible = true
	_home_button.visible = false
	_depth_label.text = ""
	# Формулировка позитивная даже при поражении: не «ты проиграл»,
	# а «гуардиан устал» (GDD §8.4)
	_headline.text = "Гуардиан устал" if died else "Домой с добычей"
	_headline.add_theme_color_override("font_color", Color("DCC7A4"))
	_subline.text = "Принесли домой:\n%d фруктов, %d семечек" % [kept_fruits, kept_seeds]
	_hint.text = "Тапни, чтобы вернуться на ферму"
	_busy = true

	# Пауза, чтобы игрок успел прочитать итог и не ушёл с экрана
	# случайным тапом, оставшимся от боя
	await get_tree().create_timer(1.2).timeout
	_busy = false
	_awaiting_restart = true


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("24391F")
	add_child(bg)

	_card = Control.new()
	_card.size = Vector2(1080, 1920)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	_depth_label = _make_label(Vector2(60, 140), 44, Color("ADA99F"))
	_headline = _make_label(Vector2(60, 620), 76, Color("DCC7A4"))
	_subline = _make_label(Vector2(60, 800), 42, Color("ADA99F"))
	_hint = _make_label(Vector2(60, 1420), 38, Color("1ED8FF"))

	var track := ColorRect.new()
	track.position = Vector2(90, 1740)
	track.size = Vector2(900, 34)
	track.color = Color(0, 0, 0, 0.45)
	add_child(track)

	_groove_fill = ColorRect.new()
	_groove_fill.position = track.position
	_groove_fill.size = Vector2(900, 34)
	_groove_fill.color = Color("1ED8FF")
	add_child(_groove_fill)

	_home_button = Button.new()
	_home_button.text = "Домой"
	_home_button.position = Vector2(760, 120)
	_home_button.size = Vector2(240, 100)
	_home_button.add_theme_font_size_override("font_size", 40)
	_home_button.pressed.connect(func(): RunManager.go_home())
	add_child(_home_button)


func _make_label(pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(960, 220)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_card.add_child(label)
	return label
