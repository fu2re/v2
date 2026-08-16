extends TestHarness

## Читаемость: помещается ли текст туда, куда его положили.
##
## Отличается от `test_layout` предметом: тот ловит НАЛОЖЕНИЯ, этот — выход
## за край. Обе поломки выглядят одинаково безобидно в коде и одинаково
## позорно на экране, но ищутся по-разному: наложение — пересечением
## прямоугольников, вылет — сравнением желаемого размера с отведённым.
##
## Поводом стал огород: в клетке 200×200 подпись «♪ станцевать» кеглем 26
## не помещалась, и слово обрывалось на «станцеват / ь». Сцена при этом
## поднималась без единой ошибки.

const SCREEN := Vector2(1080, 1920)
const COMMON := MonsterData.Rarity.COMMON

## Кегль, ниже которого текст для семи лет мелковат. Не догма, но всё,
## что меньше, обязано быть вспомогательным — счётчиком, а не смыслом.
const MIN_BODY_SIZE := 24

## Нижняя граница нажимаемого. 110 пикселей холста — примерно 10 мм
## на телефоне; по меньшему детский палец промахивается.
const MIN_TOUCH := 110.0

const SCREENS := [
	"res://scenes/lobby/Lobby.tscn",
	"res://scenes/farm/Farm.tscn",
	"res://scenes/collection/Collection.tscn",
	"res://scenes/inventory/Inventory.tscn",
	"res://scenes/merchant/Merchant.tscn",
	"res://scenes/shop/Shop.tscn",
	"res://scenes/intro/CharacterSelect.tscn",
]


func run_tests() -> void:
	await _test_text_fits_its_box()
	await _test_nothing_sticks_out_of_the_screen()
	await _test_buttons_are_big_enough_for_a_child()
	_test_theme_is_applied()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _rich_state() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	OnboardingState.reset()
	OnboardingState.mark_done()
	GameState.tame("disco_sprout", COMMON)
	GameState.set_guardian("disco_sprout:0")
	GameState.add_silver(340)
	ShopState.add_gold(120)
	# Состояние НЕ пустое: пустые списки ничего не говорят о том,
	# помещается ли в строку самое длинное название в игре
	FarmState.add_seed("chord_apple", 2)
	FarmState.plant(0, "chord_apple")
	GameState.add_gear("acorn_charm")
	GameState.add_potion("health_potion", 2)


func _open(path: String) -> Node:
	var place: Node = (load(path) as PackedScene).instantiate()
	add_child(place)
	await _frames(4)
	return place


## Подписи и кнопки со своим текстом. Godot умеет сказать, сколько места
## тексту НУЖНО (`get_minimum_size`); если это больше отведённого — на экране
## обрезок или перенос посреди слова.
func _walk(node: Node, out: Array) -> void:
	if node is Label or node is Button:
		out.append(node)
	for child in node.get_children():
		_walk(child, out)


## Насколько текст не влез. Меряем ШРИФТОМ, а не `get_combined_minimum_size()`:
## у кнопки с переносом строк тот возвращает размер до переноса и молча
## отчитывается, что всё помещается, — первая версия этой проверки прошла
## мимо ровно той поломки, ради которой писалась.
func _overflow_of(control: Control) -> Vector2:
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	if font == null:
		return Vector2.ZERO

	var inner := control.size
	if control is Button:
		var box := control.get_theme_stylebox("normal")
		if box != null:
			inner.x -= box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
			inner.y -= box.get_margin(SIDE_TOP) + box.get_margin(SIDE_BOTTOM)
		# Картинка забирает место у текста. Сверху — забирает высоту,
		# слева — ширину; иначе меряли бы по пустому месту, которого нет
		var button := control as Button
		if button.icon != null:
			var icon_size := button.icon.get_size()
			if button.vertical_icon_alignment == VERTICAL_ALIGNMENT_TOP:
				inner.y -= minf(icon_size.y, inner.y * 0.5)
			else:
				inner.x -= minf(icon_size.x, inner.x * 0.5)
	if inner.x <= 0.0:
		return Vector2.ZERO

	var wrap := inner.x if control.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
	var measured := font.get_multiline_string_size(
		control.text, HORIZONTAL_ALIGNMENT_LEFT, wrap, font_size)
	return measured - inner


