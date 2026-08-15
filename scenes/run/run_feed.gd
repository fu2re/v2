extends Node2D

## Лента полян. Свайп вверх — следующая поляна, как в ленте коротких видео.
##
## Никакой карты и выбора маршрута: только «дальше» или «домой». Главное
## решение игры — свайпнуть ещё раз или уйти с добычей — повторяется
## десятки раз за забег (GDD §3).

## Пороги жестов — В ДОЛЯХ ВЫСОТЫ ЭКРАНА, а не в пикселях.
##
## Событие ввода приходит в координатах ОКНА, а не холста 1080×1920.
## При stretch-режиме окно почти всегда меньше, поэтому свайп в 200 точек
## холста доходил сюда как 100 точек экрана — ниже порога в 140. Жест
## не считался ни свайпом, ни тапом, и игрок застревал на поляне;
## а когда доходил до порога тапа — заново входил в тот же бой.
const SWIPE_FRACTION := 0.07
const TAP_FRACTION := 0.02

## Подсказка называет КНОПКУ, а жест лишь дублирует её: жест зависит
## от порогов и состояния и уже подводил игрока, кнопка — нет.
const HINT_NEXT := "Кнопка «Дальше» или свайп вверх"
const BATTLE_SCENE := preload("res://scenes/battle/DanceBattle.tscn")

## Кого берём в лес. Пусто — берём выбранного в коллекции.
@export var guardian_id: String = ""

## Раскладка живёт в RunFeed.tscn и правится в инспекторе (GDD §13.2.1).
## Скрипт связывает узлы с логикой и больше ничего о них не знает.
@onready var _card: Control = $Card
@onready var _headline: Label = $Card/Headline
@onready var _subline: Label = $Card/Subline
@onready var _hint: Label = $Card/Hint
@onready var _glade_art: Sprite2D = $Card/GladeArt
@onready var _depth_label: Label = $Card/DepthLabel
@onready var _health_fill: ColorRect = $Card/HealthFill
@onready var _home_button: Button = $HomeButton
## Кнопка ухода на ферму после забега. Живёт отдельно от жестов:
## это единственный выход, который нельзя заблокировать состоянием.
@onready var _finish_button: Button = $FinishButton
## Кнопки действия и перехода. Дублируют жесты, потому что жест
## зависит от состояния и порогов, а кнопка — нет.
@onready var _action_button: Button = $ActionButton
@onready var _next_button: Button = $NextButton
@onready var _panel_bg: ColorRect = $PanelBackdrop
@onready var _panel_box: VBoxContainer = $PanelScroll/PanelBox

var _battle: Node2D = null
var _taming: CanvasLayer = null
var _drag_start := 0.0
var _dragging := false
var _busy := false
## Забег окончен, ждём тап для нового. Флаг, а не цикл с await:
## опрос в корутине пережил бы выгрузку сцены и остался бы висеть.
var _awaiting_restart := false
## Пройдена ли текущая поляна. Пока бой не окончен, свайп заблокирован.
var _glade_cleared := false
## Бой окончен, итог показан, ждём свайпа. Сцена боя ещё на экране.
var _awaiting_result_swipe := false
var _pending_result := ""


func _ready() -> void:
	_home_button.pressed.connect(func(): RunManager.go_home())
	_finish_button.pressed.connect(_return_to_farm)
	_action_button.pressed.connect(_confirm)
	_next_button.pressed.connect(_advance)
	# Прокрутка живёт и гаснет вместе с панелью: пустой ScrollContainer
	# во весь экран молча съедал бы клики по тому, что под ним
	var scroll: ScrollContainer = $PanelScroll
	_panel_box.visibility_changed.connect(func(): scroll.visible = _panel_box.visible)

	_taming = preload("res://scenes/battle/TamingScreen.tscn").instantiate()
	add_child(_taming)
	_taming.finished.connect(_on_taming_finished)

	RunManager.health_changed.connect(_on_health_changed)
	RunManager.run_ended.connect(_on_run_ended)

	_start_run()


