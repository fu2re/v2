extends Node2D

## Коллекция: кто уже друг, кто на подходе, кого берём в лес.
##
## Показываются ВСЕ виды, включая неприручённых — с их шкалами дружбы.
## Видеть, что до нового друга осталось три встречи, важнее, чем любоваться
## теми, кто уже есть: это и есть то, ради чего игрок идёт в лес.

const CARD_HEIGHT := 240.0

var _list: VBoxContainer = null
var _status: Label = null
var _gear_panel: VBoxContainer = null
var _selected_id: String = ""


func _ready() -> void:
	_build_ui()
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


func _open_gear(monster_id: String) -> void:
	_selected_id = monster_id
	UIUtil.clear_children(_gear_panel)

	var monster := Registry.monster(monster_id)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 40)
	header.add_theme_color_override("font_color", Color("DCC7A4"))
	header.text = "Снаряжение: %s" % (monster.display_name if monster != null else monster_id)
	_gear_panel.add_child(header)

	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		var current := GameState.equipped_gear(monster_id, slot)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color("ADA99F"))
		label.text = "%s — %s" % [GearData.slot_name(slot), GearData.slot_hint(slot)]
		_gear_panel.add_child(label)

		if current != null:
			_add_gear_button("Снять: %s (%s)" % [current.display_name, current.effect_text()],
				func(): GameState.unequip(monster_id, slot))

		for gear_id in GameState.owned_gear_ids():
			var item := Registry.gear(gear_id)
			if item == null or item.slot != slot:
				continue
			_add_gear_button("%s x%d — %s" % [
					item.display_name, GameState.gear_count(gear_id), item.effect_text()],
				func(): GameState.equip(monster_id, gear_id))

	_add_gear_button("Закрыть", _close_gear)
	_gear_panel.visible = true


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


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("2A414F")
	add_child(bg)

	var title := Label.new()
	title.position = Vector2(60, 80)
	title.size = Vector2(960, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", Color("DCC7A4"))
	title.text = "Друзья"
	add_child(title)

	var back := Button.new()
	back.text = "На ферму"
	back.position = Vector2(60, 1740)
	back.size = Vector2(960, 110)
	back.add_theme_font_size_override("font_size", 44)
	back.pressed.connect(_go_back)
	add_child(back)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 200)
	scroll.size = Vector2(960, 1500)
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(960, 0)
	_list.add_theme_constant_override("separation", 20)
	scroll.add_child(_list)

	_status = Label.new()
	_status.position = Vector2(60, 1660)
	_status.size = Vector2(960, 60)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 30)
	_status.add_theme_color_override("font_color", Color("DCC7A4"))
	add_child(_status)

	var panel := ColorRect.new()
	panel.size = Vector2(1080, 1920)
	panel.color = Color(0.09, 0.13, 0.16, 0.97)
	panel.visible = false
	add_child(panel)

	_gear_panel = VBoxContainer.new()
	_gear_panel.position = Vector2(60, 160)
	_gear_panel.size = Vector2(960, 1600)
	_gear_panel.add_theme_constant_override("separation", 14)
	_gear_panel.visible = false
	_gear_panel.visibility_changed.connect(func(): panel.visible = _gear_panel.visible)
	add_child(_gear_panel)
