class_name RunFeed
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
## Сколько ждать после боя, прежде чем показать итог.
##
## Анимация падения монстра длится 0.45 с плюс кадр на крестики. Пауза
## чуть длиннее: победа обязана успеть случиться на экране до того,
## как её накроет панель с текстом.
const VICTORY_PAUSE := 0.9

## Сколько держится каждый шаг показа: приз, прибавка уровня.
## Достаточно, чтобы прочитать, и мало, чтобы не заскучать на десятой победе.
const PRIZE_STEP := 0.65
## За сколько полоска опыта добегает до края.
const XP_FILL_SECONDS := 0.5

## Геометрия модальной панели. Верх постоянный, низ считается по содержимому
## (см. `_fit_panel`), поэтому здесь только поля и границы.
const PANEL_TOP := 300.0
const PANEL_SIDE := 60.0
const PANEL_PAD := 40.0
const PANEL_MAX_BOTTOM := 1640.0
## Ширина полоски опыта. Уже панели намеренно: на всю ширину она упиралась
## в рамку и читалась как часть рамки, а не как шкала.
const XP_BAR_WIDTH := 760.0

const BATTLE_SCENE := preload("res://scenes/battle/DanceBattle.tscn")

## Ключ экземпляра, которого берём в лес. Пусто — берём выбранного в коллекции.
@export var guardian_key: String = ""

## Раскладка живёт в RunFeed.tscn и правится в инспекторе (GDD §13.2.1).
## Скрипт связывает узлы с логикой и больше ничего о них не знает.
@onready var _card: Control = $Card
## Фон поляны: у каждого типа свой, и меняется он вместе с поляной.
@onready var _scenery: Sprite2D = $Scenery
## Витрина награды: что игрок теряет, пролистывая (GDD §8.1.2).
@onready var _tame_banner: Label = $Card/TameBanner
@onready var _friendship_track: ColorRect = $Card/FriendshipTrack
@onready var _friendship_fill: ColorRect = $Card/FriendshipFill
@onready var _friendship_label: Label = $Card/FriendshipLabel
@onready var _reward_label: Label = $Card/RewardLabel
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
## Кнопка «дальше» ПОСЛЕ боя. Отдельная от обычной и на слое поверх боя:
## та стоит на 1394 — ровно по линии удара и танцорам, — и поверх живой
## сцены боя читалась как приклеенная к герою.
@onready var _result_button: Button = $PanelLayer/ResultButton
@onready var _panel_bg: ColorRect = $PanelLayer/PanelBackdrop
@onready var _panel_frame: Panel = $PanelLayer/PanelFrame
@onready var _panel_box: VBoxContainer = $PanelLayer/PanelScroll/PanelBox

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

## Отдала ли поляна свою добычу.
##
## Без этого флага куст, костёр и бабка срабатывали НА КАЖДЫЙ ТАП: можно
## было трясти один и тот же куст сто раз подряд и лечиться у одного костра
## до полного здоровья. Поляна даёт своё ровно один раз — иначе лента
## перестаёт быть чередой решений и превращается в кнопку «ещё».
var _glade_used := false
## Бой окончен, итог показан, ждём свайпа. Сцена боя ещё на экране.
var _awaiting_result_swipe := false
var _pending_result := ""

## Кого угощать после экрана победы.
##
## Приручение больше не выезжает поверх боя мгновенно: сначала игрок видит
## падающего монстра и свою добычу, и только по нажатию открывается угощение.
var _pending_taming: MonsterInstance = null
var _pending_perfect := false


func _ready() -> void:
	_home_button.pressed.connect(func(): RunManager.go_home())
	_finish_button.pressed.connect(_return_to_farm)
	_action_button.pressed.connect(_confirm)
	_next_button.pressed.connect(_advance)
	_result_button.pressed.connect(_advance)
	# Прокрутка живёт и гаснет вместе с панелью: пустой ScrollContainer
	# во весь экран молча съедал бы клики по тому, что под ним
	var scroll: ScrollContainer = $PanelLayer/PanelScroll
	_panel_box.visibility_changed.connect(func(): scroll.visible = _panel_box.visible)
	# Рамка подгоняется по сигналу, а не только вызовом после вставки узла.
	# `get_combined_minimum_size()` отдаёт КЭШ, который пересчитывается лишь
	# в следующем проходе раскладки: вызов сразу после add_child читал размер
	# ПРОШЛОЙ панели, и рамка оставалась во весь экран под тремя строками
	_panel_box.minimum_size_changed.connect(_fit_panel)

	_taming = preload("res://scenes/battle/TamingScreen.tscn").instantiate()
	add_child(_taming)
	_taming.finished.connect(_on_taming_finished)

	RunManager.health_changed.connect(_on_health_changed)
	RunManager.run_ended.connect(_on_run_ended)

	_start_run()


