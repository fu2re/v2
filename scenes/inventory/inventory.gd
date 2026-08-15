extends Node2D

## Инвентарь: что у игрока есть на руках.
##
## Разделение сущностей, которое раньше путалось (GDD §12.1):
##   Серебро — заработанная валюта, за неё покупается всё игровое
##   Золото  — донатная валюта, только косметика
##   Семена  — предмет, из него растут фрукты
##   Фрукты  — предмет, им угощают монстров

const TEXT_COLOR := Color("DCC7A4")
const DIM_COLOR := Color("ADA99F")

## Раскладка живёт в Inventory.tscn и правится в инспекторе (GDD §13.2.1).
@onready var _list: VBoxContainer = $ListScroll/List
@onready var _wallet: Label = $Wallet


func _ready() -> void:
	$BackButton.pressed.connect(_go_back)

	GameState.fruits_changed.connect(_refresh)
	GameState.silver_changed.connect(func(_v): _refresh())
	FarmState.seeds_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_wallet.text = "Серебро: %d        Золото: %d" % [GameState.silver, ShopState.gold]
	UIUtil.clear_children(_list)

	_add_section("Семена", "Их сажают на грядках")
	var seeds := FarmState.available_seeds()
	if seeds.is_empty():
		_add_row("Пусто — ищи дикие кусты в лесу", "", DIM_COLOR)
	for fruit_id in seeds:
		var fruit := Registry.fruit(fruit_id)
		_add_row(
			fruit.display_name if fruit != null else fruit_id,
			"x%d · зреет %s" % [
				FarmState.seed_count(fruit_id),
				_format_time(float(fruit.grow_seconds())) if fruit != null else "?",
			])

	_add_section("Фрукты", "Ими угощают монстров после победы")
	var any_fruit := false
	for fruit in Registry.all_fruits():
		for quality in [FruitData.Quality.PERFECT, FruitData.Quality.JUICY,
				FruitData.Quality.PLAIN]:
			var count := GameState.fruit_count(fruit.id, quality)
			if count <= 0:
				continue
			any_fruit = true
			_add_row("%s (%s)" % [fruit.display_name, FruitData.quality_name(quality)],
				"x%d" % count)
	if not any_fruit:
		_add_row("Пусто — вырасти что-нибудь на грядке", "", DIM_COLOR)

	_add_section("Снаряжение", "Надевается на гуардиана во «Друзьях»")
	var gear_ids := GameState.owned_gear_ids()
	if gear_ids.is_empty():
		_add_row("Пусто — купи у торговца в лесу", "", DIM_COLOR)
	for gear_id in gear_ids:
		var item := Registry.gear(gear_id)
		if item == null:
			continue
		_add_row("%s (%s)" % [item.display_name, GearData.slot_name(item.slot)],
			"x%d · %s" % [GameState.gear_count(gear_id), item.effect_text()])


func _format_time(seconds: float) -> String:
	var total := int(ceil(seconds))
	if total >= 3600:
		return "%d ч" % (total / 3600)
	if total >= 60:
		return "%d мин" % (total / 60)
	return "%d сек" % total


func _add_section(title: String, hint: String) -> void:
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 46)
	header.add_theme_color_override("font_color", Color("F0DEC0"))
	_list.add_child(header)

	var sub := Label.new()
	sub.text = hint
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", DIM_COLOR)
	_list.add_child(sub)


func _add_row(name: String, detail: String, colour := TEXT_COLOR) -> void:
	var row := Label.new()
	row.text = "  %s%s" % [name, ("     " + detail) if not detail.is_empty() else ""]
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_theme_font_size_override("font_size", 30)
	row.add_theme_color_override("font_color", colour)
	_list.add_child(row)


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")


