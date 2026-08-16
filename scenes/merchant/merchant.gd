extends Node2D

## Лавка в усадьбе: торговец за СЕРЕБРО (GDD §8.2.2).
##
## Здесь запасаются перед выходом в лес — семенами, зельями, снаряжением.
## Всё покупается за игровую валюту; наряды за золото живут отдельным
## экраном, и попасть туда можно только сознательным нажатием.
## Разделение контуров видно даже в раскладке: две валюты не встречаются
## на одном прилавке (GDD §12).
##
## Витрина обновляется раз в десять минут, но это не таймер давления:
## семена продаются всегда, ничего не пропадает, и опоздать невозможно.

@onready var _list: VBoxContainer = $ListScroll/List
@onready var _purse: Label = $Purse
@onready var _rotation: Label = $Rotation
@onready var _status: Label = $Status

## Сколько строк было в прошлый раз. Список пересобирается только при
## изменении состава: полная пересборка каждый кадр уничтожала бы кнопку
## между нажатием и отпусканием, и покупка не срабатывала бы (CLAUDE.md).
var _last_rotation := -1
var _last_rows := -1


func _ready() -> void:
	$BackButton.pressed.connect(_go_to_lobby)
	$CosmeticsButton.pressed.connect(_go_to_cosmetics)
	Jukebox.play_screen("merchant")
	UIUtil.set_screen_background($Scenery, "res://art/screen/screen_merchant.png")

	GameState.silver_changed.connect(func(_v): _refresh_prices())
	_rebuild()


func _process(_delta: float) -> void:
	# Витрина сменилась, пока игрок стоял у прилавка, — показываем новую
	if MerchantStock.rotation_index() != _last_rotation:
		_rebuild()
		return
	_refresh_rotation_label()


func _rebuild() -> void:
	_last_rotation = MerchantStock.rotation_index()
	UIUtil.clear_children(_list)

	var stock := MerchantStock.farm_stock(_last_rotation)
	_last_rows = stock.size()

	if stock.is_empty():
		var empty := Label.new()
		empty.text = "Прилавок пуст. Загляни попозже."
		empty.add_theme_font_size_override("font_size", 32)
		empty.add_theme_color_override("font_color", Color("ADA99F"))
		_list.add_child(empty)

	for item: Resource in stock:
		_list.add_child(_make_row(item))

	_refresh_prices()
	_refresh_rotation_label()


func _make_row(item: Resource) -> Control:
	var price := MerchantStock.price_of(item)
	var title: String = item.display_name
	var detail := MerchantStock.describe(item)

	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 130)
	button.add_theme_font_size_override("font_size", 32)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.text = "%s — %d серебра\n%s" % [title, price, detail]
	UIUtil.decorate_row(button, item)
	button.pressed.connect(_buy.bind(item))
	# Цена перепроверяется при каждом обновлении кошелька, поэтому имя узла
	# несёт цену: так строку не приходится пересобирать ради одной блокировки
	button.set_meta("price", price)
	return button


func _buy(item: Resource) -> void:
	var title: String = item.display_name
	if not MerchantStock.buy(item):
		_status.text = "Не хватает серебра на «%s»" % title
		return

	_status.text = "Куплено: %s" % title
	# Состав витрины не изменился — обновляем только доступность цен,
	# не трогая сами кнопки
	_refresh_prices()


## Что по карману, а что нет. Меняются только `disabled` и подпись кошелька:
## кнопки остаются теми же узлами, и нажатие не теряется.
func _refresh_prices() -> void:
	_purse.text = "Серебро: %d" % GameState.silver
	for child in _list.get_children():
		if child is Button and child.has_meta("price"):
			var price: int = child.get_meta("price")
			child.disabled = GameState.silver < price


func _refresh_rotation_label() -> void:
	var left := MerchantStock.seconds_until_rotation()
	var minutes := left / 60
	var seconds := left % 60
	_rotation.text = "Новый товар через %d:%02d · семена в продаже всегда" % [
		minutes, seconds,
	]


func _go_to_cosmetics() -> void:
	get_tree().change_scene_to_file("res://scenes/shop/Shop.tscn")


func _go_to_lobby() -> void:
	get_tree().change_scene_to_file(OnboardingState.LOBBY)