func _start_run() -> void:
	# Гуардиана выбирают в коллекции; экспорт нужен только для отладки сцены
	var chosen := guardian_key if not guardian_key.is_empty() else GameState.guardian_key()
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
				MonsterData.rarity_name(glade.grade),
				wants.display_name if wants != null else "?",
			]
			_headline.add_theme_color_override("font_color",
				MonsterData.rarity_color(glade.grade))
			# Подсказка честно говорит, есть ли выбор: превзойдённого можно
			# пролистать, нового — нет, и это видно до попытки
			if GameState.is_tamed_at_least(glade.monster_id, glade.grade):
				_hint.text = "Кнопка «Танцевать» или свайп мимо"
			else:
				_hint.text = "Кнопка «Танцевать» или тап по экрану"
			# Спрайт грейда: легендарный обязан отличаться от обычного
			# ещё на карточке, до боя
			_glade_art.texture = monster.sprite_for_grade(glade.grade) if monster != null else null
			# Встреча сама по себе открывает клетку коллекции наполовину:
			# силуэт светлеет, имя вида появляется. Полный скин по-прежнему
			# за победой (GDD §7.5) — иначе коллекция собиралась бы свайпами
			# мимо, без единого танца
			GameState.mark_met(glade.monster_id, glade.grade)
			_show_stakes(glade)
		Glade.Type.WILD_BUSH:
			_subline.text = "Здесь можно собрать семена"
			_headline.add_theme_color_override("font_color", Color("97C46A"))
			_hint.text = "Кнопка «Собрать» или тап по экрану"
			var bush := Registry.fruit(glade.fruit_id)
			_glade_art.texture = bush.sprite() if bush != null else null
		Glade.Type.CAMPFIRE:
			_subline.text = "Можно перевести дух\nи подкрепиться фруктами"
			_headline.add_theme_color_override("font_color", Color("FF5C7A"))
			_hint.text = "Кнопка «Отдохнуть» или тап по экрану"
			_glade_art.texture = null
		Glade.Type.ENCOUNTER:
			_headline.add_theme_color_override("font_color", Color("BA9A6D"))
			_glade_art.texture = null
			match glade.encounter:
				Glade.Encounter.MERCHANT:
					_subline.text = "Три товара за серебро"
					_hint.text = "Кнопка «Товар» или тап по экрану"
				Glade.Encounter.LOOT_BUSH:
					_subline.text = "Куст шуршит — в нём что-то есть"
					_hint.text = "Кнопка «Потрясти» или тап по экрану"
				Glade.Encounter.GRANNY:
					_subline.text = "Бабушка чего-то просит"
					_hint.text = "Кнопка «Подойти» или тап по экрану"
				_:
					_subline.text = "Здесь что-то есть"
					_hint.text = "Кнопка «Посмотреть» или тап по экрану"
		_:
			_subline.text = "Здесь что-то есть"
			_headline.add_theme_color_override("font_color", Color("DCC7A4"))
			_hint.text = "Кнопка «Посмотреть» или тап по экрану"
			_glade_art.texture = null

	if glade.type != Glade.Type.BATTLE:
		_hide_stakes()
	_show_scenery(glade)
	_refresh_buttons()


## Фон поляны. Лента должна ощущаться прогулкой по разным местам,
## а не сменой текста на одном и том же зелёном.
##
## Фоны делятся надвое, и делятся по смыслу. У костра и встречи фон САМ
## является содержанием: на нём горит огонь и стоит навес торговца, и подменить
## его безымянным лесом — потерять то, ради чего игрок остановился. У боя
## и дикого куста фон — просто место, а что там происходит, говорят заголовок,
## спрайт на карточке и мелодия. Эти два и вращаются по двадцати картинкам:
## именно они попадаются чаще всего, и именно на них лес приедался.
##
## Фон приглушается сильнее прочих экранов — поверх него лежат и текст,
## и спрайт монстра, и полоска дружбы (GDD §11.1.1).
func _show_scenery(glade: Glade) -> void:
	var art := ""
	match glade.type:
		Glade.Type.CAMPFIRE:
			art = "res://art/glade/glade_campfire.png"
		Glade.Type.ENCOUNTER:
			art = "res://art/glade/glade_encounter.png"
		_:
			art = ForestScenery.next_path()

	# Запасной путь — старый фон по типу: если каталог леса пуст,
	# поляна остаётся с картинкой, а не с чёрным экраном
	if art.is_empty():
		art = "res://art/glade/glade_wild_bush.png" \
			if glade.type == Glade.Type.WILD_BUSH \
			else "res://art/glade/glade_battle.png"

	if not UIUtil.set_screen_background(_scenery, art, 0.45):
		_scenery.visible = false

	# Слух узнаёт поляну раньше глаз: мелодия меняется вместе с картинкой,
	# и по ней слышно, драка впереди или костёр. Вариант каждый раз новый
	# из пяти — лента бесконечная, и один и тот же мотив на каждом кусте
	# приелся бы быстрее всего остального в игре
	if not Jukebox.play_glade(Glade.TYPE_KEYS.get(glade.type, "battle")):
		# У нового типа поляны своего пула ещё нет — лес не должен молчать
		Jukebox.play_screen("run_feed")


