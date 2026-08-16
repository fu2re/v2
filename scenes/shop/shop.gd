extends Node2D

## Магазин.
##
## Требования GDD §12.3 видны прямо на экране: шансы раскрыты до оплаты,
## счётчик гарантии на виду, остаток дневного лимита показан, покупка
## подтверждается вторым нажатием.

const CONFIRM_RESET_SEC := 4.0

## Раскладка живёт в Shop.tscn и правится в инспекторе (GDD §13.2.1).
@onready var _list: VBoxContainer = $ListScroll/List
@onready var _balance: Label = $Balance
@onready var _status: Label = $Status
@onready var _crate_button: Button = $CrateButton
@onready var _odds_label: Label = $OddsLabel

## Что ждёт подтверждения. Покупка в один тап запрещена родительским
## контролем — и это защита не от жадности, а от случайного нажатия ребёнком.
var _pending: String = ""
var _pending_since: float = 0.0


func _ready() -> void:
	$BackButton.pressed.connect(_go_back)
	_crate_button.pressed.connect(_on_crate_pressed)
	Jukebox.play_screen("shop")

	ShopState.gold_changed.connect(func(_v): _refresh())
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
	_balance.text = "Золото: %d      Сегодня можно потратить: %d" % [
		ShopState.gold, ShopState.remaining_today(),
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


## Одна строка витрины: картинка, название, цена — всё на одной кнопке.
##
## Раньше это были два отдельных узла: подпись сверху и кнопка снизу. Связь
## между ними держалась только на близости, и витрина рассыпалась на чересполосицу
## заголовков и пустых плашек — непонятно, к чему относится цена и что вообще
## нажимать. Одна кнопка на предмет: нажимается ровно то, что видно.
func _make_row(item: CosmeticData) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 150)
	button.add_theme_font_size_override("font_size", 32)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Цвет грейда — на самой кнопке: редкость видна там же, где название,
	# и не требует отдельной подписи
	button.add_theme_color_override("font_color", MonsterData.rarity_color(item.rarity))
	UIUtil.decorate_row(button, item)

	var caption := "%s · %s" % [item.display_name, CosmeticData.slot_name(item.slot)]

	if ShopState.is_owned(item.id):
		var worn := ShopState.equipped_in(item.slot)
		var is_worn := worn != null and worn.id == item.id
		button.text = "%s\n%s" % [caption, "Надето" if is_worn else "Нажми, чтобы надеть"]
		button.disabled = is_worn
		button.pressed.connect(func():
			ShopState.equip(item.id)
			_refresh())
	elif _pending == item.id:
		button.text = "%s\nКупить за %d ♪? Нажми ещё раз" % [caption, item.price_gold]
		button.pressed.connect(_confirm_buy.bind(item))
	else:
		button.text = "%s\n%d ♪" % [caption, item.price_gold]
		button.disabled = ShopState.gold < item.price_gold
		button.pressed.connect(func():
			_pending = item.id
			_pending_since = Time.get_ticks_msec() / 1000.0
			_status.text = "Подтверди покупку вторым нажатием"
			_refresh())

	return button


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
		_status.text = "%s уже есть — вернулись Золото: %d" % [
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
	get_tree().change_scene_to_file("res://scenes/merchant/Merchant.tscn")