func _test_text_fits_its_box() -> void:
	print("Текст помещается в отведённое место")
	for path: String in SCREENS:
		_rich_state()
		var place := await _open(path)

		var controls: Array = []
		_walk(place, controls)
		for control: Control in controls:
			if not control.visible or not control.is_visible_in_tree():
				continue
			var text: String = control.text
			if text.strip_edges().is_empty():
				continue
			var box := control.size
			if box.x <= 0.0 or box.y <= 0.0:
				continue
			# Внутри контейнера размер — дело контейнера, а не наше
			if control.get_parent() is Container:
				continue

			var overflow := _overflow_of(control)
			check(overflow.y <= 1.0,
				"%s: «%s» не помещается по высоте (лишних %.0f px)" % [
					path.get_file(), text.substr(0, 28), overflow.y])

		place.queue_free()
		await _frames(1)


## Ничто не уезжает за край экрана. Кнопка, наполовину вылезшая за границу,
## нажимается наполовину — и ребёнок решает, что игра сломалась.
func _test_nothing_sticks_out_of_the_screen() -> void:
	print("Ничто не торчит за краем экрана")
	for path: String in SCREENS:
		_rich_state()
		var place := await _open(path)

		var controls: Array = []
		_walk(place, controls)
		for control: Control in controls:
			if not control.visible or not control.is_visible_in_tree():
				continue
			if control.size.x <= 0.0 or control.size.y <= 0.0:
				continue
			var top_left := control.global_position
			var bottom_right := top_left + control.size
			check(top_left.x >= -1.0 and top_left.y >= -1.0,
				"%s: %s начинается за краем (%.0f, %.0f)" % [
					path.get_file(), control.name, top_left.x, top_left.y])
			check(bottom_right.x <= SCREEN.x + 1.0,
				"%s: %s вылезает справа (%.0f > %.0f)" % [
					path.get_file(), control.name, bottom_right.x, SCREEN.x])

		place.queue_free()
		await _frames(1)


func _test_buttons_are_big_enough_for_a_child() -> void:
	print("Кнопки достаточно крупные для детского пальца")
	for path: String in SCREENS:
		_rich_state()
		var place := await _open(path)

		var controls: Array = []
		_walk(place, controls)
		for control: Control in controls:
			if not (control is Button) or not control.is_visible_in_tree():
				continue
			# Накладка на постройку двора меряется своей картинкой,
			# а не текстом, и бывает любой формы
			if (control as Button).flat:
				continue
			check(control.size.y >= MIN_TOUCH,
				"%s: кнопка «%s» ростом %.0f — мельче %.0f" % [
					path.get_file(), control.text.substr(0, 20),
					control.size.y, MIN_TOUCH])

		place.queue_free()
		await _frames(1)


## Тема обязана быть подключена проектом. Без неё Godot рисует своей
## дефолтной — плоскими серыми прямоугольниками, и игра выглядит
## системным приложением (GDD §11.4).
func _test_theme_is_applied() -> void:
	print("Тема проекта подключена")
	var path := "res://art/ui/beatroot_theme.tres"
	check(ResourceLoader.exists(path), "нет файла темы %s" % path)

	var declared: String = ProjectSettings.get_setting("gui/theme/custom", "")
	check_eq(declared, path, "тема в project.godot")

	var theme := load(path) as Theme
	if theme == null:
		check(false, "тема не грузится как Theme")
		return

	# Кнопка обязана иметь свой стиль во ВСЕХ состояниях: без `pressed`
	# нажатие не видно, и ребёнок жмёт второй раз
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		check(theme.has_stylebox(state, "Button"),
			"у кнопки нет стиля «%s»" % state)

	# Обводка подписей — не украшение: подписи лежат на пёстром лесу
	check(theme.get_constant("outline_size", "Label") > 0,
		"у подписей нет обводки — текст утонет в фоне")