## Что на кону: витрина награды за бой (GDD §8.1.2).
##
## Раз превзойдённого монстра можно пролистать, карточка обязана показать,
## что игрок теряет, пролистывая. Иначе пропуск — не решение, а случайность.
func _show_stakes(glade: Glade) -> void:
	var value := GameState.get_friendship(glade.monster_id, glade.grade)
	var threshold := GameState.friendship_threshold(glade.grade)
	var after_win := mini(value + GameState.FRIENDSHIP_WIN, threshold)

	var already := GameState.has_instance(glade.monster_id, glade.grade)

	# У того, кто УЖЕ в коллекции, шкалы дружбы нет вовсе.
	#
	# Она показывала «0 / 100» при надписи «уже друг» — противоречие само
	# по себе, а за ним тянулось и настоящее: после боя открывалось угощение,
	# фрукты списывались, шкала росла, и всё это не значило ничего.
	# Дружиться заново не с кем; с приручённым идут не за дружбой,
	# а за опытом — и кормят его в коллекции (§7.5).
	# Шкалы нет и там, где приручать пока нельзя: дружба туда не копится,
	# и полоска показывала бы прогресс, которого не происходит
	var open_now := GameState.can_tame(glade.monster_id, glade.grade)
	var show_bar := not already and open_now
	_friendship_track.visible = show_bar
	_friendship_fill.visible = show_bar
	if show_bar:
		var full_width := _friendship_track.size.x
		_friendship_fill.size.x = full_width \
			* clampf(float(value) / float(threshold), 0.0, 1.0)

	# Пометка «можно подружиться» затмевает всё остальное: это единственная
	# ситуация, в которой пропуск стоит игроку по-настоящему дорого
	var will_tame := not already and open_now and after_win >= threshold
	_tame_banner.visible = will_tame
	if will_tame:
		_tame_banner.text = "Можно подружиться!"

	if already:
		_friendship_label.text = "Уже твой друг · бой ради опыта и добычи"
	elif not open_now:
		# Через ступень приручать нельзя, и молчать об этом нельзя тоже:
		# без объяснения непонятно, почему шкалы нет вовсе
		var step := GameState.missing_step(glade.monster_id, glade.grade)
		# Аргумент РОВНО один: лишние GDScript не отбрасывает, а молча
		# оставляет шаблон как есть, и игрок читал «Сначала подружись: %s»
		_friendship_label.text = "Подружиться пока нельзя.\nСначала подружись: %s" \
			% MonsterData.rarity_name(step)
	else:
		_friendship_label.text = "Дружба %d/%d  (+%d за победу)" % [
			value, threshold, GameState.FRIENDSHIP_WIN,
		]

	# Мелким шрифтом — остальное, что даёт победа
	var chest := Balance.victory_chest_odds(glade.grade)
	var expensive := int(round(chest[2]))
	_reward_label.visible = true
	_reward_label.text = "Победа: +%d серебра · сундук (дорогая вещь %d%%) · опыт" % [
		glade.silver_reward, expensive,
	]


func _hide_stakes() -> void:
	_tame_banner.visible = false
	_friendship_track.visible = false
	_friendship_fill.visible = false
	_friendship_label.text = ""
	_reward_label.text = ""


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
	get_tree().change_scene_to_file(OnboardingState.LOBBY)


## Мимо можно пройти только там, что уже превзойдено.
##
## Иначе главное решение забега («идти дальше или уйти с добычей»)
## подменялось бы бесплатным листанием мимо всего опасного, и лента
## переставала быть выбором.
func _try_next_glade() -> void:
	if _blocks_swipe():
		var monster := Registry.monster(RunManager.current_glade.monster_id)
		_hint.text = "%s не отпускает.\nТапни, чтобы танцевать" \
			% (monster.display_name if monster != null else "Монстр")
		_shake_card()
		return
	_next_glade()


## Держит ли текущая поляна игрока на месте.
##
## Держит всё, что для игрока НОВО: незнакомый вид или знакомый вид в грейде
## выше приручённого. Превзойдённого монстра можно свайпнуть мимо (GDD §8.1) —
## иначе десятый бой с давно приручённым Ростиком превращает ленту
## в обязаловку, а не в риск.
func _blocks_swipe() -> bool:
	var glade := RunManager.current_glade
	if glade == null or glade.type != Glade.Type.BATTLE or _glade_cleared:
		return false
	return not GameState.is_tamed_at_least(glade.monster_id, glade.grade)


func _shake_card() -> void:
	var tween := create_tween()
	tween.tween_property(_card, "position:x", 22.0, 0.06)
	tween.tween_property(_card, "position:x", -22.0, 0.06)
	tween.tween_property(_card, "position:x", 0.0, 0.06)


func _next_glade() -> void:
	_glade_cleared = false
	_glade_used = false
	_show_glade(RunManager.advance())


## Разрешить поляну: вступить в бой или собрать награду.
func _resolve_glade() -> void:
	var glade := RunManager.current_glade
	if glade == null:
		return
	# Поляна отдаёт своё ОДИН раз. Повторный тап по уже собранному кусту
	# или прогретому костру не должен давать ничего
	if _glade_used:
		return
	_busy = true

	match glade.type:
		Glade.Type.BATTLE:
			_start_battle(glade)
		Glade.Type.WILD_BUSH:
			# Куст даёт и фрукты, и СЕМЕНА нового вида. Семена — единственный
			# способ завести новую культуру, и он замыкает контур лес→ферма
			_glade_used = true
			RunManager.add_loot_fruit(glade.fruit_id, FruitData.Quality.PLAIN, 2)
			RunManager.add_loot_seed(glade.fruit_id, 1)
			RunManager.add_loot_silver(glade.silver_reward)
			var fruit := Registry.fruit(glade.fruit_id)
			var name := fruit.display_name if fruit != null else glade.fruit_id
			var known := FarmState.known_seeds.has(glade.fruit_id)
			_hint.text = "%s: 2 плода и семя!\n%s" % [name, HINT_NEXT] if known \
				else "Новый вид: %s!\nСемя пойдёт на грядку.\n%s" % [name, HINT_NEXT]
			_busy = false
			_refresh_buttons()
		Glade.Type.ENCOUNTER:
			match glade.encounter:
				Glade.Encounter.MERCHANT:
					# Торговец — исключение: прилавок можно открывать снова,
					# он ничего не даёт даром, всё покупается за серебро
					_open_merchant(glade)
				Glade.Encounter.LOOT_BUSH:
					_glade_used = true
					_open_loot_bush(glade)
				Glade.Encounter.GRANNY:
					_glade_used = true
					_open_granny(glade)
				_:
					_glade_used = true
					RunManager.add_loot_silver(glade.silver_reward)
					_hint.text = "+%d серебра\n%s" % [glade.silver_reward, HINT_NEXT]
					_busy = false
					_refresh_buttons()
		Glade.Type.CAMPFIRE:
			# Костёр не лечит сам: у него ЕДЯТ фрукты, и флаг «поляна отдала
			# своё» здесь не ставится — панель можно открыть снова, пока
			# не ушёл дальше. Съеденное при этом не возвращается
			_open_campfire()
		_:
			_glade_used = true
			RunManager.add_loot_silver(glade.silver_reward)
			_hint.text = "+%d серебра\n%s" % [glade.silver_reward, HINT_NEXT]
			_busy = false
			_refresh_buttons()