func _start_run() -> void:
	# Гуардиана выбирают в коллекции; экспорт нужен только для отладки сцены
	var chosen := guardian_id if not guardian_id.is_empty() else GameState.guardian_id()
	if not RunManager.start_run(chosen):
		return
	_on_health_changed(RunManager.health, RunManager.max_health)
	_show_glade(RunManager.advance())


func _show_glade(glade: Glade) -> void:
	if glade == null:
		return
	_busy = false
	_finish_button.visible = false
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
			# Мимо монстра не пройти — это не пропускаемая поляна
			_hint.text = "Кнопка «Танцевать» или тап по экрану"
			_glade_art.texture = monster.sprite() if monster != null else null
		Glade.Type.WILD_BUSH:
			_subline.text = "Здесь можно собрать семена"
			_headline.add_theme_color_override("font_color", Color("97C46A"))
			_hint.text = "Кнопка «Собрать» или тап по экрану"
			var bush := Registry.fruit(glade.fruit_id)
			_glade_art.texture = bush.sprite() if bush != null else null
		Glade.Type.CAMPFIRE:
			_subline.text = "Можно перевести дух\n+%d к здоровью" % RunManager.CAMPFIRE_RESTORE
			_headline.add_theme_color_override("font_color", Color("FF5C7A"))
			_hint.text = "Кнопка «Отдохнуть» или тап по экрану"
			_glade_art.texture = null
		Glade.Type.MERCHANT:
			_headline.add_theme_color_override("font_color", Color("BA9A6D"))
			_hint.text = "Кнопка «Товар» или тап по экрану"
			_glade_art.texture = null
		_:
			_subline.text = "Здесь что-то есть"
			_headline.add_theme_color_override("font_color", Color("DCC7A4"))
			_hint.text = "Кнопка «Посмотреть» или тап по экрану"
			_glade_art.texture = null

	_refresh_buttons()


## Свайп и тап по поляне ловим в _unhandled_input, а НЕ в _input.
##
## _input срабатывает раньше интерфейса, поэтому тап по кнопке «Домой»
## одновременно разрешал поляну: забег закрывался и тут же начинался бой.
## _unhandled_input вызывается только если событие не забрал ни один Control.
func _unhandled_input(event: InputEvent) -> void:
	if _taming != null and _taming.visible:
		return
	# Пока показан итог боя, ввод обслуживает только уход с него
	if _battle != null and not _awaiting_result_swipe:
		return
	if _busy and not _awaiting_result_swipe:
		return

	# Клавиатура: пробел разрешает поляну, стрелка вверх листает дальше.
	# Игрок жал пробел и не получал ничего — на десктопе это основной ввод
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_confirm()
			KEY_UP, KEY_W, KEY_PAGEUP:
				_advance()
		return

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _dragging:
			return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		# Колесо мыши приходит СЮДА ЖЕ, но нажатие и отпускание у него
		# в одной точке. Жест читался как тап и заново запускал тот же бой —
		# ровно то, о чём сообщал игрок. Колесо вверх это явное «дальше»
		if event is InputEventMouseButton:
			var button := (event as InputEventMouseButton).button_index
			if button == MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_advance()
				return
			if button != MOUSE_BUTTON_LEFT:
				return

		var pressed: bool = event.pressed
		var pos_y: float = event.position.y
		if pressed:
			_drag_start = pos_y
			_dragging = true
		elif _dragging:
			_dragging = false
			var travel := pos_y - _drag_start
			# Пороги считаем от ВЫСОТЫ ОКНА: событие приходит в его
			# координатах, а не в координатах холста 1080×1920
			var height := maxf(get_viewport_rect().size.y, 1.0)
			var swipe_up := travel < -height * SWIPE_FRACTION
			var tapped := absf(travel) < height * TAP_FRACTION

			# Итог боя убирается любым осмысленным жестом: и свайпом,
			# и тапом. Застрять на экране результата нельзя
			if _awaiting_result_swipe:
				if swipe_up or tapped:
					_dismiss_battle()
				return
			if _awaiting_restart:
				if tapped:
					_awaiting_restart = false
					_return_to_farm()
				return
			if swipe_up:
				_try_next_glade()
			elif tapped:
				_resolve_glade()


