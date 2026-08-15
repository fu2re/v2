extends Node

## Каждая кнопка должна быть кликабельной.
##
## Класс багов, который не ловят ни компиляция, ни подъём сцены: невидимый
## контейнер поверх кнопки съедает клики. У `Control` по умолчанию
## `mouse_filter = STOP`, поэтому пустая обёртка, добавленная позже кнопки,
## делает её мёртвой — и это заметно только руками.
##
## Тест повторяет логику выбора Godot: среди контролов, накрывающих точку,
## побеждает последний в порядке обхода дерева.

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()

	_prepare_state()

	for path in [
		"res://scenes/farm/Farm.tscn",
		"res://scenes/collection/Collection.tscn",
		"res://scenes/shop/Shop.tscn",
		"res://scenes/run/RunFeed.tscn",
		"res://tools/chart_forge/ChartForge.tscn",
	]:
		await _check_scene(path)

	# Панели, которые открываются по ходу игры. Именно там этот класс багов
	# и живёт: модальный слой ложится поверх и перекрывает то, что под ним
	await _check_panel("res://scenes/farm/Farm.tscn", "выбор семян",
		func(root): root._open_seed_picker(0))
	await _check_panel("res://scenes/collection/Collection.tscn", "снаряжение",
		func(root): root._open_gear("disco_sprout"))
	await _check_panel("res://scenes/run/RunFeed.tscn", "костёр",
		func(root): root._open_campfire())
	await _check_panel("res://scenes/run/RunFeed.tscn", "торговец",
		func(root): root._open_merchant(RunManager.current_glade))

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Состояние, при котором панели вообще есть что показать.
func _prepare_state() -> void:
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	FarmState.add_seed("drum_berry", 3)
	FarmState.add_seed("echo_pear", 2)

	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.add_friendship("bass_bear", Registry.monster("bass_bear").friendship_threshold())
	GameState.set_guardian("disco_sprout")
	GameState.add_gear("spring_boots")
	GameState.add_seeds(500)
	ShopState.add_chords(500)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


func _check_scene(path: String) -> void:
	print("Кликабельность: %s" % path.get_file())
	await _run_check(path, "")


## То же, но с открытой панелью.
func _check_panel(path: String, label: String, opener: Callable) -> void:
	print("Кликабельность: %s → %s" % [path.get_file(), label])
	await _run_check(path, label, opener)


func _run_check(path: String, label: String, opener := Callable()) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		check(false, "%s загружается" % path)
		return

	var root := packed.instantiate()
	add_child(root)
	for i in 3:
		await get_tree().process_frame

	if opener.is_valid():
		opener.call(root)
		for i in 2:
			await get_tree().process_frame

	var tag := path.get_file() if label.is_empty() else "%s → %s" % [path.get_file(), label]
	var order: Array[Control] = []
	_collect_controls(root, order)

	var buttons: Array[Button] = []
	for c in order:
		if c is Button and c.visible and not c.disabled:
			buttons.append(c)

	check(not buttons.is_empty(), "%s: кнопки найдены (%d)" % [tag, buttons.size()])

	# Кнопки ПОД открытой модалкой блокируются намеренно — это не баг, а смысл
	# модального слоя. Проверяем только то, что находится над последней
	# перекрывающей экран подложкой
	var modal_index := _last_backdrop_index(order)
	var checked := 0

	for button in buttons:
		if order.find(button) < modal_index:
			continue
		checked += 1
		var point := button.get_global_rect().get_center()
		var winner := _topmost_at(order, point)
		var reachable := winner == button or button.is_ancestor_of(winner)
		check(reachable, "%s: кнопку «%s» перекрывает %s (%s)" % [
			tag, button.text,
			winner.name if winner != null else "ничто",
			winner.get_class() if winner != null else "-",
		])

	check(checked > 0, "%s: есть хоть одна доступная кнопка" % tag)

	root.queue_free()
	for i in 2:
		await get_tree().process_frame
	Conductor.stop()


## Индекс последней подложки, перекрывающей экран целиком.
##
## Такая подложка означает модальный слой: всё, что раньше неё в дереве,
## закрыто намеренно.
func _last_backdrop_index(order: Array[Control]) -> int:
	var screen := Vector2(1080, 1920)
	var result := -1
	for i in order.size():
		var c := order[i]
		if not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if c is Button:
			continue
		var rect := c.get_global_rect()
		if rect.size.x >= screen.x * 0.9 and rect.size.y >= screen.y * 0.9:
			result = i
	return result


## Обход в том же порядке, в каком Godot строит дерево контролов:
## чем позже узел, тем он выше в разборе ввода.
func _collect_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_collect_controls(child, out)


## Кто получит клик в этой точке. Идём с конца: побеждает последний,
## который накрывает точку и не пропускает ввод насквозь.
func _topmost_at(order: Array[Control], point: Vector2) -> Control:
	for i in range(order.size() - 1, -1, -1):
		var c := order[i]
		if not c.is_visible_in_tree():
			continue
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if c.get_global_rect().has_point(point):
			return c
	return null