## Куст с гостинцами: потряси — и что-нибудь упадёт.
##
## Лут обычный: зелье, семя, горсть серебра, изредка — сундук со снаряжением.
## Пустым куст не бывает никогда: «потряс и ничего» — это обещание,
## которое игра не сдержала.
func _open_loot_bush(glade: Glade) -> void:
	var prize := RunManager.shake_bush(glade.depth)
	_open_panel("Куст с гостинцами")
	_add_panel_label(prize)
	_add_panel_button("Спасибо, куст!", _close_panel)


## Бабушка у тропинки: просит серебра.
##
## Просьба НИКОГДА не больше, чем есть в кармане: предложение, которое нельзя
## принять, — это издёвка, а не выбор. Отказ ничем не наказывается: щедрость
## награждается, жадность просто остаётся при своём.
func _open_granny(glade: Glade) -> void:
	var asked := RunManager.granny_request()
	_open_panel("Бабушка у тропинки")

	if asked <= 0:
		_add_panel_label("Бабушка машет рукой: «Иди, милый, у самого пусто».")
		_add_panel_button("Идти дальше", _close_panel)
		return

	_add_panel_label("«Не найдётся ли %d серебра, милый?»\nВ кармане: %d"
		% [asked, RunManager.run_silver])
	_add_panel_button("Дать %d серебра" % asked, _give_to_granny.bind(asked))
	_add_panel_button("Извиниться и пойти дальше", _refuse_granny)


func _give_to_granny(amount: int) -> void:
	var gift := RunManager.pay_granny(amount)
	_open_panel("Бабушка у тропинки")
	_add_panel_label("«Спасибо, милый! Возьми-ка вот это».\n\n%s" % gift)
	_add_panel_button("Идти дальше", _close_panel)


func _refuse_granny() -> void:
	# Ни потери, ни укора: отказ — законный выбор, а не проступок
	_open_panel("Бабушка у тропинки")
	_add_panel_label("«Ничего-ничего. Доброго пути!»")
	_add_panel_button("Идти дальше", _close_panel)


## Торговец. Продаёт снаряжение за серебро, найденные в этом же забеге —
## значит уйти домой пораньше и потратить всё здесь это настоящий выбор.
func _open_merchant(glade: Glade) -> void:
	var stock := _merchant_stock(glade.depth)
	_open_panel("Бродячий торговец")

	if stock.is_empty():
		_add_panel_label("Сегодня всё раскуплено.")
	for item: Resource in stock:
		# Типы указаны явно: у Resource поля читаются как Variant,
		# и вывод типа через := уронил бы весь скрипт (CLAUDE.md)
		var price: int = item.price
		var title: String = item.display_name
		var effect: String = item.effect_text()
		var button := _add_panel_button("%s — %d серебра\n%s" % [title, price, effect],
			_buy_item.bind(item))
		button.disabled = RunManager.run_silver < price

	_add_panel_label("Серебра в кармане: %d" % RunManager.run_silver)
	_add_panel_button("Идти дальше", _close_panel)


## Ассортимент детерминирован глубиной: игрок, увидевший товар и решивший
## сначала добить бой, обязан застать его на месте.
##
## Сам набор собирает `MerchantStock` — тот же класс, что держит витрину
## в усадьбе. Две реализации одной торговли разъехались бы на первой же
## правке цен.
func _merchant_stock(depth: int) -> Array:
	return MerchantStock.forest_stock(depth)


func _buy_item(item: Resource) -> void:
	var price: int = item.price
	var id: String = item.id
	if RunManager.run_silver < price:
		return
	RunManager.add_loot_silver(-price)
	GameState.add_gear(id)
	_open_merchant(RunManager.current_glade)


## Костёр — единственная точка смены гуардиана внутри забега (GDD §15.1).
func _open_campfire() -> void:
	_open_panel("Костёр")
	_add_panel_label("Здоровье: %d / %d" % [RunManager.health, RunManager.max_health])

	# Лечение стоит угощения — единственное настоящее решение внутри забега
	# (GDD §8.2.3). Зелий в игре нет: тот же фрукт либо съедается здесь ради
	# здоровья и бафа, либо приберегается для приручения. Раньше костёр лечил
	# даром, и выбирать было не из чего
	var eaten := false
	for fruit in Registry.all_fruits():
		for quality in [FruitData.Quality.PERFECT, FruitData.Quality.JUICY,
				FruitData.Quality.PLAIN]:
			var count := GameState.fruit_count(fruit.id, quality)
			if count <= 0:
				continue
			eaten = true
			var button := _add_panel_button("Съесть: %s ×%d\n+%d здоровья%s" % [
				fruit.display_name, count, fruit.heal(), _buff_text(fruit),
			], _eat_at_campfire.bind(fruit.id, quality))
			UIUtil.decorate_row(button, fruit)

	if not eaten:
		_add_panel_label("Есть нечего — фрукты растут на грядках.", 30)

	var friends := GameState.all_instances()
	if friends.size() <= 1:
		_add_panel_label("Сменить пока некого.")
	for friend: MonsterInstance in friends:
		if friend.key() == RunManager.guardian_key:
			continue
		# Грейд в подписи обязателен: два экземпляра одного вида иначе дают
		# две неотличимые кнопки, и выбор превращается в угадайку
		var suffix := ""
		if friend.grade > MonsterData.Rarity.COMMON:
			suffix = ", %s" % friend.grade_name()
		_add_panel_button("Позвать: %s (%s%s) ур.%d" % [
			friend.display_name(), MonsterData.genre_name(friend.genre()),
			suffix, friend.level,
		], _swap_guardian.bind(friend.key()))

	_add_panel_button("Идти дальше", _close_panel)


