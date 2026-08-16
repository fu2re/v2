extends TestHarness

## Каждая кнопка должна быть кликабельной.
##
## Класс багов, который не ловят ни компиляция, ни подъём сцены: невидимый
## контейнер поверх кнопки съедает клики. У `Control` по умолчанию
## `mouse_filter = STOP`, поэтому пустая обёртка, добавленная позже кнопки,
## делает её мёртвой — и это заметно только руками.
##
## Тест повторяет логику выбора Godot: среди контролов, накрывающих точку,
## побеждает последний в порядке обхода дерева.

func run_tests() -> void:

	_prepare_state()

	for path in [
		"res://scenes/lobby/Lobby.tscn",
		"res://scenes/farm/Farm.tscn",
		"res://scenes/merchant/Merchant.tscn",
		"res://scenes/collection/Collection.tscn",
		"res://scenes/shop/Shop.tscn",
		"res://scenes/inventory/Inventory.tscn",
		"res://scenes/run/RunFeed.tscn",
		"res://tools/chart_forge/ChartForge.tscn",
	]:
		await _check_scene(path)

	# Панели, которые открываются по ходу игры. Именно там этот класс багов
	# и живёт: модальный слой ложится поверх и перекрывает то, что под ним
	await _check_panel("res://scenes/farm/Farm.tscn", "выбор семян",
		func(root): root._open_seed_picker(0))
	await _check_panel("res://scenes/collection/Collection.tscn", "снаряжение",
		func(root): root._open_gear("disco_sprout:0"))
	await _check_panel("res://scenes/collection/Collection.tscn", "угощение",
		func(root): root._open_feed("disco_sprout:0"))
	await _check_panel("res://scenes/run/RunFeed.tscn", "костёр",
		func(root): root._open_campfire())
	await _check_panel("res://scenes/run/RunFeed.tscn", "торговец",
		func(root): root._open_merchant(RunManager.current_glade))

	# Экран победы — единственная панель, которая открывается ПОВЕРХ живой
	# сцены боя. Именно там кнопка «Угостить» и оказалась погребена: панель
	# лежала на нулевом слое, а бой со своим HUD — выше
	await _check_panel("res://scenes/run/RunFeed.tscn", "победа поверх боя",
		func(root): _open_victory(root))


## Показать экран победы так же, как это делает игра: со сценой боя на месте.
##
## Без боя под панелью проверка бессмысленна — накрывать её будет нечему,
## и первая версия этого теста именно поэтому ничего не поймала.
func _open_victory(root: Node) -> void:
	var glade := RunManager.current_glade
	if glade == null:
		return
	if glade.type != Glade.Type.BATTLE:
		glade.type = Glade.Type.BATTLE
		glade.monster_id = "disco_sprout"
	root._start_battle(glade)

	var monster := MonsterInstance.create(glade.monster_id, glade.grade)
	var lines: Array[String] = ["+12 серебра"]
	root._pending_taming = monster
	root._show_victory(monster, lines)


## Состояние, при котором панели вообще есть что показать.
func _prepare_state() -> void:
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	FarmState.add_seed("drum_berry", 3)
	FarmState.add_seed("echo_pear", 2)

	GameState.tame("disco_sprout", MonsterData.Rarity.COMMON)
	GameState.tame("bass_bear", MonsterData.Rarity.COMMON)
	GameState.set_guardian("disco_sprout:0")
	GameState.add_gear("spring_boots")
	GameState.add_silver(500)
	ShopState.add_gold(500)

	# Без фиксированного зерна поляны выпадают случайно, а вместе с ними
	# и набор кнопок: прогон к прогону число проверок гуляло, и падение
	# ниже прежнего было бы неотличимо от невезения
	RunManager.set_seed(7)


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
		# Кнопка, укатившаяся за край прокрутки, кликов не получает и от Godot:
		# ScrollContainer режет и рисование, и ввод. Такая кнопка не выглядит
		# нажимаемой, а значит и к этому классу багов не относится — её просто
		# надо домотать. Без этой оговорки тест ругался на каждый длинный
		# список, стоило добавить в него пару строк
		if _clipped_away(button):
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


## Скрыта ли кнопка обрезкой родителя-прокрутки.
##
## Проверяется ЦЕНТР: наполовину выехавшая кнопка остаётся нажимаемой
## и по-прежнему обязана быть доступной, а вот уехавшая целиком — нет.
func _clipped_away(button: Button) -> bool:
	var point := button.get_global_rect().get_center()
	var parent := button.get_parent()
	while parent != null:
		if parent is Control and (parent is ScrollContainer or parent.clip_contents):
			if not (parent as Control).get_global_rect().has_point(point):
				return true
		parent = parent.get_parent()
	return false


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
	var flat: Array[Control] = []
	_walk_controls(node, flat)

	# Сортируем по СЛОЮ, а не только по порядку в дереве.
	#
	# Godot разбирает ввод по CanvasLayer: слой с бо́льшим номером получает
	# клик первым, независимо от того, где узел лежит в дереве. Пока модель
	# этого не знала, тест считал панель победы доступной — а на живом экране
	# её накрывала сцена боя со своим слоем, и кнопка «Угостить» не нажималась.
	# Сортировка устойчивая, поэтому внутри одного слоя порядок дерева цел.
	var indexed: Array = []
	for i in flat.size():
		indexed.append([_layer_of(flat[i]), i, flat[i]])
	indexed.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])

	for entry: Array in indexed:
		out.append(entry[2])


func _walk_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_walk_controls(child, out)


## На каком слое рисуется узел. Вне CanvasLayer это нулевой слой сцены.
func _layer_of(node: Node) -> int:
	var parent := node.get_parent()
	while parent != null:
		if parent is CanvasLayer:
			return (parent as CanvasLayer).layer
		parent = parent.get_parent()
	return 0


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
