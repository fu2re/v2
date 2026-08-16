extends Node2D

## Коллекция: кто уже друг, кто на подходе, кого берём в лес.
##
## Карточка — на ЭКЗЕМПЛЯР, а не на вид (GDD §6.3): обычный и редкий Ростик
## живут отдельными строками, у каждого свой уровень и своё снаряжение.
##
## Показываются и те, с кем ещё не подружились: у каждой пары «вид + грейд»
## своя шкала (GDD §6.1), и видеть, что до нового друга осталось три встречи,
## важнее, чем любоваться теми, кто уже есть. Но перечислять все шесть грейдов
## каждого вида нельзя — это стена из полосок; показываем приручённых
## и по одной строке «на подходе» для того грейда, к которому игрок ближе всего.

const CARD_HEIGHT := 290.0

## Клетка витрины. Шесть в ряд при ширине списка 960 и зазоре 8:
## 6×150 + 5×8 = 940 — влезает с запасом на полосу прокрутки.
const CELL_SIZE := 150.0
const CELL_GAP := 8

## Раскладка живёт в Collection.tscn и правится в инспекторе (GDD §13.2.1).
@onready var _list: VBoxContainer = $ListScroll/List
@onready var _status: Label = $Status
@onready var _gear_panel: VBoxContainer = $GearPanel

## Ключ экземпляра, которому сейчас подбирают снаряжение.
var _selected_key: String = ""


func _ready() -> void:
	$BackButton.pressed.connect(_go_back)
	Jukebox.play_screen("collection")
	UIUtil.set_screen_background($Scenery, "res://art/screen/screen_guardians.png")
	# Подложка гаснет вместе с панелью: иначе панель висит поверх живого
	# экрана, кнопки под ней видно, но нажать нельзя
	var backdrop: ColorRect = $GearBackdrop
	_gear_panel.visibility_changed.connect(
		func(): backdrop.visible = _gear_panel.visible)

	GameState.gear_changed.connect(_on_gear_changed)
	GameState.guardian_changed.connect(func(_id): _refresh())
	_refresh()


## Снаряжение сменилось — перестроить и список, и ОТКРЫТУЮ панель.
##
## Раньше сигнал обновлял только список за панелью, а сама панель оставалась
## той, что построили при открытии: игрок надевал пояс и не видел никакой
## разницы, пока не выходил и не заходил снова. Пересборка здесь безопасна —
## сигнал приходит по факту смены, а не каждый кадр (CLAUDE.md).
func _on_gear_changed() -> void:
	_refresh()
	if _gear_panel.visible and not _selected_key.is_empty():
		_open_gear(_selected_key)


## Витрина: строка на вид, колонка на грейд (GDD §7.5).
##
## Раньше здесь был список приручённых плюс отдельные карточки прогресса,
## и увидеть КОЛЛЕКЦИЮ как целое было нельзя: сколько всего существ в игре,
## что уже открыто, чего не хватает. Таблица отвечает на это одним взглядом,
## а закрытые клетки-силуэты показывают, что впереди ещё есть что искать.
func _refresh() -> void:
	UIUtil.clear_children(_list)

	var progress := GameState.collection_progress()
	_status.text = "Открыто %d из %d" % [progress.x, progress.y]

	for species in Registry.all_monsters():
		_list.add_child(_make_species_row(species))


## Одна строка витрины: имя вида и шесть клеток грейдов слева направо.
func _make_species_row(species: MonsterData) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Имя вида — только если хоть один грейд открыт. Иначе коллекция
	# рассказывала бы содержание вперёд игрока
	var any_open := false
	for grade in range(MonsterData.Rarity.size()):
		if GameState.is_met(species.id, grade):
			any_open = true
			break

	var title := Label.new()
	title.text = species.display_name if any_open else "? ? ?"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color",
		Color("F0DEC0") if any_open else Color("6B6862"))
	row.add_child(title)

	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", CELL_GAP)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for grade in range(MonsterData.Rarity.size()):
		cells.add_child(_make_cell(species, grade))
	row.add_child(cells)
	return row


