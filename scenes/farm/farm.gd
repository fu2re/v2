extends Node2D

## Ферма — база между забегами.
##
## Здесь замыкается контур игры (GDD §7.3): в лесу находишь дикие семена,
## на ферме растишь фрукты, фруктами приручаешь монстров, с монстрами идёшь
## глубже в лес. Ни одно звено не работает в одиночку.

const PLOT_COLS := 4
const PLOT_SIZE := 200.0
const PLOT_GAP := 24.0
const GRID_TOP := 780.0

var _plot_buttons: Array[Button] = []
var _status: Label = null
var _seeds_label: Label = null
var _grid: Control = null
var _dance: CanvasLayer = null
var _seed_picker: VBoxContainer = null
var _picker_bg: ColorRect = null
var _guardian_label: Label = null
var _pending_plot := -1


func _ready() -> void:
	_build_ui()

	_dance = preload("res://scenes/farm/PlantDance.tscn").instantiate()
	add_child(_dance)
	_dance.finished.connect(_on_dance_finished)

	FarmState.plots_changed.connect(_refresh)
	FarmState.silver_changed.connect(_refresh)
	GameState.silver_changed.connect(func(_v): _refresh())

	_refresh()


func _process(_delta: float) -> void:
	FarmState.tick()


func _refresh() -> void:
	_sync_grid()
	_seeds_label.text = "Серебро %d    Золото %d    Семян %d" % [
		GameState.silver, ShopState.gold, _total_seeds(),
	]

	var guardian := Registry.monster(GameState.guardian_id())
	_guardian_label.text = "В лес пойдёт: %s" % guardian.display_name if guardian != null \
		else "Гуардиан не выбран"


func _total_seeds() -> int:
	var total := 0
	for fruit_id in FarmState.available_seeds():
		total += FarmState.seed_count(fruit_id)
	return total


## Убрать детей ПРЯМО СЕЙЧАС, а не в конце кадра.
##
## queue_free() отложен: узел остаётся в дереве до конца кадра, продолжает
## занимать место в контейнере и ловить ввод. Из-за этого список семян
## накапливал старые кнопки, а новые уезжали вниз за край панели.
func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Обновить грядки, НЕ пересоздавая кнопки без нужды.
##
## Пока что-то растёт, FarmState.tick() шлёт plots_changed каждый кадр.
## Полная пересборка на каждый сигнал уничтожала кнопку между нажатием
## и отпусканием, и `pressed` не успевал сработать — ферма выглядела
## мёртвой сразу после первой посадки.
func _sync_grid() -> void:
	if _plot_buttons.size() != FarmState.plot_count():
		_rebuild_grid()
		return
	for i in _plot_buttons.size():
		# Присваиваем только при изменении: пока грядка растёт, сюда
		# заходят каждый кадр, а установка текста дёргает раскладку
		var label := _plot_label(i)
		if _plot_buttons[i].text != label:
			_plot_buttons[i].text = label


func _rebuild_grid() -> void:
	for button in _plot_buttons:
		if is_instance_valid(button):
			_grid.remove_child(button)
			button.queue_free()
	_plot_buttons.clear()

	for i in FarmState.plot_count():
		var button := Button.new()
		var col := i % PLOT_COLS
		var row := i / PLOT_COLS
		button.position = Vector2(
			60.0 + col * (PLOT_SIZE + PLOT_GAP),
			GRID_TOP + row * (PLOT_SIZE + PLOT_GAP),
		)
		button.size = Vector2(PLOT_SIZE, PLOT_SIZE)
		button.add_theme_font_size_override("font_size", 26)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.text = _plot_label(i)
		button.pressed.connect(_on_plot_pressed.bind(i))
		_grid.add_child(button)
		_plot_buttons.append(button)


func _plot_label(index: int) -> String:
	if FarmState.is_empty_plot(index):
		return "Пусто\n\nПосадить"
	var fruit := Registry.fruit(FarmState.plots[index].seed_id)
	var name := fruit.display_name if fruit != null else "?"

	if FarmState.is_ready(index):
		return "%s\n\nСОБРАТЬ" % name

	var percent := int(round(FarmState.growth_ratio(index) * 100.0))
	var left := _format_time(FarmState.seconds_left(index))
	var dance_hint := "\n♪ станцевать" if FarmState.can_dance(index) else ""
	return "%s\n%d%%\n%s%s" % [name, percent, left, dance_hint]


func _format_time(seconds: float) -> String:
	var total := int(ceil(seconds))
	if total >= 3600:
		return "%d ч %d мин" % [total / 3600, (total % 3600) / 60]
	if total >= 60:
		return "%d мин" % [total / 60]
	return "%d сек" % total


func _on_plot_pressed(index: int) -> void:
	if FarmState.is_ready(index):
		var fruit_id := FarmState.harvest(index)
		var fruit := Registry.fruit(fruit_id)
		_status.text = "Собрано: %s" % (fruit.display_name if fruit != null else fruit_id)
		return

	if FarmState.is_empty_plot(index):
		_open_seed_picker(index)
		return

	if FarmState.can_dance(index):
		var fruit := Registry.fruit(FarmState.plots[index].seed_id)
		_pending_plot = index
		_dance.start(fruit.display_name if fruit != null else "растения")
		return

	_status.text = "Уже растёт. Загляни позже — урожай не пропадёт."


