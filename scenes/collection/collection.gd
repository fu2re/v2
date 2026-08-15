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

const CARD_HEIGHT := 240.0

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

	GameState.gear_changed.connect(_refresh)
	GameState.guardian_changed.connect(func(_id): _refresh())
	_refresh()


func _refresh() -> void:
	UIUtil.clear_children(_list)

	for friend: MonsterInstance in GameState.all_instances():
		_list.add_child(_make_friend_card(friend))

	for monster in Registry.all_monsters():
		var card := _make_progress_card(monster)
		if card != null:
			_list.add_child(card)


## Карточка приручённого экземпляра.
func _make_friend_card(friend: MonsterInstance) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(960, CARD_HEIGHT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", friend.grade_color())
	var active := " ← в лесу" if GameState.guardian_key() == friend.key() else ""
	# Грейд в имени обязателен: два Ростика разных грейдов иначе неотличимы
	var grade_mark := "" if friend.grade == MonsterData.Rarity.COMMON \
		else " · %s" % friend.grade_name()
	title.text = "%s%s%s" % [friend.display_name(), grade_mark, active]
	box.add_child(title)

	var species := friend.data()
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 30)
	info.add_theme_color_override("font_color", Color("ADA99F"))
	var fruit := Registry.fruit(species.favorite_fruit_id) if species != null else null
	info.text = "%s · уровень %d · любит %s" % [
		MonsterData.genre_name(friend.genre()),
		friend.level,
		fruit.display_name if fruit != null else "?",
	]
	box.add_child(info)

	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 30)
	var xp := friend.xp_progress()
	progress.max_value = xp.y
	progress.value = xp.x
	progress.show_percentage = false
	box.add_child(progress)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 28)
	status.add_theme_color_override("font_color", Color("DCC7A4"))
	status.text = "Друг · %s" % _gear_summary(friend.key())
	box.add_child(status)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var take := Button.new()
	take.text = "Взять в лес"
	take.custom_minimum_size = Vector2(300, 76)
	take.add_theme_font_size_override("font_size", 32)
	take.disabled = GameState.guardian_key() == friend.key()
	take.pressed.connect(func(): GameState.set_guardian(friend.key()))
	row.add_child(take)

	var gear := Button.new()
	gear.text = "Снаряжение"
	gear.custom_minimum_size = Vector2(300, 76)
	gear.add_theme_font_size_override("font_size", 32)
	gear.pressed.connect(_open_gear.bind(friend.key()))
	row.add_child(gear)

	# Угощение растит уровень (GDD §6.5). Кнопка гаснет на потолке и когда
	# угощать нечем: предлагать нажать то, что не сработает, — обман
	var feed := Button.new()
	feed.text = "Угостить"
	feed.custom_minimum_size = Vector2(280, 76)
	feed.add_theme_font_size_override("font_size", 32)
	feed.disabled = friend.is_max_level() or GameState.fruits.is_empty()
	feed.pressed.connect(_open_feed.bind(friend.key()))
	row.add_child(feed)

	box.add_child(row)
	return card


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


## Карточка «на подходе»: ближайший к приручению грейд этого вида.
##
## Возвращает null, если ни к одному грейду вид ещё не подступался —
## показывать шесть пустых полосок на каждого незнакомца незачем.
func _make_progress_card(monster: MonsterData) -> Control:
	var best_grade := -1
	var best_ratio := 0.0
	for grade in MonsterData.RARITY_NAMES.size():
		if GameState.has_instance(monster.id, grade):
			continue
		var value := GameState.get_friendship(monster.id, grade)
		if value <= 0:
			continue
		var ratio := float(value) / float(GameState.friendship_threshold(grade))
		if ratio > best_ratio:
			best_ratio = ratio
			best_grade = grade

	if best_grade < 0:
		return null

	var value := GameState.get_friendship(monster.id, best_grade)
	var threshold := GameState.friendship_threshold(best_grade)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(960, CARD_HEIGHT * 0.7)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", MonsterData.rarity_color(best_grade))
	title.text = "%s · %s" % [monster.display_name, MonsterData.rarity_name(best_grade)]
	box.add_child(title)

	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 30)
	progress.max_value = threshold
	progress.value = value
	progress.show_percentage = false
	box.add_child(progress)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 28)
	status.add_theme_color_override("font_color", Color("DCC7A4"))
	var meetings := int(ceil(float(threshold - value) / GameState.FRIENDSHIP_WIN))
	status.text = "Дружба %d/%d — примерно %d встреч" % [value, threshold, meetings]
	box.add_child(status)

	return card


func _gear_summary(instance_key: String) -> String:
	var parts: Array[String] = []
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		var item := GameState.equipped_gear(instance_key, slot)
		parts.append(item.display_name if item != null else "—")
	return " / ".join(parts)


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
		take_off.custom_minimum_size = Vector2(0, 56)
		take_off.add_theme_font_size_override("font_size", 24)
		take_off.pressed.connect(func(): GameState.unequip(instance_key, slot))
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
	_selected_key = ""


func _go_back() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)