## Клетка коллекции: спрайт грейда, рамка у приручённого, силуэт у закрытого.
func _make_cell(species: MonsterData, grade: int) -> Control:
	var state := CollectionGrid.state_for(species.id, grade)

	var cell := Button.new()
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	cell.icon = species.sprite_for_grade(grade)
	cell.expand_icon = true
	cell.text = ""
	# Красим ТОЛЬКО картинку, а не всю кнопку: `modulate` гасил вместе
	# со спрайтом и саму клетку, и чёрный силуэт на почерневшей клетке
	# переставал читаться — вместо загадки получалось пустое место.
	# Раскраска — правило игры, а не рисование, и живёт в CollectionGrid
	cell.add_theme_color_override("icon_normal_color",
		CollectionGrid.tint_for(state))
	cell.add_theme_color_override("icon_disabled_color",
		CollectionGrid.tint_for(state))
	cell.tooltip_text = CollectionGrid.caption_for(species.id, grade)

	if state == CollectionGrid.Cell.TAMED:
		# Рамка отвечает на один вопрос — «мой или нет». Грейд и без неё
		# виден по колонке, поэтому цвет рамки один на все грейды
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color(0.153, 0.114, 0.078, 0.92)
		frame.set_border_width_all(6)
		frame.border_color = CollectionGrid.TAMED_FRAME
		frame.set_corner_radius_all(18)
		cell.add_theme_stylebox_override("normal", frame)

	if CollectionGrid.opens_card(species.id, grade):
		cell.pressed.connect(_open_card.bind(species.id, grade))
	else:
		# По закрытой клетке смотреть нечего: молчаливое нажатие честнее
		# пустой карточки
		cell.disabled = true
	return cell


## Угостить друга: фрукт превращается в опыт (GDD §6.5).
##
## Кормление держит ферму в петле после того, как вид приручён: раньше
## фрукты становились не нужны в тот же миг, когда шкала дружбы упиралась
## в потолок, и половина игры выпадала из смысла.
func _open_feed(instance_key: String) -> void:
	_selected_key = instance_key
	UIUtil.clear_children(_gear_panel)

	var friend := GameState.instance(instance_key)
	if friend == null:
		return

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 44)
	header.add_theme_color_override("font_color", Color("F0DEC0"))
	header.text = "Чем угостить: %s" % friend.display_name()
	_gear_panel.add_child(header)

	var xp := friend.xp_progress()
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 30)
	status.add_theme_color_override("font_color", Color("DCC7A4"))
	status.text = "Уровень %d · опыт %d/%d" % [friend.level, xp.x, xp.y]
	_gear_panel.add_child(status)

	var species := friend.data()
	var favorite_id := species.favorite_fruit_id if species != null else ""

	var any := false
	for fruit in Registry.all_fruits():
		for quality in [FruitData.Quality.PERFECT, FruitData.Quality.JUICY,
				FruitData.Quality.PLAIN]:
			var count := GameState.fruit_count(fruit.id, quality)
			if count <= 0:
				continue
			any = true
			var gain := GameState.feeding_xp(friend.species_id, fruit.id, quality)
			var mark := "  ★" if fruit.id == favorite_id else ""
			_add_gear_button("%s (%s) x%d   +%d опыта%s" % [
					fruit.display_name, FruitData.quality_name(quality),
					count, gain, mark],
				_feed_friend.bind(instance_key, fruit.id, quality))

	if not any:
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color("ADA99F"))
		empty.text = "Угощать нечем — вырасти что-нибудь на грядке."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_gear_panel.add_child(empty)

	_add_gear_button("Закрыть", _close_gear)
	_gear_panel.visible = true


func _feed_friend(instance_key: String, fruit_id: String,
		quality: FruitData.Quality) -> void:
	if GameState.feed(instance_key, fruit_id, quality) <= 0:
		return
	SaveManager.mark_dirty()
	# Панель пересобирается ЦЕЛИКОМ и только по нажатию игрока, а не из
	# _process: иначе кнопка исчезала бы между нажатием и отпусканием
	_open_feed(instance_key)
	_refresh()



