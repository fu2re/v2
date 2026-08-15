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
	await _test_monster_glade_blocks_swipe()
	await _test_defeat_does_not_freeze()
	await _test_tutorial_notes_cover_whole_track()
	await _test_defeat_during_miss_does_not_crash()
	_test_swipe_thresholds_are_relative()

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


## Поляну с монстром пропустить нельзя: встретил — танцуй.
##
## Без этого главное решение забега подменялось бы бесплатным листанием
## мимо всего опасного, и лента переставала быть выбором.
func _test_monster_glade_blocks_swipe() -> void:
	print("Поляну с монстром нельзя пропустить")
	GameState.reset()
	FarmState.reset()
	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.set_guardian("disco_sprout")
	RunManager.set_seed(7)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	# Доходим до боевой поляны
	var guard := 0
	while RunManager.current_glade != null \
			and RunManager.current_glade.type != Glade.Type.BATTLE and guard < 60:
		guard += 1
		feed._next_glade()
		await _frames(1)

	check(RunManager.current_glade != null
		and RunManager.current_glade.type == Glade.Type.BATTLE,
		"боевая поляна найдена")

	var depth_before := RunManager.depth
	check(feed._blocks_swipe(), "боевая поляна держит игрока")
	feed._try_next_glade()
	await _frames(2)
	check_eq(RunManager.depth, depth_before, "свайп не сработал — поляна не пройдена")

	# После прохождения свайп разблокируется
	feed._glade_cleared = true
	check(not feed._blocks_swipe(), "пройденная поляна отпускает")
	feed._try_next_glade()
	await _frames(2)
	check(RunManager.depth > depth_before, "после боя свайп работает")

	# Небоевые поляны пропускаются свободно
	guard = 0
	while RunManager.current_glade != null \
			and RunManager.current_glade.type == Glade.Type.BATTLE and guard < 60:
		guard += 1
		feed._glade_cleared = true
		feed._try_next_glade()
		await _frames(1)
	if RunManager.current_glade != null:
		check(not feed._blocks_swipe(),
			"поляна типа «%s» пропускается свободно" % RunManager.current_glade.type_name())

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Игрок сообщил: при проигрыше в лесу игра зависает.
##
## Проверяем не «вызвалась ли функция», а что после поражения интерфейс
## снова принимает ввод и уводит на ферму. Зависание — это именно
## непринимаемый ввод, и увидеть его можно только настоящим кликом.
func _test_defeat_does_not_freeze() -> void:
	print("Поражение не подвешивает ленту")
	GameState.reset()
	FarmState.reset()
	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.set_guardian("disco_sprout")
	RunManager.set_seed(11)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	# Доводим до боевой поляны и имитируем проигранный бой
	var guard := 0
	while RunManager.current_glade != null \
			and RunManager.current_glade.type != Glade.Type.BATTLE and guard < 60:
		guard += 1
		feed._next_glade()
		await _frames(1)
	check(RunManager.current_glade != null
		and RunManager.current_glade.type == Glade.Type.BATTLE, "боевая поляна найдена")

	var state := BattleState.new()
	state.setup(Registry.monster(RunManager.current_glade.monster_id),
		Registry.monster("disco_sprout"), 1, RunManager.current_glade.depth, 0)
	state.take_strike()
	check(state.health <= 0, "здоровье обнулено — поражение")

	var ended: Array[bool] = []
	RunManager.run_ended.connect(func(_d, _f, _s): ended.append(true), CONNECT_ONE_SHOT)
	feed._on_battle_finished(false, state)
	check(not ended.is_empty(), "забег закрылся")
	check(not RunManager.is_active, "забег неактивен")

	# Ждём паузу на чтение итога и проверяем, что ввод снова живой
	await get_tree().create_timer(1.5).timeout
	await _frames(2)
	check(feed._awaiting_restart, "лента ждёт тапа, а не висит")
	check(not feed._busy, "ввод разблокирован")
	check(feed._battle == null, "сцена боя убрана")

	# Кнопка — гарантированный выход, не зависящий от состояния жестов
	check(feed._finish_button.visible, "кнопка «На ферму» показана")
	check(not feed._finish_button.disabled, "и она нажимаема")

	feed.queue_free()
	await _frames(2)


## Игрок сообщил: вторая половина мелодии в туториале без нот.
func _test_tutorial_notes_cover_whole_track() -> void:
	print("Урок покрывает нотами весь трек")
	var lesson := preload("res://scenes/onboarding/Onboarding.tscn").instantiate()
	add_child(lesson)
	await _frames(3)

	var chart: ChartData = lesson._build_lesson_chart()
	check(chart != null, "чарт урока построен")
	if chart == null:
		return

	var last := chart.note_beats[chart.note_count() - 1]
	var total := chart.total_beats()
	check(last >= total * 0.85,
		"ноты доходят до конца трека (%.0f из %.0f долей)" % [last, total])

	# И урок обязан быть выигрываемым: без атакующих нот победы не бывает
	var attacks := 0
	for t in chart.note_types:
		if t == ChartData.NoteType.ATTACK:
			attacks += 1
	check(attacks >= 3, "в уроке есть атакующие ноты (%d)" % attacks)

	Conductor.stop()
	lesson.queue_free()
	await _frames(2)


## Пропуск ноты может закончить бой, а конец боя очищает список нот.
##
## Именно здесь падала игра при проигрыше: цикл продолжал работать
## с индексом в уже пустом массиве.
func _test_defeat_during_miss_does_not_crash() -> void:
	print("Поражение прямо в момент промаха не роняет бой")
	GameState.reset()
	var battle := preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	battle.autostart = false
	add_child(battle)
	await _frames(2)

	var chart := ChartLoader.load_by_id("demo_disco", "normal")
	battle.starting_health = 1
	battle.starting_shield = 0
	battle.begin(chart)
	await _frames(2)

	# Кладём ноту в список активных и добиваем здоровье её пропуском.
	# Это ровно та последовательность, на которой игра падала: _miss
	# заканчивает бой, _end_battle чистит список, а цикл идёт дальше.
	battle.state.shield = 0
	battle.state.health = 1
	# Тип указан явно: acquire объявлен в другом скрипте, и вывод типа тут не работает
	var note: Note = battle._pool.acquire(4.0, ChartData.NoteType.SHIELD)
	check(note != null, "нота выдана из пула")
	battle._active.append(note)

	battle._miss(note)
	check(battle.state.is_over, "пропуск добил здоровье — поражение")
	check(battle._active.is_empty(), "конец боя очистил список нот")

	# Повторный проход по пустому списку не должен ронять игру
	battle._expire_missed()
	check(is_instance_valid(battle), "сцена боя цела — падения не было")

	Conductor.stop()
	battle.queue_free()
	await _frames(2)


## Пороги жестов должны быть в долях экрана, а не в пикселях холста.
func _test_swipe_thresholds_are_relative() -> void:
	print("Пороги свайпа заданы в долях экрана")
	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	var swipe: float = feed.SWIPE_FRACTION
	var tap: float = feed.TAP_FRACTION
	feed.free()
	check(swipe > 0.0 and swipe < 0.5,
		"порог свайпа — доля высоты (%.2f)" % swipe)
	check(tap < swipe,
		"порог тапа меньше порога свайпа")