func _swap_guardian(instance_key: String) -> void:
	GameState.set_guardian(instance_key)
	RunManager.swap_guardian(instance_key)
	_open_campfire()


func _open_panel(title: String) -> void:
	_busy = true
	_panel_box.visible = true
	_panel_bg.visible = true
	_panel_frame.visible = true

	# Кнопки поляны лежат в дереве ПОСЛЕ подложки, поэтому рисуются поверх
	# неё: на живом прогоне «Отдохнуть» и «Дальше ↑» торчали сквозь панель
	# встречи. Прятать их приходится явно — подложка перекрывает только то,
	# что стоит раньше неё
	_action_button.visible = false
	_next_button.visible = false
	_home_button.visible = false

	UIUtil.clear_children(_panel_box)
	_add_panel_label(title, 52)


func _close_panel() -> void:
	_panel_box.visible = false
	_panel_bg.visible = false
	_panel_frame.visible = false
	_hint.text = HINT_NEXT
	_busy = false
	# Кнопки поляны возвращаются в том состоянии, которое положено ЭТОЙ поляне,
	# а не в том, в каком были до панели
	_home_button.visible = true
	_refresh_buttons()


## Рамка панели по содержимому, а не по фиксированной высоте.
##
## Раньше рамка была ростом 1180 всегда, и под коротким итогом висело
## полэкрана пустоты — карточка выглядела недогруженной, будто что-то
## не отрисовалось. Растёт вниз от постоянного верха: содержимое победы
## добавляется по шагам, и рамка, скачущая вверх-вниз на каждом призе,
## читалась бы как дёрганье.
func _fit_panel() -> void:
	var content := _panel_box.get_combined_minimum_size().y
	var bottom := minf(PANEL_TOP + content + PANEL_PAD * 2.0, PANEL_MAX_BOTTOM)
	_panel_frame.position = Vector2(PANEL_SIDE, PANEL_TOP)
	_panel_frame.size = Vector2(1080.0 - PANEL_SIDE * 2.0, bottom - PANEL_TOP)

	var scroll: ScrollContainer = $PanelLayer/PanelScroll
	var inner := 1080.0 - (PANEL_SIDE + PANEL_PAD) * 2.0
	scroll.position = Vector2(PANEL_SIDE + PANEL_PAD, PANEL_TOP + PANEL_PAD)
	scroll.size = Vector2(inner, maxf(bottom - PANEL_TOP - PANEL_PAD * 2.0, 1.0))
	# Ширину содержимого задаём отсюда же: разойдись она с прокруткой хоть
	# на пиксель — и панель поедет вбок горизонтальной полосой
	_panel_box.custom_minimum_size.x = inner


func _add_panel_label(text: String, size: int = 34) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# По центру: `Label` по умолчанию прижимает текст влево, и панель победы
	# читалась как список у левого края вместо карточки итога
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("DCC7A4"))
	_panel_box.add_child(label)
	_fit_panel()


func _add_panel_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 120)
	button.add_theme_font_size_override("font_size", 32)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(callback)
	_panel_box.add_child(button)
	_fit_panel()
	return button