## Экран экипировки: три слота сверху, сундук снизу.
##
## Раньше это был сплошной список, где надетое и лежащее в сундуке шли
## вперемешку и отличались только словом «Снять». Понять, что на ком надето,
## было нельзя. Теперь слоты — это ячейки: видно, что занято, что пусто
## и что вообще подходит.
func _open_gear(instance_key: String) -> void:
	_selected_key = instance_key
	UIUtil.clear_children(_gear_panel)

	var friend := GameState.instance(instance_key)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 44)
	header.add_theme_color_override("font_color", Color("F0DEC0"))
	# Снаряжение носит конкретный экземпляр, поэтому в шапке грейд и уровень:
	# иначе непонятно, кому из двух Ростиков надевают пояс
	header.text = "%s · %s · ур.%d" % [
		friend.display_name(), friend.grade_name(), friend.level,
	] if friend != null else instance_key
	_gear_panel.add_child(header)

	# Три ячейки слотов в ряд — как на персонаже
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 16)
	_gear_panel.add_child(slots)
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		slots.add_child(_make_slot_cell(instance_key, slot))

	# Сводка эффектов: игрок должен видеть, что даёт весь комплект целиком
	var bonuses := GameState.gear_bonuses(instance_key)
	var summary := Label.new()
	summary.add_theme_font_size_override("font_size", 28)
	summary.add_theme_color_override("font_color", Color("1ED8FF"))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = "Вместе: окно ×%.2f · удар +%.1f · здоровье +%d · защита +%d%%" % [
		bonuses.window_scale, bonuses.power_bonus, bonuses.health_bonus,
		int(round(bonuses.shield_reduction * 100.0)),
	]
	_gear_panel.add_child(summary)

	var chest := Label.new()
	chest.add_theme_font_size_override("font_size", 34)
	chest.add_theme_color_override("font_color", Color("DCC7A4"))
	chest.text = "Сундук"
	_gear_panel.add_child(chest)

	var owned := GameState.owned_gear_ids()
	if owned.is_empty():
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", 28)
		empty.add_theme_color_override("font_color", Color("ADA99F"))
		empty.text = "Пусто. Снаряжение выпадает за победу и продаётся у торговца."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_gear_panel.add_child(empty)

	for gear_id in owned:
		var item := Registry.gear(gear_id)
		if item == null:
			continue
		_add_gear_button("%s ×%d\n%s · %s" % [
				item.display_name, GameState.gear_count(gear_id),
				GearData.slot_name(item.slot), item.effect_text()],
			func(): GameState.equip(instance_key, gear_id))

	_add_gear_button("Закрыть", _close_gear)
	_gear_panel.visible = true


## Ячейка одного слота: что надето, что слот делает, как снять.
func _make_slot_cell(instance_key: String, slot: GearData.Slot) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(300, 200)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	cell.add_child(box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("F0DEC0"))
	title.text = GearData.slot_name(slot)
	box.add_child(title)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color("ADA99F"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = GearData.slot_hint(slot)
	box.add_child(hint)

	var item := GameState.equipped_gear(instance_key, slot)
	var worn := Label.new()
	worn.add_theme_font_size_override("font_size", 26)
	worn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if item != null:
		worn.text = item.display_name
		worn.add_theme_color_override("font_color", MonsterData.rarity_color(item.rarity))
	else:
		worn.text = "— пусто —"
		worn.add_theme_color_override("font_color", Color("6B6862"))
	box.add_child(worn)

	if item != null:
		var take_off := Button.new()
		take_off.text = "Снять"
		take_off.custom_minimum_size = Vector2(0, 116)
		take_off.add_theme_font_size_override("font_size", 24)
		take_off.pressed.connect(func(): GameState.unequip(instance_key, slot))
		box.add_child(take_off)

	return cell


func _add_gear_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 116)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(callback)
	_gear_panel.add_child(button)


func _close_gear() -> void:
	_gear_panel.visible = false
	_selected_key = ""


func _go_back() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)


## Карточка существа: характеристики, а не только картинка.
##
## Это ответ на «нигде не видно характеристик защитника». До неё игрок знал
## о своём монстре ровно две вещи — имя и уровень, — и не мог сравнить двух
## кандидатов перед забегом. Числа берутся у того же `MonsterInstance`,
## что дерётся в бою, поэтому карточка не может разойтись с боем.
func _open_card(species_id: String, grade: int) -> void:
	var species := Registry.monster(species_id)
	if species == null:
		return

	_selected_key = MonsterInstance.key_for(species_id, grade)
	UIUtil.clear_children(_gear_panel)

	var tamed := GameState.instance(_selected_key)
	# У неприручённого статы считаются по тем же правилам — игрок должен
	# видеть, за кем идёт, ещё до того, как тот согласится
	var shown := tamed if tamed != null else MonsterInstance.create(species_id, grade)

	_card_title(shown, tamed != null)
	_card_portrait(species, grade)
	_card_stats(shown, tamed)
	_card_actions(tamed)

	_add_gear_button("Закрыть", _close_gear)
	_gear_panel.visible = true