## Забег кончился — возвращаемся на ферму. Именно там добыча превращается
## в новые посадки, и контур замыкается (GDD §7.3).
func _return_to_farm() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")


## Поляну с монстром пропустить нельзя.
##
## Встретил — танцуй. Иначе главное решение забега («идти дальше или уйти
## с добычей») подменялось бы бесплатным листанием мимо всего опасного,
## и лента переставала быть выбором.
func _try_next_glade() -> void:
	if _blocks_swipe():
		_hint.text = "%s не отпускает.\nТапни, чтобы танцевать" \
			% Registry.monster(RunManager.current_glade.monster_id).display_name
		_shake_card()
		return
	_next_glade()


## Держит ли текущая поляна игрока на месте.
func _blocks_swipe() -> bool:
	var glade := RunManager.current_glade
	return glade != null and glade.type == Glade.Type.BATTLE and not _glade_cleared


func _shake_card() -> void:
	var tween := create_tween()
	tween.tween_property(_card, "position:x", 22.0, 0.06)
	tween.tween_property(_card, "position:x", -22.0, 0.06)
	tween.tween_property(_card, "position:x", 0.0, 0.06)


func _next_glade() -> void:
	_glade_cleared = false
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
			RunManager.add_loot_silver(glade.silver_reward)
			var fruit := Registry.fruit(glade.fruit_id)
			var name := fruit.display_name if fruit != null else glade.fruit_id
			var known := FarmState.known_seeds.has(glade.fruit_id)
			_hint.text = "%s: 2 плода и семя!\n%s" % [name, HINT_NEXT] if known \
				else "Новый вид: %s!\nСемя пойдёт на грядку.\n%s" % [name, HINT_NEXT]
			_busy = false
		Glade.Type.MERCHANT:
			_open_merchant(glade)
		Glade.Type.CAMPFIRE:
			RunManager.rest_at_campfire()
			_open_campfire()
		_:
			RunManager.add_loot_silver(glade.silver_reward)
			_hint.text = "+%d серебра\n%s" % [glade.silver_reward, HINT_NEXT]
			_busy = false


## Торговец. Продаёт снаряжение за серебро, найденные в этом же забеге —
## значит уйти домой пораньше и потратить всё здесь это настоящий выбор.
func _open_merchant(glade: Glade) -> void:
	var stock := _merchant_stock(glade.depth)
	_open_panel("Бродячий торговец")

	if stock.is_empty():
		_add_panel_label("Сегодня всё раскуплено.")
	for item: GearData in stock:
		var affordable := RunManager.run_silver >= item.price
		var button := _add_panel_button("%s — %d серебра\n%s" % [
			item.display_name, item.price, item.effect_text(),
		], _buy_gear.bind(item))
		button.disabled = not affordable

	_add_panel_label("Серебра в кармане: %d" % RunManager.run_silver)
	_add_panel_button("Идти дальше", _close_panel)


## Ассортимент детерминирован глубиной: игрок, увидевший товар и решивший
## сначала добить бой, обязан застать его на месте.
func _merchant_stock(depth: int) -> Array:
	var pool := Registry.all_gear()
	if pool.is_empty():
		return []
	var out: Array = []
	for i in 3:
		out.append(pool[(depth * 7 + i * 3) % pool.size()])
	return out


func _buy_gear(item: GearData) -> void:
	if RunManager.run_silver < item.price:
		return
	RunManager.add_loot_silver(-item.price)
	GameState.add_gear(item.id)
	_open_merchant(RunManager.current_glade)