func _start_battle(glade: Glade) -> void:
	_card.visible = false
	_home_button.visible = false
	_action_button.visible = false
	_next_button.visible = false

	# Мелодия поляны замолкает: в бою играет чарт, и две дорожки разом
	# превратились бы в кашу — а под одну из них ещё и попадать в такт
	Jukebox.stop()

	_battle = BATTLE_SCENE.instantiate()
	# Трек не задаём: бой сам подберёт его по стихии, мотиву и грейду
	# встреченного монстра (GDD §10.1.1)
	_battle.chart_id = ""
	_battle.monster_id = glade.monster_id
	_battle.monster_grade = glade.grade
	_battle.guardian_key = RunManager.guardian_key
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

	# Исход слышен раньше, чем прочитан: джингл звучит сразу по окончании боя,
	# ещё до экрана с итогами
	Jukebox.play_cue("victory" if won else "defeat")

	# Опыт начисляется за ЛЮБОЙ бой, даже проигранный: ты всё равно изучил
	# повадки. Иначе неудача откатывала бы прогресс, а это ровно то,
	# чего игра для детей делать не должна
	GameState.add_battle_experience(monster.species_id)

	# Победа открывает клетку коллекции — навсегда и независимо от того,
	# удалось ли приручить (GDD §7.5)
	if won:
		GameState.mark_defeated(monster.species_id, monster.grade)

	if RunManager.health <= 0:
		_dismiss_battle()
		RunManager.die()
		return

	# Снимок защитника ДО награды: экран победы показывает, как опыт вырос,
	# а для этого нужно знать, откуда он рос. Считать «после минус прибавка»
	# нельзя — на переходе уровня шкала обнуляется, и разность врёт
	var before := _guardian_snapshot()

	# Опыт — тому, кто дрался, и НЕ ТОЛЬКО за победу (GDD §6.5). За убежавшего
	# монстра меньше, но не ноль: иначе новичок, которому пока нечем добить,
	# застревает навсегда — бой обязателен, а гуардиан от него не растёт
	var levels := RunManager.reward_guardian_xp(monster.grade, perfect, won)
	var after := _guardian_snapshot()

	if won:
		var silver: int = RunManager.current_glade.silver_reward
		RunManager.add_loot_silver(silver)

		# Призы копятся СПИСКОМ, а показываются по одному (GDD §8.1.3).
		# Каждый — с картинкой: строка «Сундук: Кожаный пояс» требует чтения,
		# а пояс на экране узнаётся сразу
		var prizes: Array[Dictionary] = [
			{"text": "+%d серебра" % silver, "item": null,
				"icon": "res://art/currency/coin_silver.png"},
		]

		var prize := RunManager.roll_victory_gear(monster.grade)
		if not prize.is_empty():
			var item := Registry.gear(prize)
			if item != null:
				prizes.append({"text": item.display_name, "item": item})

		# Кого угощать — запоминаем: приручение откроется по нажатию игрока.
		#
		# Того, кто УЖЕ в коллекции, угощать незачем: дружба у него набрана,
		# приручать нечего, и экран угощения только съедал бы фрукты впустую.
		# Такой бой идёт за опытом и добычей, и они уже начислены выше
		#
		# То же и с тем, у кого закрыта ступень ниже: дружба ему сейчас
		# не копится вовсе, и фрукты ушли бы в пустоту
		var can_befriend := not GameState.has_instance(monster.species_id, monster.grade) \
			and GameState.can_tame(monster.species_id, monster.grade)
		_pending_taming = monster if can_befriend else null
		_pending_perfect = perfect

		# Панель ждёт, пока монстр упадёт. Без паузы итог выскакивал в тот же
		# кадр, что и последняя нота, и анимация падения доигрывала ЗА ним:
		# игрок читал текст, а сзади что-то шевелилось. Пауза чуть длиннее
		# самой анимации — момент победы должен успеть случиться
		var shown_glade := RunManager.current_glade
		await get_tree().create_timer(VICTORY_PAUSE).timeout
		# За время паузы игрок мог уйти домой или свайпнуть дальше. Сторожим
		# ПОЛЯНУ, а не сцену боя: боя может не быть вовсе — итог показывают
		# и обучение, и тесты, вызывая этот путь напрямую
		if not is_inside_tree() or RunManager.current_glade != shown_glade:
			return
		await _play_victory(monster, prizes, before, after, levels)
	else:
		# Монстр не побеждён — он убегает, и приручить его нельзя.
		# Дружба не начисляется вовсе: подружиться можно только с тем,
		# кто дослушал танец до конца (GDD §6.1).
		#
		# Но танец не пропал: опыт гуардиану уже начислен выше, и это
		# говорится игроку прямо здесь — иначе поражение выглядит как
		# потерянное время
		_pending_result = "%s убежал, но танец не пропал.\nЗащитник стал опытнее." \
			% monster.display_name()
		if levels > 0 and not after.is_empty():
			_pending_result = "%s\n%s подрос до уровня %d!" % [
				_pending_result, after["name"], after["level"],
			]
		_awaiting_result_swipe = true
		_busy = false
		# Подсказку меняем СРАЗУ, а не после закрытия боя: иначе под сценой
		# боя остаётся приглашение «тапни, чтобы танцевать», и стоит игроку
		# закрыть итог — карточка зовёт в бой, который уже проигран
		_hint.text = HINT_NEXT
		_refresh_buttons()


## Экран победы: что произошло и что досталось.
##
## Держится поверх боя, но НЕ закрывает его: монстр внизу продолжает падать,
## и «Наплясался!» видно. Смысл именно в паузе — раньше угощение выезжало
## мгновенно, и ни анимации, ни добычи игрок не успевал заметить.
##
## Панель собирается теми же `_open_panel`/`_add_panel_*`, что и встречи:
## один способ показывать модальные окна на всю ленту.
## Закрыть итог боя, когда угощать некого. Панель гасим напрямую, как
## и в `_open_taming`: под нами всё ещё сцена боя, и кнопки поляны там
## не нужны — карточка вернётся сама, когда бой закроется.
func _close_victory() -> void:
	_panel_box.visible = false
	_panel_bg.visible = false
	_panel_frame.visible = false
	_awaiting_result_swipe = true
	_busy = false
	_refresh_buttons()


## Перейти от итога боя к угощению.
##
## Панель гасим напрямую, а не через `_close_panel`: тот возвращает кнопки
## поляны, а под нами всё ещё сцена боя — карточки там нет, и кнопки
## «Танцевать» поверх лежащего монстра выглядели бы приглашением
## подраться ещё раз. Карточка вернётся сама, когда бой закроется.
func _open_taming() -> void:
	_panel_box.visible = false
	_panel_bg.visible = false
	_panel_frame.visible = false

	if _pending_taming == null:
		return
	_taming.show_for(_pending_taming, _pending_perfect)
	_pending_taming = null


## Поляна отдана: монстра здесь больше нет.
##
## После боя карточка возвращалась в том виде, в каком звала в бой, — со
## спрайтом монстра, шкалой дружбы и строкой «Победа: +10 серебра · сундук».
## Монстр к тому моменту либо приручён, либо убежал, и обещать за него
## награду экран не имеет права: игрок читает это как «сюда можно ещё раз».
## Поляна опустела, делать на ней нечего, остаётся только идти дальше.
func _show_spent_glade() -> void:
	_glade_art.texture = null
	_headline.text = "Поляна опустела"
	_headline.add_theme_color_override("font_color", Color("DCC7A4"))
	_subline.text = ""
	_hide_stakes()
	_reward_label.visible = false


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
	_show_spent_glade()

	# Бой кончился — лес возвращается. Без этого карточка с итогом висела бы
	# в тишине до самого свайпа
	var glade := RunManager.current_glade
	if glade != null:
		Jukebox.play_glade(Glade.TYPE_KEYS.get(glade.type, "battle"))
	_refresh_buttons()
	if not _pending_result.is_empty():
		_hint.text = "%s\n%s" % [_pending_result, HINT_NEXT]
		_pending_result = ""