func _card_title(shown: MonsterInstance, tamed: bool) -> void:
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", shown.grade_color())
	title.text = "%s · %s" % [shown.display_name(), shown.grade_name()]
	_gear_panel.add_child(title)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 28)
	badge.add_theme_color_override("font_color",
		CollectionGrid.TAMED_FRAME if tamed else Color("ADA99F"))
	badge.text = "В твоей коллекции" if tamed else "Побеждён, но пока не подружились"
	_gear_panel.add_child(badge)


func _card_portrait(species: MonsterData, grade: int) -> void:
	var portrait := TextureRect.new()
	portrait.texture = species.sprite_for_grade(grade)
	portrait.custom_minimum_size = Vector2(0, 260)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gear_panel.add_child(portrait)


## Таблица характеристик. Каждая строка — «что это» и «сколько», в столбик:
## склеенная строка чисел для семилетнего нечитаема.
func _card_stats(shown: MonsterInstance, tamed: MonsterInstance) -> void:
	var species := shown.data()
	var fruit := Registry.fruit(species.favorite_fruit_id) if species != null else null

	_add_stat("Стихия", MonsterData.genre_name(shown.genre()))
	_add_stat("Здоровье", "%d" % shown.max_health())
	_add_stat("Настрой", "%d" % shown.vibe())
	_add_stat("Удар", "%.1f" % shown.power())
	_add_stat("Любимый фрукт", fruit.display_name if fruit != null else "?")

	if tamed == null:
		var threshold := GameState.friendship_threshold(shown.grade)
		var value := GameState.get_friendship(shown.species_id, shown.grade)
		_add_stat("Дружба", "%d / %d" % [value, threshold])
		return

	_add_stat("Уровень", "%d" % tamed.level)

	# Опыт ПОЛОСКОЙ, а не строкой «120 / 220»: сколько осталось до уровня,
	# читается взглядом, а не вычитанием в уме
	var xp := tamed.xp_progress()
	if tamed.is_max_level():
		_add_stat("Опыт", "максимальный уровень")
	else:
		_add_xp_bar(xp)
		_add_next_level(tamed)

	var bonuses := GameState.gear_bonuses(tamed.key())
	_add_stat("Снаряжение", "окно ×%.2f · удар +%.1f · здоровье +%d · защита +%d%%" % [
		bonuses.window_scale, bonuses.power_bonus, bonuses.health_bonus,
		int(round(bonuses.shield_reduction * 100.0)),
	])


func _add_stat(name: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = name
	label.custom_minimum_size = Vector2(320, 0)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("ADA99F"))
	row.add_child(label)

	var amount := Label.new()
	amount.text = value
	amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount.add_theme_font_size_override("font_size", 32)
	amount.add_theme_color_override("font_color", Color("F0DEC0"))
	row.add_child(amount)

	_gear_panel.add_child(row)


## Что можно сделать с существом. У неприручённого — ничего: кнопки,
## которые ничего не делают, ребёнок жмёт и решает, что игра сломалась.
func _card_actions(tamed: MonsterInstance) -> void:
	if tamed == null:
		return

	var key := tamed.key()
	if GameState.guardian_key() != key:
		_add_gear_button("Взять в лес", func(): GameState.set_guardian(key))
	_add_gear_button("Снаряжение", func(): _open_gear(key))
	_add_gear_button("Угостить", func(): _open_feed(key))


## Полоска опыта до следующего уровня.
func _add_xp_bar(progress: Vector2i) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "Опыт"
	label.custom_minimum_size = Vector2(320, 0)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color("ADA99F"))
	row.add_child(label)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 36)
	bar.show_percentage = false
	bar.max_value = maxf(float(progress.y), 1.0)
	bar.value = float(progress.x)
	column.add_child(bar)

	var caption := Label.new()
	caption.text = "%d / %d" % [progress.x, progress.y]
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color("DCC7A4"))
	column.add_child(caption)

	row.add_child(column)
	_gear_panel.add_child(row)


## Каким станет существо на следующем уровне.
##
## Без этого «уровень 3» остаётся числом: непонятно, стоит ли кормить дальше
## и что вообще даёт рост. Считаем ТЕМ ЖЕ объектом, который дерётся в бою, —
## копия с уровнем на единицу больше, — поэтому обещание не может разойтись
## с тем, что случится на самом деле.
func _add_next_level(tamed: MonsterInstance) -> void:
	var preview := MonsterInstance.create(tamed.species_id, tamed.grade)
	preview.level = tamed.level + 1

	_add_stat("На уровне %d" % preview.level,
		"здоровье %d → %d · удар %.1f → %.1f" % [
			tamed.max_health(), preview.max_health(),
			tamed.power(), preview.power(),
		])