## Костёр — единственная точка смены гуардиана внутри забега (GDD §15.1).
func _open_campfire() -> void:
	_open_panel("Костёр")
	_add_panel_label("Здоровье восстановлено: %d / %d" % [RunManager.health, RunManager.max_health])

	var friends := GameState.tamed
	if friends.size() <= 1:
		_add_panel_label("Сменить пока некого.")
	for monster_id in friends:
		if monster_id == RunManager.guardian_id:
			continue
		var monster := Registry.monster(monster_id)
		if monster == null:
			continue
		_add_panel_button("Позвать: %s (%s)" % [
			monster.display_name, MonsterData.genre_name(monster.genre),
		], _swap_guardian.bind(monster_id))

	_add_panel_button("Идти дальше", _close_panel)


func _swap_guardian(monster_id: String) -> void:
	GameState.set_guardian(monster_id)
	RunManager.swap_guardian(monster_id)
	_open_campfire()


func _open_panel(title: String) -> void:
	_busy = true
	_panel_box.visible = true
	_panel_bg.visible = true
	UIUtil.clear_children(_panel_box)
	_add_panel_label(title, 52)


func _close_panel() -> void:
	_panel_box.visible = false
	_panel_bg.visible = false
	_hint.text = HINT_NEXT
	_busy = false


func _add_panel_label(text: String, size: int = 34) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("DCC7A4"))
	_panel_box.add_child(label)


func _add_panel_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 32)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	_panel_box.add_child(button)
	return button


func _start_battle(glade: Glade) -> void:
	_card.visible = false
	_home_button.visible = false
	_action_button.visible = false
	_next_button.visible = false

	_battle = BATTLE_SCENE.instantiate()
	_battle.chart_id = "demo_disco"
	_battle.difficulty = "normal"
	_battle.monster_id = glade.monster_id
	_battle.guardian_id = RunManager.guardian_id
	_battle.starting_health = RunManager.health
	_battle.starting_shield = RunManager.shield
	_battle.depth = glade.depth
	_battle.autostart = true
	_battle.battle_finished.connect(_on_battle_finished)
	add_child(_battle)


func _on_battle_finished(won: bool, state: BattleState) -> void:
	# Здоровье сквозное: сколько осталось после боя, столько и уходит на следующую поляну
	_glade_cleared = true
	RunManager.set_health(state.health)
	RunManager.set_shield(state.shield)

	var monster := state.monster
	var perfect := state.is_perfect_run()

	# Опыт начисляется за ЛЮБОЙ бой, даже проигранный: ты всё равно изучил
	# повадки. Иначе неудача откатывала бы прогресс, а это ровно то,
	# чего игра для детей делать не должна
	GameState.add_battle_experience(monster.id)

	if RunManager.health <= 0:
		_dismiss_battle()
		RunManager.die()
		return

	if won:
		RunManager.add_loot_silver(RunManager.current_glade.silver_reward)
		var prize := RunManager.roll_victory_gear(monster)
		if not prize.is_empty():
			var item := Registry.gear(prize)
			_pending_result = "Сундук: %s" % item.display_name if item != null else ""
		# Экран угощения поверх боя: монстр остаётся лежать на виду,
		# и связь «победил → можно подружиться» читается сразу
		_taming.show_for(monster, perfect)
	else:
		# Монстр не побеждён — он убегает, и приручить его нельзя.
		# Дружба не начисляется вовсе: подружиться можно только с тем,
		# кто дослушал танец до конца (GDD §6.1)
		_pending_result = "%s убежал.\nПодружиться можно только с тем,\nкто дослушал до конца." \
			% monster.display_name
		_awaiting_result_swipe = true
		_busy = false
		# Подсказку меняем СРАЗУ, а не после закрытия боя: иначе под сценой
		# боя остаётся приглашение «тапни, чтобы танцевать», и стоит игроку
		# закрыть итог — карточка зовёт в бой, который уже проигран
		_hint.text = HINT_NEXT
		_refresh_buttons()


