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
	Jukebox.play_screen("inventory")
	UIUtil.set_screen_background($Scenery, "res://art/screen/screen_inventory.png")

	GameState.fruits_changed.connect(_refresh)
	GameState.silver_changed.connect(func(_v): _refresh())
	FarmState.seeds_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_wallet.text = "Серебро: %d        Золото: %d" % [GameState.silver, ShopState.gold]
	UIUtil.clear_children(_list)

	_add_hero_stats()

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
			], TEXT_COLOR, fruit)

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
				"x%d" % count, TEXT_COLOR, fruit)
	if not any_fruit:
		_add_row("Пусто — вырасти что-нибудь на грядке", "", DIM_COLOR)

	_add_section("Снаряжение", "Надевается на защитника в «Коллекции»")
	var gear_ids := GameState.owned_gear_ids()
	if gear_ids.is_empty():
		_add_row("Пусто — купи у торговца в лесу", "", DIM_COLOR)
	for gear_id in gear_ids:
		var item := Registry.gear(gear_id)
		if item == null:
			continue
		_add_row("%s (%s)" % [item.display_name, GearData.slot_name(item.slot)],
			"x%d · %s" % [GameState.gear_count(gear_id), item.effect_text()], TEXT_COLOR, item)



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


## Строка сумки: картинка, название, подробность.
##
## Раньше всё это было одной подписью со склеенным текстом, и длинная строка
## («Шапочка из жёлудя (Головной убор)  x1 · Здоровье +20, защита +5%»)
## переносилась посреди фразы, разрывая её на две неровные половины.
## Разложенное по колонкам не переносится вовсе, а картинка избавляет
## ребёнка от чтения там, где хватает узнавания.
func _add_row(name: String, detail: String, colour := TEXT_COLOR,
		item: Resource = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	# Контейнер не ловит ввод: пустая обёртка поверх экрана молча съедала бы
	# нажатия по тому, что под ней (CLAUDE.md)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(88, 88)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = UIUtil.item_icon(item)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = name
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", colour)
	column.add_child(title)

	if not detail.is_empty():
		var sub := Label.new()
		sub.text = detail
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 26)
		sub.add_theme_color_override("font_color", DIM_COLOR)
		column.add_child(sub)

	row.add_child(column)
	_list.add_child(row)


func _go_back() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)


## Характеристики героя и его защитника.
##
## До этого раздела статы жили только в карточке существа, а «сколько у меня
## здоровья в забеге» не отвечал ни один экран. Числа берутся у тех же
## объектов, что дерутся в бою, поэтому сумка не может разойтись с боем.
func _add_hero_stats() -> void:
	_add_section("Герой", "С чем ты выходишь в лес")

	var guardian := GameState.guardian()
	if guardian == null:
		_add_row("Защитника пока нет", "Подружись с кем-нибудь в лесу", DIM_COLOR)
		return

	var bonuses := GameState.gear_bonuses(guardian.key())
	var health: int = guardian.max_health() + int(bonuses.get("health_bonus", 0))
	var power: float = guardian.power() + float(bonuses.get("power_bonus", 0.0))

	_add_row("%s · %s" % [guardian.display_name(), guardian.grade_name()],
		"уровень %d · %s" % [guardian.level,
			MonsterData.genre_name(guardian.genre())], TEXT_COLOR, guardian.data())

	# Со снаряжением и без: игрок должен видеть, что именно дал пояс
	_add_row("Здоровье", "%d  (своих %d + снаряжение %d)" % [
		health, guardian.max_health(), int(bonuses.get("health_bonus", 0))])
	_add_row("Удар", "%.1f  (своих %.1f + снаряжение %.1f)" % [
		power, guardian.power(), float(bonuses.get("power_bonus", 0.0))])
	_add_row("Окно попадания", "×%.2f" % float(bonuses.get("window_scale", 1.0)))
	_add_row("Защита от удара", "%d%%" % int(round(
		float(bonuses.get("shield_reduction", 0.0)) * 100.0)))

	var xp := guardian.xp_progress()
	_add_row("Опыт", "максимум" if guardian.is_max_level() \
		else "%d / %d до уровня %d" % [xp.x, xp.y, guardian.level + 1])

	# Бафы, съеденные у костра, живут до конца забега — и о них надо помнить,
	# решая, идти ли дальше
	if RunManager.is_active:
		var eaten: Array[String] = []
		if RunManager.buff("shield_reduction") > 0.0:
			eaten.append("защита +%d%%" % int(round(
				RunManager.buff("shield_reduction") * 100.0)))
		if RunManager.buff("power_bonus") > 0.0:
			eaten.append("удар +%.1f" % RunManager.buff("power_bonus"))
		if RunManager.buff("window_scale") > 0.0:
			eaten.append("окно +%d%%" % int(round(
				RunManager.buff("window_scale") * 100.0)))
		if not eaten.is_empty():
			_add_row("Съедено у костра", " · ".join(eaten))
