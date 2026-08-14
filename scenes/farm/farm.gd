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
var _guardian_label: Label = null
var _pending_plot := -1


func _ready() -> void:
	_build_ui()

	_dance = preload("res://scenes/farm/PlantDance.tscn").instantiate()
	add_child(_dance)
	_dance.finished.connect(_on_dance_finished)

	FarmState.plots_changed.connect(_refresh)
	FarmState.seeds_changed.connect(_refresh)
	GameState.seeds_changed.connect(func(_v): _refresh())

	_refresh()


func _process(_delta: float) -> void:
	FarmState.tick()


func _refresh() -> void:
	_rebuild_grid()
	_seeds_label.text = "Семечки: %d      Семена: %d" % [
		GameState.seeds, _total_seeds(),
	]

	var guardian := Registry.monster(GameState.guardian_id())
	_guardian_label.text = "В лес пойдёт: %s" % guardian.display_name if guardian != null \
		else "Гуардиан не выбран"


func _total_seeds() -> int:
	var total := 0
	for fruit_id in FarmState.available_seeds():
		total += FarmState.seed_count(fruit_id)
	return total


func _rebuild_grid() -> void:
	for button in _plot_buttons:
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
	for child in _seed_picker.get_children():
		child.queue_free()

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

	var collection := Button.new()
	collection.text = "Друзья"
	collection.position = Vector2(90, 460)
	collection.size = Vector2(420, 130)
	collection.add_theme_font_size_override("font_size", 46)
	collection.pressed.connect(_go_to_collection)
	add_child(collection)

	var forest := Button.new()
	forest.text = "В лес"
	forest.position = Vector2(570, 460)
	forest.size = Vector2(420, 130)
	forest.add_theme_font_size_override("font_size", 46)
	forest.pressed.connect(_go_to_forest)
	add_child(forest)

	_guardian_label = Label.new()
	_guardian_label.position = Vector2(60, 620)
	_guardian_label.size = Vector2(960, 60)
	_guardian_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guardian_label.add_theme_font_size_override("font_size", 34)
	_guardian_label.add_theme_color_override("font_color", Color("F0DEC0"))
	add_child(_guardian_label)

	_grid = Control.new()
	_grid.size = Vector2(1080, 1000)
	add_child(_grid)

	_seed_picker = VBoxContainer.new()
	_seed_picker.position = Vector2(90, 500)
	_seed_picker.size = Vector2(900, 900)
	_seed_picker.add_theme_constant_override("separation", 20)
	_seed_picker.visible = false
	add_child(_seed_picker)