## Убрать сцену боя и вернуть карточку поляны.
##
## Вызывается по свайпу, а не сразу после боя: итог обязан оставаться
## на экране, пока игрок сам не решит идти дальше.
func _dismiss_battle() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	_awaiting_result_swipe = false
	_card.visible = true
	_home_button.visible = true
	_refresh_buttons()
	if not _pending_result.is_empty():
		_hint.text = "%s\n\n%s" % [_pending_result, HINT_NEXT]
		_pending_result = ""


func _on_taming_finished() -> void:
	_pending_result = ""
	_dismiss_battle()
	_busy = false


func _on_health_changed(current: int, maximum: int) -> void:
	if _health_fill == null:
		return
	var ratio := clampf(float(current) / maxf(maximum, 1.0), 0.0, 1.0)
	_health_fill.size.x = 900.0 * ratio


func _on_run_ended(died: bool, kept_fruits: int, kept_seeds: int) -> void:
	_card.visible = true
	_home_button.visible = false
	_depth_label.text = ""
	# Формулировка позитивная даже при поражении: не «ты проиграл»,
	# а «гуардиан устал» (GDD §8.4)
	_headline.text = "Гуардиан устал" if died else "Домой с добычей"
	_headline.add_theme_color_override("font_color", Color("DCC7A4"))
	_subline.text = "Принесли домой:\n%d фруктов, %d серебра" % [kept_fruits, kept_seeds]
	_hint.text = "Забег окончен"

	# Кнопка, а не жест.
	#
	# Игрок сообщил о зависании на этом экране. Точную причину поймать
	# не удалось, но она заведомо лежит в состоянии жестов: свайп зависит
	# от _dragging, _busy и _battle разом, и любая рассинхронизация между
	# ними оставляет игрока запертым. Кнопка не зависит ни от чего из этого —
	# она либо на экране, либо нет. Тупик закрыт целым классом, а не точечно.
	_action_button.visible = false
	_next_button.visible = false
	_finish_button.visible = true
	_finish_button.disabled = true
	_busy = true

	# Пауза, чтобы игрок успел прочитать итог и не ушёл с экрана
	# случайным тапом, оставшимся от боя
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(_finish_button):
		return
	_finish_button.disabled = false
	_busy = false
	_awaiting_restart = true


## Единая точка «разрешить текущий экран».
##
## Сюда сходятся тап, пробел и кнопка. Раньше каждый ввод шёл своей веткой,
## и часть из них молча ничего не делала.
func _confirm() -> void:
	if _awaiting_result_swipe:
		_dismiss_battle()
		return
	if _awaiting_restart:
		_awaiting_restart = false
		_return_to_farm()
		return
	_resolve_glade()


## Единая точка «идти дальше».
func _advance() -> void:
	if _awaiting_result_swipe:
		_dismiss_battle()
		return
	if _awaiting_restart:
		return
	_try_next_glade()


## Обновить подписи кнопок под текущее состояние.
##
## Кнопка обязана говорить, что она сделает: «Танцевать» на бою,
## «Собрать» на кусте. Одинаковая подпись на все случаи — это та же
## непонятность, что и голый жест.
func _refresh_buttons() -> void:
	var glade := RunManager.current_glade
	if glade == null:
		_action_button.visible = false
		_next_button.visible = false
		return

	if _awaiting_result_swipe:
		_action_button.text = "Дальше"
		_action_button.visible = true
		_next_button.visible = false
		return

	match glade.type:
		Glade.Type.BATTLE:
			_action_button.text = "Танцевать"
		Glade.Type.WILD_BUSH:
			_action_button.text = "Собрать"
		Glade.Type.CAMPFIRE:
			_action_button.text = "Отдохнуть"
		Glade.Type.MERCHANT:
			_action_button.text = "Товар"
		_:
			_action_button.text = "Посмотреть"

	_action_button.visible = not _glade_cleared or glade.type != Glade.Type.BATTLE
	# Кнопка «дальше» гаснет там, где поляну нельзя пропустить,
	# и это видно сразу, а не после безрезультатного свайпа
	_next_button.visible = true
	_next_button.disabled = _blocks_swipe()