## Угощение закрылось — поляна пройдена, идём дальше САМИ.
##
## Раньше игрок возвращался на карточку той же встречи: монстр уже приручён,
## делать здесь нечего, а экран звал танцевать с ним заново. Приручение —
## финал поляны, и после него ждать свайпа не за чем.
func _on_taming_finished() -> void:
	_pending_result = ""
	_dismiss_battle()
	_busy = false
	_awaiting_result_swipe = false
	_next_glade()


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
		# Итог показывается ПОВЕРХ сцены боя, поэтому и кнопка своя —
		# на верхнем слое и выше танцоров
		_action_button.visible = false
		_next_button.visible = false
		_result_button.visible = true
		return
	_result_button.visible = false

	# Подпись говорит, ЧТО именно произойдёт: одна на все случаи так же
	# непонятна, как голый жест (GDD §8.1.1)
	match glade.type:
		Glade.Type.BATTLE:
			_action_button.text = "Танцевать"
		Glade.Type.WILD_BUSH:
			_action_button.text = "Собрать"
		Glade.Type.CAMPFIRE:
			_action_button.text = "Отдохнуть"
		Glade.Type.ENCOUNTER:
			match glade.encounter:
				Glade.Encounter.MERCHANT:
					_action_button.text = "Товар"
				Glade.Encounter.LOOT_BUSH:
					_action_button.text = "Потрясти"
				Glade.Encounter.GRANNY:
					_action_button.text = "Подойти"
				_:
					_action_button.text = "Посмотреть"
		_:
			_action_button.text = "Посмотреть"

	# Собранная поляна больше ничего не предлагает: кнопка действия уходит,
	# чтобы её не жали впустую. Исключение — торговец: к прилавку можно
	# вернуться, он ничего не раздаёт даром
	var merchant := glade.type == Glade.Type.ENCOUNTER \
		and glade.encounter == Glade.Encounter.MERCHANT
	if _glade_used and not merchant:
		_action_button.visible = false
		_next_button.visible = true
		_next_button.disabled = false
		_next_button.text = "Дальше ↑"
		_sync_hint()
		return

	_action_button.visible = not _glade_cleared or glade.type != Glade.Type.BATTLE
	_sync_hint()

	# Кнопка «дальше» гаснет там, где поляну нельзя пропустить, и это видно
	# сразу, а не после безрезультатного свайпа.
	#
	# Заблокированная кнопка МЕНЯЕТ ПОДПИСЬ, а не только цвет: на живом
	# прогоне серая «Дальше ↑» читалась как сломанная — игрок жал и не понимал,
	# почему ничего не происходит. Причина отказа должна стоять на самой кнопке
	var blocked := _blocks_swipe()
	_next_button.visible = true
	_next_button.disabled = blocked
	_next_button.text = "Сначала бой" if blocked else "Дальше ↑"


## Подсказка не обещает кнопки, которой нет.
##
## Текст подсказки ставится в `_show_glade` один раз и потом живёт сам по себе,
## а кнопка действия исчезает по состоянию — когда поляна отдана или бой уже
## был. Получался экран, зовущий нажать «Танцевать», которой на нём нет:
## ребёнок ищет несуществующую кнопку и решает, что игра сломалась.
func _sync_hint() -> void:
	if _action_button.visible:
		return
	if _hint.text.contains(_action_button.text):
		_hint.text = HINT_NEXT


## Съесть фрукт у костра: здоровье и баф до конца забега.
##
## Тот же плод мог пойти монстру на дружбу — в этом вся соль: лечение
## не бесплатное, оно стоит будущего друга (GDD §8.2.3).
func _eat_at_campfire(fruit_id: String, quality: FruitData.Quality) -> void:
	if not GameState.consume_fruit(fruit_id, quality):
		return
	var fruit := Registry.fruit(fruit_id)
	if fruit == null:
		return

	RunManager.restore_health(fruit.heal())
	RunManager.add_buff(fruit.buff())
	_open_campfire()


## Подпись бафа для кнопки. Пусто — тир без бафа, и строку не пишем вовсе:
## «баф: нет» занимает место и ничего не сообщает.
func _buff_text(fruit: FruitData) -> String:
	var buff := fruit.buff()
	if buff.is_empty():
		return ""
	var parts: Array[String] = []
	if buff.has("shield_reduction"):
		parts.append("защита +%d%%" % int(round(float(buff["shield_reduction"]) * 100.0)))
	if buff.has("power_bonus"):
		parts.append("удар +%.1f" % float(buff["power_bonus"]))
	if buff.has("window_scale"):
		parts.append("окно +%d%%" % int(round(float(buff["window_scale"]) * 100.0)))
	return "\n" + " · ".join(parts) + " до конца забега"


## Снимок защитника: уровень, шкала опыта и статы.
##
## Нужен дважды — до награды и после, — чтобы экран победы мог показать
## не только «стало», но и «было». Разность считать нельзя: на переходе
## уровня шкала обнуляется, и «после минус прибавка» врёт.
func _guardian_snapshot() -> Dictionary:
	var guardian := GameState.instance(RunManager.guardian_key)
	if guardian == null:
		return {}
	var progress := guardian.xp_progress()
	return {
		"name": guardian.display_name(),
		"level": guardian.level,
		"xp": progress.x,
		"xp_needed": progress.y,
		"health": guardian.max_health(),
		"power": guardian.power(),
		"max_level": guardian.is_max_level(),
	}


## Экран победы: сначала опыт, потом призы — по одному.
##
## Раньше всё вываливалось разом простыней текста, и рост защитника терялся
## среди строк добычи. Порядок здесь не украшение: сперва игрок видит, что
## его существо стало сильнее, и только потом — что нашлось в сундуке.
## Пока идут анимации, уйти нельзя: свайп и кнопка появляются в конце,
## иначе половину показа пролистывают, не заметив.
func _play_victory(monster: MonsterInstance, prizes: Array[Dictionary],
		before: Dictionary, after: Dictionary, levels: int) -> void:
	_open_panel("Наплясались!")
	_add_panel_label(monster.display_name(), 44)

	# Уйти пока нельзя: показ ещё идёт
	_awaiting_result_swipe = false
	_busy = true
	_refresh_buttons()

	if not before.is_empty():
		await _show_experience(before, after, levels)

	for prize: Dictionary in prizes:
		if not is_inside_tree():
			return
		await _show_prize(prize)

	_finish_victory(monster)


