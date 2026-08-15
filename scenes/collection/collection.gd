extends Node2D

## Коллекция: кто уже друг, кто на подходе, кого берём в лес.
##
## Показываются ВСЕ виды, включая неприручённых — с их шкалами дружбы.
## Видеть, что до нового друга осталось три встречи, важнее, чем любоваться
## теми, кто уже есть: это и есть то, ради чего игрок идёт в лес.

const CARD_HEIGHT := 240.0

## Раскладка живёт в Collection.tscn и правится в инспекторе (GDD §13.2.1).
@onready var _list: VBoxContainer = $ListScroll/List
@onready var _status: Label = $Status
@onready var _gear_panel: VBoxContainer = $GearPanel

var _selected_id: String = ""


func _ready() -> void:
	$BackButton.pressed.connect(_go_back)
	# Подложка гаснет вместе с панелью: иначе панель висит поверх живого
	# экрана, кнопки под ней видно, но нажать нельзя
	var backdrop: ColorRect = $GearBackdrop
	_gear_panel.visibility_changed.connect(
		func(): backdrop.visible = _gear_panel.visible)

	GameState.gear_changed.connect(_refresh)
	GameState.guardian_changed.connect(func(_id): _refresh())
	_refresh()


func _refresh() -> void:
	UIUtil.clear_children(_list)

	for monster in Registry.all_monsters():
		_list.add_child(_make_card(monster))


func _make_card(monster: MonsterData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(960, CARD_HEIGHT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var tamed := GameState.is_tamed(monster.id)
	var value := GameState.get_friendship(monster.id)
	var threshold := monster.friendship_threshold()

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", MonsterData.rarity_color(monster.rarity))
	var active := " ← в лесу" if GameState.guardian_id() == monster.id else ""
	title.text = "%s%s" % [monster.display_name, active]
	box.add_child(title)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 30)
	info.add_theme_color_override("font_color", Color("ADA99F"))
	var fruit := Registry.fruit(monster.favorite_fruit_id)
	info.text = "%s · %s · любит %s" % [
		MonsterData.genre_name(monster.genre),
		MonsterData.rarity_name(monster.rarity),
		fruit.display_name if fruit != null else "?",
	]
	box.add_child(info)

	# Шкала дружбы у ВСЕХ, включая незнакомых: прогресс должен быть виден
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 30)
	progress.max_value = threshold
	progress.value = value
	progress.show_percentage = false
	box.add_child(progress)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 28)
	status.add_theme_color_override("font_color", Color("DCC7A4"))
	if tamed:
		status.text = "Друг · %s" % _gear_summary(monster.id)
	else:
		var left := threshold - value
		var meetings := int(ceil(float(left) / GameState.FRIENDSHIP_WIN))
		status.text = "Дружба %d/%d — примерно %d встреч" % [value, threshold, meetings]
	box.add_child(status)

	if tamed:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var take := Button.new()
		take.text = "Взять в лес"
		take.custom_minimum_size = Vector2(300, 76)
		take.add_theme_font_size_override("font_size", 32)
		take.disabled = GameState.guardian_id() == monster.id
		take.pressed.connect(func(): GameState.set_guardian(monster.id))
		row.add_child(take)

		var gear := Button.new()
		gear.text = "Снаряжение"
		gear.custom_minimum_size = Vector2(300, 76)
		gear.add_theme_font_size_override("font_size", 32)
		gear.pressed.connect(_open_gear.bind(monster.id))
		row.add_child(gear)

		box.add_child(row)

	return card


func _gear_summary(monster_id: String) -> String:
	var parts: Array[String] = []
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		var item := GameState.equipped_gear(monster_id, slot)
		parts.append(item.display_name if item != null else "—")
	return " / ".join(parts)


## Экран экипировки: три слота сверху, сундук снизу.
##
## Раньше это был сплошной список, где надетое и лежащее в сундуке шли
## вперемешку и отличались только словом «Снять». Понять, что на ком надето,
## было нельзя. Теперь слоты — это ячейки: видно, что занято, что пусто
## и что вообще подходит.
func _open_gear(monster_id: String) -> void:
	_selected_id = monster_id
	UIUtil.clear_children(_gear_panel)

	var monster := Registry.monster(monster_id)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 44)
	header.add_theme_color_override("font_color", Color("F0DEC0"))
	header.text = monster.display_name if monster != null else monster_id
	_gear_panel.add_child(header)

	# Три ячейки слотов в ряд — как на персонаже
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 16)
	_gear_panel.add_child(slots)
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		slots.add_child(_make_slot_cell(monster_id, slot))

	# Сводка эффектов: игрок должен видеть, что даёт весь комплект целиком
	var bonuses := GameState.gear_bonuses(monster_id)
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
			func(): GameState.equip(monster_id, gear_id))

	_add_gear_button("Закрыть", _close_gear)
	_gear_panel.visible = true


## Ячейка одного слота: что надето, что слот делает, как снять.
func _make_slot_cell(monster_id: String, slot: GearData.Slot) -> Control:
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

	var item := GameState.equipped_gear(monster_id, slot)
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
		take_off.custom_minimum_size = Vector2(0, 56)
		take_off.add_theme_font_size_override("font_size", 24)
		take_off.pressed.connect(func(): GameState.unequip(monster_id, slot))
		box.add_child(take_off)

	return cell


func _add_gear_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 80)
	button.add_theme_font_size_override("font_size", 30)
	button.pressed.connect(callback)
	_gear_panel.add_child(button)


func _close_gear() -> void:
	_gear_panel.visible = false
	_selected_id = ""


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")


