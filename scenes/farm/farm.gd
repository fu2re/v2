extends Node2D

## Ферма — база между забегами.
##
## Здесь замыкается контур игры (GDD §7.3): в лесу находишь дикие семена,
## на ферме растишь фрукты, фруктами приручаешь монстров, с монстрами идёшь
## глубже в лес. Ни одно звено не работает в одиночку.

## Сетка грядок. Размер клетки задан не «на глаз»: в неё должны поместиться
## название фрукта, процент, оставшееся время и значок — при 226 пикселях
## и кегле 24 самая длинная строка («Золотое яблоко») переносится на две
## и не вылезает за край. При 200 вылезала, и слово «станцевать»
## обрывалось на середине.
const PLOT_COLS := 4
const PLOT_SIZE := 226.0
const PLOT_GAP := 20.0
## Сетка лежит НА нарисованных грядках, а не над ними в воздухе.
const GRID_TOP := 820.0
const GRID_LEFT := 58.0

## Раскладка живёт в Farm.tscn и правится в инспекторе (GDD §13.2.1).
## Скрипт только связывает узлы с логикой.
@onready var _status: Label = $Status
@onready var _seeds_label: Label = $SeedsLabel
@onready var _grid: Control = $PlotGrid
@onready var _seed_picker: VBoxContainer = $SeedPicker
@onready var _picker_bg: ColorRect = $PickerBackdrop
@onready var _guardian_label: Label = $GuardianLabel

var _plot_buttons: Array[Button] = []
var _dance: CanvasLayer = null
var _pending_plot := -1


func _ready() -> void:
	# Навигация теперь во дворе усадьбы: отсюда есть только путь обратно.
	# Раньше каждый экран знал про все остальные, и «назад» означало разное
	# в зависимости от того, откуда пришёл
	$BackButton.pressed.connect(_go_to_lobby)

	Jukebox.play_screen("farm")
	UIUtil.set_screen_background($Scenery, "res://art/screen/screen_farm.png")

	# Подложка гаснет вместе с панелью: без неё панель висит поверх
	# живого экрана, кнопки под ней видно, но нажать нельзя
	_seed_picker.visibility_changed.connect(
		func(): _picker_bg.visible = _seed_picker.visible)

	_dance = preload("res://scenes/farm/PlantDance.tscn").instantiate()
	add_child(_dance)
	_dance.finished.connect(_on_dance_finished)

	FarmState.plots_changed.connect(_refresh)
	FarmState.seeds_changed.connect(_refresh)
	GameState.silver_changed.connect(func(_v): _refresh())

	_refresh()


func _process(_delta: float) -> void:
	FarmState.tick()


func _refresh() -> void:
	_sync_grid()
	_seeds_label.text = "Серебро %d    Золото %d    Семян %d" % [
		GameState.silver, ShopState.gold, _total_seeds(),
	]

	var guardian := GameState.guardian()
	if guardian == null:
		_guardian_label.text = "Гуардиан не выбран"
	else:
		var grade_mark := "" if guardian.grade == MonsterData.Rarity.COMMON \
			else " · %s" % guardian.grade_name()
		_guardian_label.text = "В лес пойдёт: %s%s (ур.%d)" % [
			guardian.display_name(), grade_mark, guardian.level,
		]


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
		var icon := _plot_icon(i)
		if _plot_buttons[i].icon != icon:
			_plot_buttons[i].icon = icon


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
			GRID_LEFT + col * (PLOT_SIZE + PLOT_GAP),
			GRID_TOP + row * (PLOT_SIZE + PLOT_GAP),
		)
		button.size = Vector2(PLOT_SIZE, PLOT_SIZE)
		button.add_theme_font_size_override("font_size", 24)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Картинка фрукта над подписью: ребёнок 7 лет узнаёт грядку по ягоде
		# быстрее, чем прочитает её название (GDD §2.3)
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.icon = _plot_icon(i)
		button.text = _plot_label(i)
		button.pressed.connect(_on_plot_pressed.bind(i))
		_grid.add_child(button)
		_plot_buttons.append(button)


## Картинка в клетке. Пусто — картинки нет: пустая грядка и должна выглядеть
## пустой, подставлять туда что-то значило бы соврать.
func _plot_icon(index: int) -> Texture2D:
	if FarmState.is_empty_plot(index):
		return null
	var fruit := Registry.fruit(FarmState.plots[index].seed_id)
	return fruit.sprite() if fruit != null else null


## Подпись в клетке. Коротко: клетка 226 пикселей, и всё, что длиннее двух
## слов, переносится и вылезает за край. Название фрукта уже сказано
## картинкой, поэтому в тексте остаётся только состояние.
func _plot_label(index: int) -> String:
	if FarmState.is_empty_plot(index):
		return "Посадить"

	if FarmState.is_ready(index):
		return "СОБРАТЬ"

	var percent := int(round(FarmState.growth_ratio(index) * 100.0))
	var left := _format_time(FarmState.seconds_left(index))
	# Значок ноты вместо слова «станцевать»: слово не влезает, а нота
	# уже означает танец на всех остальных экранах
	var dance_hint := "  ♪" if FarmState.can_dance(index) else ""
	return "%d%%\n%s%s" % [percent, left, dance_hint]


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


func _go_to_lobby() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)