## Полоска опыта защитника и её рост.
##
## Ползёт, а не прыгает: рост, случившийся мгновенно, читается как «уже было
## так». При переходе уровня полоска добегает до края, обнуляется и идёт
## дальше — ровно так, как это произошло на самом деле.
func _show_experience(before: Dictionary, after: Dictionary, levels: int) -> void:
	# «Защитник:» здесь не украшение. Победивший и побеждённый бывают одного
	# вида, и тогда панель показывала имя дважды подряд без объяснения, кто
	# из них кто: «Ростик» заголовком и «Ростик · уровень 1» строкой ниже
	var title := Label.new()
	title.text = "Защитник: %s · уровень %d" % [before["name"], before["level"]]
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("DCC7A4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(title)

	var bar := ProgressBar.new()
	# Уже панели и по центру: на всю ширину шкала упиралась в рамку
	# и читалась как её часть, а не как полоска опыта
	bar.custom_minimum_size = Vector2(XP_BAR_WIDTH, 44)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = maxf(float(before["xp_needed"]), 1.0)
	bar.value = float(before["xp"])
	_panel_box.add_child(bar)

	var caption := Label.new()
	caption.add_theme_font_size_override("font_size", 28)
	caption.add_theme_color_override("font_color", Color("ADA99F"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel_box.add_child(caption)
	_fit_panel()

	if bool(before.get("max_level", false)):
		caption.text = "Опыт: максимальный уровень"
		await get_tree().create_timer(PRIZE_STEP).timeout
		return

	# Каждый пройденный уровень — свой пробег полоски до края и обнуление
	for i in levels:
		var tween := create_tween()
		tween.tween_property(bar, "value", bar.max_value, XP_FILL_SECONDS)
		await tween.finished
		bar.value = 0.0
		title.text = "Защитник: %s · уровень %d" % [
			before["name"], int(before["level"]) + i + 1]

	bar.max_value = maxf(float(after["xp_needed"]), 1.0)
	var last := create_tween()
	last.tween_property(bar, "value", float(after["xp"]), XP_FILL_SECONDS)
	await last.finished
	caption.text = "Опыт %d / %d" % [after["xp"], after["xp_needed"]]

	if levels <= 0:
		await get_tree().create_timer(PRIZE_STEP * 0.5).timeout
		return

	# Уровень взят — показываем, ЧТО именно выросло. Без этого «уровень 3»
	# остаётся числом, за которым не видно ни здоровья, ни удара
	var grew := Label.new()
	grew.add_theme_font_size_override("font_size", 34)
	grew.add_theme_color_override("font_color", Color("FFD24D"))
	grew.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grew.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grew.text = "Новый уровень!  Здоровье %d → %d · удар %.1f → %.1f" % [
		before["health"], after["health"], before["power"], after["power"],
	]
	_panel_box.add_child(grew)
	_fit_panel()
	await get_tree().create_timer(PRIZE_STEP).timeout


## Один приз: картинка и подпись. Ничего не выпало — ничего и не пишем.
func _show_prize(prize: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Строка приза centered целиком: иконка и подпись держатся вместе
	# посреди панели, а не разъезжаются по её краям
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var item: Resource = prize.get("item")
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(96, 96)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Картинка обязательна у КАЖДОГО приза. У серебра предмета нет,
	# поэтому путь задаётся прямо: пустой слот вместо монеты сдвигал бы
	# подпись и делал строку непохожей на остальные
	var direct: String = prize.get("icon", "")
	if not direct.is_empty() and ResourceLoader.exists(direct):
		icon.texture = load(direct) as Texture2D
	else:
		icon.texture = UIUtil.item_icon(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text := Label.new()
	text.text = String(prize.get("text", ""))
	text.add_theme_font_size_override("font_size", 38)
	text.add_theme_color_override("font_color", Color("F0DEC0"))
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Ширина колонки задана явно. В центрированном `HBoxContainer` подпись
	# получает свой МИНИМАЛЬНЫЙ размер, а у автопереноса он равен ширине
	# одного символа — «+12 серебра» вставало столбиком по букве в строке
	text.custom_minimum_size = Vector2(560, 96)
	row.add_child(text)

	_panel_box.add_child(row)
	_fit_panel()

	# Приз выезжает, а не появляется: движение отделяет один приз от другого,
	# и подряд идущие строки перестают сливаться в список
	row.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(row, "modulate:a", 1.0, 0.2)
	await get_tree().create_timer(PRIZE_STEP).timeout


## Показ закончился — можно идти дальше.
func _finish_victory(monster: MonsterInstance) -> void:
	if _pending_taming != null:
		var species := monster.data()
		var favorite := Registry.fruit(species.favorite_fruit_id) if species != null else null
		if favorite != null:
			_add_panel_label("Любит: %s" % favorite.display_name, 30)
		_add_panel_button("Угостить", _open_taming)
		return

	if GameState.has_instance(monster.species_id, monster.grade):
		_add_panel_label("Он и так твой друг — дрались ради опыта и добычи", 30)
	else:
		var step := GameState.missing_step(monster.species_id, monster.grade)
		if step >= 0:
			_add_panel_label("Подружиться пока нельзя: сначала %s"
				% MonsterData.rarity_name(step), 30)
	_add_panel_button("Дальше", _close_victory)
