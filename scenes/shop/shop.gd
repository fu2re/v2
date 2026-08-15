extends Node2D

## Магазин.
##
## Требования GDD §12.3 видны прямо на экране: шансы раскрыты до оплаты,
## счётчик гарантии на виду, остаток дневного лимита показан, покупка
## подтверждается вторым нажатием.

const CONFIRM_RESET_SEC := 4.0

var _list: VBoxContainer = null
var _balance: Label = null
var _status: Label = null
var _crate_button: Button = null
var _odds_label: Label = null

## Что ждёт подтверждения. Покупка в один тап запрещена родительским
## контролем — и это защита не от жадности, а от случайного нажатия ребёнком.
var _pending: String = ""
var _pending_since: float = 0.0


func _ready() -> void:
	_build_ui()
	ShopState.chords_changed.connect(func(_v): _refresh())
	ShopState.purchase_blocked.connect(_on_blocked)
	ShopState.crate_opened.connect(_on_crate_opened)
	_refresh()


func _process(_delta: float) -> void:
	# Подтверждение живёт несколько секунд: забытая «взведённая» кнопка
	# однажды сработает от случайного тапа
	if _pending.is_empty():
		return
	if Time.get_ticks_msec() / 1000.0 - _pending_since > CONFIRM_RESET_SEC:
		_pending = ""
		_refresh()


func _refresh() -> void:
	_balance.text = "Аккорды: %d      Сегодня можно потратить: %d" % [
		ShopState.chords, ShopState.remaining_today(),
	]

	var allowed := ShopState.lootboxes_allowed()
	_crate_button.visible = allowed
	_odds_label.visible = allowed
	if allowed:
		_odds_label.text = ShopState.odds_disclosure()
		_crate_button.text = "Пластинка — %d ♪" % ShopState.CRATE_PRICE \
			if _pending != "__crate__" else "Точно открыть? Нажми ещё раз"

	UIUtil.clear_children(_list)

	for item in Registry.all_cosmetics():
		_list.add_child(_make_row(item))


func _make_row(item: CosmeticData) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", MonsterData.rarity_color(item.rarity))
	title.text = "%s · %s" % [item.display_name, CosmeticData.slot_name(item.slot)]
	box.add_child(title)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 90)
	button.add_theme_font_size_override("font_size", 30)

	if ShopState.is_owned(item.id):
		var worn := ShopState.equipped_in(item.slot)
		var is_worn := worn != null and worn.id == item.id
		button.text = "Надето" if is_worn else "Надеть"
		button.disabled = is_worn
		button.pressed.connect(func():
			ShopState.equip(item.id)
			_refresh())
	elif _pending == item.id:
		button.text = "Купить за %d ♪? Нажми ещё раз" % item.price_chords
		button.pressed.connect(_confirm_buy.bind(item))
	else:
		button.text = "%d ♪" % item.price_chords
		button.pressed.connect(func():
			_pending = item.id
			_pending_since = Time.get_ticks_msec() / 1000.0
			_status.text = "Подтверди покупку вторым нажатием"
			_refresh())

	box.add_child(button)
	return box


func _confirm_buy(item: CosmeticData) -> void:
	_pending = ""
	if ShopState.buy_direct(item.id):
		_status.text = "Куплено: %s" % item.display_name
	_refresh()


func _on_crate_pressed() -> void:
	if _pending != "__crate__":
		_pending = "__crate__"
		_pending_since = Time.get_ticks_msec() / 1000.0
		_status.text = "Шансы указаны выше. Подтверди вторым нажатием."
		_refresh()
		return
	_pending = ""
	ShopState.open_crate()
	_refresh()


func _on_crate_opened(cosmetic_id: String, was_duplicate: bool, pity_hit: bool) -> void:
	var item := Registry.cosmetic(cosmetic_id)
	if item == null:
		return
	if was_duplicate:
		_status.text = "%s уже есть — вернулись Аккорды: %d" % [
			item.display_name, ShopState.DUPLICATE_REFUND.get(item.rarity, 0),
		]
	elif pity_hit:
		_status.text = "Гарантия сработала: %s!" % item.display_name
	else:
		_status.text = "Выпало: %s (%s)" % [
			item.display_name, MonsterData.rarity_name(item.rarity),
		]


func _on_blocked(reason: String) -> void:
	_pending = ""
	_status.text = reason
	_refresh()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/farm/Farm.tscn")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	bg.color = Color("3A2A1C")
	add_child(bg)

	var title := Label.new()
	title.position = Vector2(60, 60)
	title.size = Vector2(960, 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color("F0DEC0"))
	title.text = "Лавка"
	add_child(title)

	_balance = Label.new()
	_balance.position = Vector2(60, 150)
	_balance.size = Vector2(960, 50)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_balance.add_theme_font_size_override("font_size", 30)
	_balance.add_theme_color_override("font_color", Color("DCC7A4"))
	add_child(_balance)

	_odds_label = Label.new()
	_odds_label.position = Vector2(60, 210)
	_odds_label.size = Vector2(560, 260)
	_odds_label.add_theme_font_size_override("font_size", 26)
	_odds_label.add_theme_color_override("font_color", Color("BA9A6D"))
	add_child(_odds_label)

	_crate_button = Button.new()
	_crate_button.position = Vector2(640, 250)
	_crate_button.size = Vector2(380, 140)
	_crate_button.add_theme_font_size_override("font_size", 32)
	_crate_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crate_button.pressed.connect(_on_crate_pressed)
	add_child(_crate_button)

	_status = Label.new()
	_status.position = Vector2(60, 480)
	_status.size = Vector2(960, 70)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 28)
	_status.add_theme_color_override("font_color", Color("1ED8FF"))
	add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(60, 560)
	scroll.size = Vector2(960, 1180)
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(960, 0)
	_list.add_theme_constant_override("separation", 18)
	scroll.add_child(_list)

	var back := Button.new()
	back.text = "На ферму"
	back.position = Vector2(60, 1770)
	back.size = Vector2(960, 100)
	back.add_theme_font_size_override("font_size", 40)
	back.pressed.connect(_go_back)
	add_child(back)
