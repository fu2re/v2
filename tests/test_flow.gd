extends Node

## Проверки живого взаимодействия: жмём НАСТОЯЩИЕ кнопки настоящих сцен.
##
## test_clickable отвечает на вопрос «дойдёт ли клик до кнопки», а этот —
## на вопрос «что произойдёт, если нажать её несколько раз подряд».
## Оба бага, о которых сообщил игрок, живут именно здесь.

var _failed := 0
var _passed := 0
## Печатать, кто перехватывает клик. Включай при разборе поломок:
## именно этот вывод показал, что клик доходит до кнопки, а `pressed`
## не срабатывает, потому что кнопку пересоздают между нажатием и отпусканием.
var _diagnose := false


## Кто на самом деле получит клик в этой точке.
func _who_is_at(from: Control, point: Vector2) -> String:
	var root := from.get_tree().root
	var found: Array[Control] = []
	_all_controls(root, found)
	for i in range(found.size() - 1, -1, -1):
		var c := found[i]
		if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if c.get_global_rect().has_point(point):
			return "%s (%s)" % [c.name, c.get_class()]
	return "ничто"


func _all_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_all_controls(child, out)


func _ready() -> void:
	SaveManager.enter_test_mode()

	await _test_planting_several_plots()
	await _test_home_button_does_not_start_battle()

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


func check_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s (получено %s, ожидалось %s)" % [description, actual, expected])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Настоящий клик через viewport, а не вызов сигнала.
##
## Разница принципиальна: pressed.emit() минует всю маршрутизацию ввода,
## поэтому проходит даже там, где живой клик перехватывает чужой обработчик.
## Оба бага, о которых сообщил игрок, видны только так.
func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	if _diagnose:
		print("    клик по «%s» в %s → перехватывает: %s"
			% [control.text if control is Button else control.name, point,
				_who_is_at(control, point)])
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await get_tree().process_frame
	await get_tree().process_frame


func _buttons_in(node: Node, out: Array[Button]) -> void:
	if node is Button and node.visible and not node.disabled:
		out.append(node)
	for child in node.get_children():
		_buttons_in(child, out)


func _visible_buttons(root: Node) -> Array[Button]:
	var out: Array[Button] = []
	_buttons_in(root, out)
	return out


## Игрок сообщил: сажается только одно семечко, дальше не выходит.
func _test_planting_several_plots() -> void:
	print("Посадка в несколько грядок подряд")
	GameState.reset()
	FarmState.reset()
	FarmState.add_seed("drum_berry", 5)
	FarmState.add_seed("echo_pear", 5)

	var farm := preload("res://scenes/farm/Farm.tscn").instantiate()
	add_child(farm)
	await _frames(3)

	for plot in 3:
		var plot_buttons: Array[Button] = []
		_buttons_in(farm._grid, plot_buttons)
		check(plot_buttons.size() >= 3, "грядка %d: кнопки грядок на месте (%d)"
			% [plot, plot_buttons.size()])
		if plot >= plot_buttons.size():
			break

		await _click(plot_buttons[plot])

		check(farm._seed_picker.visible, "грядка %d: список семян открылся" % plot)

		var seed_buttons: Array[Button] = []
		_buttons_in(farm._seed_picker, seed_buttons)
		# Последняя кнопка — «Отмена», сажаем первым доступным семенем
		check(seed_buttons.size() >= 2, "грядка %d: в списке есть семена (%d)"
			% [plot, seed_buttons.size()])
		if seed_buttons.size() < 2:
			break

		await _click(seed_buttons[0])

		check(not FarmState.is_empty_plot(plot), "грядка %d засажена" % plot)
		check(not farm._seed_picker.visible, "грядка %d: список закрылся" % plot)

	var planted := 0
	for i in FarmState.plot_count():
		if not FarmState.is_empty_plot(i):
			planted += 1
	check_eq(planted, 3, "засажены все три грядки подряд")

	farm.queue_free()
	await _frames(2)


## Игрок сообщил: кнопка возврата домой не работает.
##
## Подозрение: обработчик свайпа ловит тот же тап и разрешает поляну,
## то есть вместо ухода домой начинается бой.
func _test_home_button_does_not_start_battle() -> void:
	print("Кнопка «Домой» уводит домой, а не в бой")
	GameState.reset()
	FarmState.reset()
	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.set_guardian("disco_sprout")

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	check(RunManager.is_active, "забег идёт")
	check(feed._home_button.visible, "кнопка «Домой» видна")

	var ended: Array[bool] = []
	RunManager.run_ended.connect(func(_d, _f, _s): ended.append(true), CONNECT_ONE_SHOT)

	await _click(feed._home_button)

	check(not ended.is_empty(), "нажатие увело забег домой")
	check(not RunManager.is_active, "забег закрыт")
	check(feed._battle == null, "бой не начался вместо ухода домой")

	feed.queue_free()
	await _frames(2)
