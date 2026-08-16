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
@onready var _panel_bg: ColorRect = $PanelLayer/PanelBackdrop
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
	# Прокрутка живёт и гаснет вместе с панелью: пустой ScrollContainer
	# во весь экран молча съедал бы клики по тому, что под ним
	var scroll: ScrollContainer = $PanelLayer/PanelScroll
	_panel_box.visibility_changed.connect(func(): scroll.visible = _panel_box.visible)

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
			_show_stakes(glade)
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

	_friendship_track.visible = true
	_friendship_fill.visible = true
	var full_width := _friendship_track.size.x
	_friendship_fill.size.x = full_width * clampf(float(value) / float(threshold), 0.0, 1.0)

	# Пометка «можно подружиться» затмевает всё остальное: это единственная
	# ситуация, в которой пропуск стоит игроку по-настоящему дорого
	var already := GameState.has_instance(glade.monster_id, glade.grade)
	var open := GameState.can_tame(glade.monster_id, glade.grade)
	var will_tame := not already and open and after_win >= threshold
	_tame_banner.visible = will_tame
	if will_tame:
		_tame_banner.text = "Можно подружиться!"

	if already:
		_friendship_label.text = "Уже друг · дружба %d/%d" % [value, threshold]
	elif not open:
		# Через ступень приручать нельзя, и молчать об этом нельзя тоже:
		# полная шкала без объяснения выглядит как поломка
		var step := GameState.missing_step(glade.monster_id, glade.grade)
		_friendship_label.text = "Сначала подружись: %s\nДружба копится: %d/%d" % [
			MonsterData.rarity_name(step), value, threshold,
		]
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
			_glade_used = true
			RunManager.rest_at_campfire()
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
	# Сумка зелий ограничена — проверяем до списания серебра
	if item is PotionData and not GameState.has_potion_room():
		return
	RunManager.add_loot_silver(-price)
	if item is PotionData:
		GameState.add_potion(id)
	else:
		GameState.add_gear(id)
	_open_merchant(RunManager.current_glade)


## Костёр — единственная точка смены гуардиана внутри забега (GDD §15.1).
func _open_campfire() -> void:
	_open_panel("Костёр")
	_add_panel_label("Здоровье восстановлено: %d / %d" % [RunManager.health, RunManager.max_health])

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
	_hint.text = HINT_NEXT
	_busy = false
	# Кнопки поляны возвращаются в том состоянии, которое положено ЭТОЙ поляне,
	# а не в том, в каком были до панели
	_home_button.visible = true
	_refresh_buttons()


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

	if RunManager.health <= 0:
		_dismiss_battle()
		RunManager.die()
		return

	# Опыт — тому, кто дрался, и НЕ ТОЛЬКО за победу (GDD §6.5). За убежавшего
	# монстра меньше, но не ноль: иначе новичок, которому пока нечем добить,
	# застревает навсегда — бой обязателен, а гуардиан от него не растёт
	var levels := RunManager.reward_guardian_xp(monster.grade, perfect, won)
	var grown := ""
	if levels > 0:
		var guardian := GameState.instance(RunManager.guardian_key)
		grown = "%s подрос до уровня %d!" % [
			guardian.display_name(), guardian.level,
		] if guardian != null else ""

	if won:
		var silver: int = RunManager.current_glade.silver_reward
		RunManager.add_loot_silver(silver)

		# Итог собирается ЗДЕСЬ, а показывается на экране победы: пока
		# монстр падает и на экране «Наплясался!», игрок должен успеть
		# увидеть, что ему досталось. Раньше поверх этого мгновенно
		# выезжало угощение, и добычу никто не читал
		var lines: Array[String] = ["+%d серебра" % silver]

		var prize := RunManager.roll_victory_gear(monster.grade)
		if not prize.is_empty():
			var item := Registry.gear(prize)
			if item != null:
				lines.append("Сундук: %s" % item.display_name)

		if not grown.is_empty():
			lines.append(grown)

		# Кого угощать — запоминаем: приручение откроется по нажатию игрока
		_pending_taming = monster
		_pending_perfect = perfect
		_show_victory(monster, lines)
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
		if not grown.is_empty():
			_pending_result = "%s\n%s" % [_pending_result, grown]
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
func _show_victory(monster: MonsterInstance, lines: Array[String]) -> void:
	# «Наплясались» во множественном числе не случайно: имена монстров бывают
	# любого рода, и «Пыльца наплясался» — то, что игрок видел на экране.
	# Плясали оба, поэтому форма честная и согласуется с чем угодно
	_open_panel("Наплясались!")
	_add_panel_label(monster.display_name(), 44)

	for line: String in lines:
		_add_panel_label(line, 38)

	# Дальше — угощение, и кнопка честно называет, что будет
	var species := monster.data()
	var favorite := Registry.fruit(species.favorite_fruit_id) if species != null else null
	if favorite != null:
		_add_panel_label("Любит: %s" % favorite.display_name, 30)

	_add_panel_button("Угостить", _open_taming)


## Перейти от итога боя к угощению.
##
## Панель гасим напрямую, а не через `_close_panel`: тот возвращает кнопки
## поляны, а под нами всё ещё сцена боя — карточки там нет, и кнопки
## «Танцевать» поверх лежащего монстра выглядели бы приглашением
## подраться ещё раз. Карточка вернётся сама, когда бой закроется.
func _open_taming() -> void:
	_panel_box.visible = false
	_panel_bg.visible = false

	if _pending_taming == null:
		return
	_taming.show_for(_pending_taming, _pending_perfect)
	_pending_taming = null


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

	# Бой кончился — лес возвращается. Без этого карточка с итогом висела бы
	# в тишине до самого свайпа
	var glade := RunManager.current_glade
	if glade != null:
		Jukebox.play_glade(Glade.TYPE_KEYS.get(glade.type, "battle"))
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
		return

	_action_button.visible = not _glade_cleared or glade.type != Glade.Type.BATTLE

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