func _open_seed_picker(index: int) -> void:
	var available := FarmState.available_seeds()
	if available.is_empty():
		_status.text = "Семян нет. Ищи дикие кусты в лесу."
		return

	_pending_plot = index
	_clear(_seed_picker)

	for fruit_id in available:
		var fruit := Registry.fruit(fruit_id)
		var button := Button.new()
		button.text = "%s x%d   (%s)" % [
			fruit.display_name if fruit != null else fruit_id,
			FarmState.seed_count(fruit_id),
			_format_time(float(fruit.grow_seconds())) if fruit != null else "?",
		]
		button.custom_minimum_size = Vector2(0, 100)
		button.add_theme_font_size_override("font_size", 36)
		button.pressed.connect(_plant_selected.bind(fruit_id))
		_seed_picker.add_child(button)

	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.custom_minimum_size = Vector2(0, 100)
	cancel.add_theme_font_size_override("font_size", 36)
	cancel.pressed.connect(_close_seed_picker)
	_seed_picker.add_child(cancel)

	_seed_picker.visible = true


func _plant_selected(fruit_id: String) -> void:
	if FarmState.plant(_pending_plot, fruit_id):
		var fruit := Registry.fruit(fruit_id)
		_status.text = "Посажено: %s. Можно станцевать, чтобы росло быстрее." \
			% (fruit.display_name if fruit != null else fruit_id)
	_close_seed_picker()


func _close_seed_picker() -> void:
	_seed_picker.visible = false
	_pending_plot = -1


func _on_dance_finished(level: DanceGrade.Level) -> void:
	if _pending_plot >= 0:
		FarmState.apply_dance(_pending_plot, level)
		_status.text = "%s Растение потянулось вверх." % DanceGrade.level_name(level)
	_pending_plot = -1
	_refresh()


func _go_to_forest() -> void:
	if GameState.guardian_id().is_empty():
		_status.text = "Некого взять в лес. Сначала подружись с кем-нибудь."
		return
	get_tree().change_scene_to_file("res://scenes/run/RunFeed.tscn")


func _go_to_collection() -> void:
	get_tree().change_scene_to_file("res://scenes/collection/Collection.tscn")


func _go_to_shop() -> void:
	get_tree().change_scene_to_file("res://scenes/shop/Shop.tscn")


func _go_to_inventory() -> void:
	get_tree().change_scene_to_file("res://scenes/inventory/Inventory.tscn")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("446A31")
	add_child(bg)

	var title := Label.new()
	title.position = Vector2(60, 100)
	title.size = Vector2(960, 100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("DCC7A4"))
	title.text = "Твой огород"
	add_child(title)

	_seeds_label = Label.new()
	_seeds_label.position = Vector2(60, 210)
	_seeds_label.size = Vector2(960, 60)
	_seeds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seeds_label.add_theme_font_size_override("font_size", 38)
	_seeds_label.add_theme_color_override("font_color", Color("F0DEC0"))
	add_child(_seeds_label)

	_status = Label.new()
	_status.position = Vector2(60, 290)
	_status.size = Vector2(960, 140)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 34)
	_status.add_theme_color_override("font_color", Color("DCC7A4"))
	add_child(_status)

	# Три входа с фермы: друзья, лавка, лес
	var nav := [
		["Друзья", Vector2(60, 460), _go_to_collection],
		["Сумка", Vector2(310, 460), _go_to_inventory],
		["Лавка", Vector2(560, 460), _go_to_shop],
		["В лес", Vector2(810, 460), _go_to_forest],
	]
	for entry: Array in nav:
		var button := Button.new()
		button.text = entry[0]
		button.position = entry[1]
		button.size = Vector2(210, 130)
		button.add_theme_font_size_override("font_size", 42)
		button.pressed.connect(entry[2])
		add_child(button)

	_guardian_label = Label.new()
	_guardian_label.position = Vector2(60, 620)
	_guardian_label.size = Vector2(960, 60)
	_guardian_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guardian_label.add_theme_font_size_override("font_size", 34)
	_guardian_label.add_theme_color_override("font_color", Color("F0DEC0"))
	add_child(_guardian_label)

	_grid = Control.new()
	_grid.size = Vector2(1080, 1000)
	# Обёртка для кнопок грядок не должна ловить ввод сама.
	# У Control по умолчанию mouse_filter = STOP, и пустой контейнер
	# во весь экран молча съедал клики по кнопкам навигации под ним
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)

	# Подложка под выбор семян: без неё панель висит поверх живого экрана,
	# кнопки под ней видно, но они не нажимаются — читается как поломка
	_picker_bg = UIUtil.make_backdrop(Color(0.14, 0.22, 0.12, 0.96))
	_picker_bg.visible = false
	add_child(_picker_bg)

	_seed_picker = VBoxContainer.new()
	_seed_picker.position = Vector2(90, 400)
	_seed_picker.size = Vector2(900, 1100)
	_seed_picker.add_theme_constant_override("separation", 20)
	_seed_picker.visible = false
	_seed_picker.visibility_changed.connect(
		func(): _picker_bg.visible = _seed_picker.visible)
	add_child(_seed_picker)
