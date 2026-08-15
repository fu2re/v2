extends TestHarness

## Раскладка экранов: что налезает на что.
##
## Все три проверки здесь появились после живого прогона, и ни одну из них
## не ловила ни компиляция, ни прежние тесты: фон висел маркой посреди пустоты,
## витрина награды лежала на кнопках, а кнопки поляны торчали сквозь модальную
## панель. Экран собирается без ошибок и в таком виде — увидеть это можно
## только измерив.

const SCREEN := Vector2(1080, 1920)
const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	await _test_backgrounds_cover_the_screen()
	await _test_card_widgets_do_not_overlap_buttons()
	await _test_labels_do_not_overlap_each_other()
	await _test_panel_hides_glade_buttons()
	await _test_victory_screen_comes_before_taming()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _rect_of(control: Control) -> Rect2:
	return Rect2(control.position, control.size)


## Фон обязан закрывать экран целиком: картинка 328×480 в оригинальном
## размере висит маркой посреди пустоты — именно так и выглядел первый
## живой прогон усадьбы.
func _test_backgrounds_cover_the_screen() -> void:
	print("Фоны закрывают экран целиком")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)

	var screens := {
		"res://scenes/lobby/Lobby.tscn": "Scenery",
		"res://scenes/collection/Collection.tscn": "Scenery",
		"res://scenes/inventory/Inventory.tscn": "Scenery",
	}

	for path: String in screens:
		var packed: PackedScene = load(path)
		var place: Node = packed.instantiate()
		add_child(place)
		await _frames(2)

		var sprite: Sprite2D = place.get_node_or_null(screens[path])
		check(sprite != null, "%s: узел фона на месте" % path)
		if sprite != null and sprite.visible and sprite.texture != null:
			var covered := sprite.texture.get_size() * sprite.scale
			check(covered.x >= SCREEN.x and covered.y >= SCREEN.y,
				"%s: фон закрывает экран (%.0f×%.0f)" % [path, covered.x, covered.y])
			check(sprite.position.is_equal_approx(SCREEN * 0.5),
				"%s: фон отцентрован" % path)
		elif sprite != null:
			note("%s: фон ещё не нарисован" % path)

		place.queue_free()
		await _frames(2)


## Витрина награды не должна лежать на кнопках.
##
## На живом прогоне «Дружба 0/100» и строка про сундук печатались прямо
## поверх «Танцевать» и «Дальше ↑»: читать было нельзя ни то, ни другое.
func _test_card_widgets_do_not_overlap_buttons() -> void:
	print("Витрина награды не налезает на кнопки")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)
	RunManager.set_seed(11)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	var glade := Glade.new()
	glade.type = Glade.Type.BATTLE
	glade.depth = 1
	glade.monster_id = "synth_slime"
	glade.grade = COMMON
	glade.silver_reward = 9
	RunManager.current_glade = glade
	feed._show_glade(glade)
	await _frames(2)

	var buttons := {
		"Танцевать": feed._action_button,
		"Дальше": feed._next_button,
	}
	var widgets := {
		"полоска дружбы": feed._friendship_track,
		"подпись дружбы": feed._friendship_label,
		"строка награды": feed._reward_label,
		"подсказка": feed._hint,
	}

	for button_name: String in buttons:
		var button: Control = buttons[button_name]
		for widget_name: String in widgets:
			var widget: Control = widgets[widget_name]
			if not widget.visible:
				continue
			check(not _rect_of(button).intersects(_rect_of(widget)),
				"«%s» не перекрывается с «%s»" % [button_name, widget_name])

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Метки карточки не должны налезать друг на друга.
##
## Отдельно от проверки кнопок: подпись дружбы бывает двухстрочной («Сначала
## подружись: …» плюс сама шкала), и на живом прогоне она наезжала на строку
## награды — читать нельзя было ни ту, ни другую.
func _test_labels_do_not_overlap_each_other() -> void:
	print("Подписи карточки не наезжают друг на друга")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)
	RunManager.set_seed(5)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	# Самый длинный случай: закрытая ступень, подпись в две строки
	var glade := Glade.new()
	glade.type = Glade.Type.BATTLE
	glade.depth = 1
	glade.monster_id = "beat_serpent"
	glade.grade = MonsterData.Rarity.RARE
	glade.silver_reward = 9
	RunManager.current_glade = glade
	feed._show_glade(glade)
	await _frames(2)

	check(feed._friendship_label.text.contains("Сначала"),
		"подпись про ступень показана: [%s]" % feed._friendship_label.text)

	var pairs := [
		["полоска дружбы", feed._friendship_track, "подпись дружбы", feed._friendship_label],
		["подпись дружбы", feed._friendship_label, "строка награды", feed._reward_label],
		["строка награды", feed._reward_label, "подсказка", feed._hint],
	]
	for pair: Array in pairs:
		var first: Control = pair[1]
		var second: Control = pair[3]
		if not first.visible or not second.visible:
			continue
		check(not _rect_of(first).intersects(_rect_of(second)),
			"«%s» не перекрывается с «%s»" % [pair[0], pair[2]])

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Модальная панель обязана скрывать кнопки поляны.
##
## Они лежат в дереве после подложки и потому рисуются ПОВЕРХ неё: на живом
## прогоне «Отдохнуть» и «Дальше ↑» торчали сквозь панель встречи с бабушкой.
func _test_panel_hides_glade_buttons() -> void:
	print("Панель встречи скрывает кнопки поляны")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)
	RunManager.set_seed(11)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	feed._open_panel("Проверка")
	await _frames(2)

	check(not feed._action_button.visible, "кнопка действия спрятана")
	check(not feed._next_button.visible, "кнопка «дальше» спрятана")
	check(not feed._home_button.visible, "кнопка «домой» спрятана")
	check(feed._panel_bg.visible, "подложка панели показана")

	feed._close_panel()
	await _frames(2)
	check(feed._home_button.visible, "после закрытия кнопки вернулись")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Победа сначала показывает итог, и только потом угощение.
##
## Раньше экран приручения выезжал мгновенно, поверх падающего монстра:
## ни анимации, ни добычи игрок увидеть не успевал.
func _test_victory_screen_comes_before_taming() -> void:
	print("После победы сперва итог, потом угощение")
	GameState.reset()
	FarmState.reset()
	RunManager.set_seed(17)
	GameState.tame("disco_sprout", COMMON)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	var glade := Glade.new()
	glade.type = Glade.Type.BATTLE
	glade.depth = 1
	glade.monster_id = "synth_slime"
	glade.grade = COMMON
	glade.silver_reward = 9
	RunManager.current_glade = glade
	feed._show_glade(glade)
	await _frames(1)

	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON),
		GameState.instance(RunManager.guardian_key), 100, 1)
	feed._on_battle_finished(true, state)
	await _frames(2)

	check(feed._panel_box.visible, "экран победы показан")
	check(not feed._taming.visible, "угощение ЕЩЁ не открыто")

	# На экране победы игрок должен увидеть, что ему досталось
	var shown := ""
	for child in feed._panel_box.get_children():
		if child is Label:
			shown += child.text + "\n"
	check(shown.contains("наплясался"), "сказано, что монстр побеждён")
	check(shown.contains("серебра"), "названа добыча: [%s]" % shown.strip_edges())

	# И только по нажатию открывается угощение
	feed._open_taming()
	await _frames(2)
	check(feed._taming.visible, "после нажатия открылось угощение")
	check(not feed._panel_box.visible, "итог убран")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)
