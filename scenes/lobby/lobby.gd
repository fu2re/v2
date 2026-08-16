extends Node2D

## Двор усадьбы — главный экран между забегами.
##
## Устроен как городской экран в старых стратегиях: нарисованный двор,
## на нём стоят постройки, и каждая — вход в своё место. Клик по домику,
## а не по кнопке со словом: ребёнок 7 лет узнаёт огород по грядкам
## быстрее, чем прочитает слово «огород» (GDD §2.3).
##
## Подпись под каждой постройкой всё же есть — она для взрослого и для того,
## кто ещё не понял картинку. Но картинка идёт первой.

## Каждая постройка: узел спрайта, подпись, куда ведёт.
##
## Порядок задаёт и порядок обхода клавиатурой — сверху вниз, слева направо,
## как читают.
const BUILDINGS := [
	{
		"node": "GardenArt",
		"title": "Огород",
		"scene": "res://scenes/farm/Farm.tscn",
		"art": ["res://art/building/building_garden.png"],
	},
	{
		"node": "GuardiansArt",
		"title": "Коллекция",
		"scene": "res://scenes/collection/Collection.tscn",
		"art": ["res://art/building/building_guardians.png"],
	},
	{
		"node": "StorehouseArt",
		"title": "Инвентарь",
		"scene": "res://scenes/inventory/Inventory.tscn",
		# Пока амбар не нарисован, во дворе стоит мешок с семенами: место
		# должно быть доступно, даже если его домик ещё в очереди на отрисовку
		"art": ["res://art/building/building_storehouse.png",
			"res://art/prop/prop_seed_pouch.png"],
	},
	{
		"node": "MerchantArt",
		"title": "Магазин",
		"scene": "res://scenes/merchant/Merchant.tscn",
		"art": ["res://art/building/building_merchant.png",
			"res://art/prop/prop_chest.png"],
	},
	{
		"node": "ForestArt",
		"title": "В путь",
		"scene": "res://scenes/run/RunFeed.tscn",
		"art": ["res://art/building/building_forest.png"],
	},
]

## Насколько постройка «подпрыгивает» под курсором. Наведение обязано быть
## видно: иначе непонятно, что двор вообще кликабельный.
const HOVER_SCALE := 1.08

## Высота строки подписи и запас до края экрана: по ним решается,
## поместится ли подпись под постройкой или её надо поднять над ней.
const CAPTION_HEIGHT := 48.0
const CAPTION_MARGIN := 20.0
const SCREEN_HEIGHT := 1920.0

@onready var _buildings: Control = $Buildings
@onready var _title: Label = $Title
@onready var _purse: RichTextLabel = $Purse
@onready var _guardian_label: Label = $GuardianLabel
@onready var _status: Label = $Status

## Кнопки-накладки поверх построек: id постройки -> Button.
var _hotspots: Dictionary = {}


func _ready() -> void:
	Jukebox.play_screen("lobby")
	# Двор рисуется во весь экран: иначе картинка висит маркой посреди пустоты
	UIUtil.cover_screen($Scenery)
	_build_hotspots()

	GameState.silver_changed.connect(func(_v): _refresh())
	GameState.guardian_changed.connect(func(_k): _refresh())
	FarmState.plots_changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	# Грядки зреют в реальном времени, в том числе пока игрок во дворе
	FarmState.tick()


## Накладка на каждую постройку.
##
## Кнопка невидимая и лежит ПОВЕРХ спрайта: так у постройки есть и своя
## картинка, и честная кнопка — с фокусом, состоянием и клавиатурой.
## Рисовать клики самому по координатам значило бы потерять и то, и другое.
func _build_hotspots() -> void:
	for entry: Dictionary in BUILDINGS:
		var node_name: String = entry["node"]
		var sprite: Sprite2D = _buildings.get_node_or_null(node_name)
		if sprite == null:
			continue

		# Арт берётся первый существующий из списка. Если не нашлось ни одного,
		# постройка просто не появляется во дворе, а не встречает игрока
		# розовым квадратом
		if sprite.texture == null:
			sprite.texture = _first_existing(entry["art"])
			if sprite.texture == null:
				sprite.visible = false
				continue

		# Границы ВИДИМОГО, а не всей текстуры. Постройки нарисованы в квадрате
		# 128×128 с прозрачными полями, и по полной коробке получалось два
		# вранья сразу: кнопка ловила клики по пустому воздуху рядом с домиком,
		# а подпись огорода уезжала так низко, что села на соседний прилавок.
		var bounds := _visible_bounds(sprite)
		var size := bounds.size
		var button := Button.new()
		button.flat = true
		button.text = ""
		button.custom_minimum_size = size
		button.size = size
		button.position = bounds.position
		button.pressed.connect(_enter.bind(entry))
		button.mouse_entered.connect(_hover.bind(sprite, true))
		button.mouse_exited.connect(_hover.bind(sprite, false))
		button.focus_entered.connect(_hover.bind(sprite, true))
		button.focus_exited.connect(_hover.bind(sprite, false))
		_buildings.add_child(button)
		_hotspots[node_name] = button

		var caption := Label.new()
		caption.text = entry["title"]
		caption.add_theme_font_size_override("font_size", 34)
		caption.add_theme_color_override("font_color", Color("F0DEC0"))
		# Обводка обязательна: подпись лежит на пёстром дворе, и без неё
		# буквы теряются в траве
		caption.add_theme_color_override("font_outline_color", Color("14200F"))
		caption.add_theme_constant_override("outline_size", 10)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size.x = size.x + 120.0

		# Обычно подпись под постройкой. Но у ближней, крупной постройки низ
		# уходит за край экрана, и подпись пропадала совсем — так исчез
		# «Огород». Не помещается снизу — ставим сверху: подпись обязана быть
		# видна всегда, иначе постройка выглядит безымянной
		var below := bounds.end.y + 6.0
		var y := below if below + CAPTION_HEIGHT <= SCREEN_HEIGHT - CAPTION_MARGIN \
			else bounds.position.y - CAPTION_HEIGHT
		caption.position = Vector2(
			bounds.get_center().x - (size.x + 120.0) * 0.5, y)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buildings.add_child(caption)


## Первая существующая текстура из списка. Список — это лестница запасных:
## сначала настоящий домик, потом что-то похожее по смыслу.
func _first_existing(paths: Array) -> Texture2D:
	for path: String in paths:
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Постройка под курсором светлеет и чуть подрастает.
##
## Исходный масштаб запоминается при первом наведении: считать его от текущего
## значит копить погрешность на каждом входе-выходе, и через десяток наведений
## домик уползал бы в сторону.
func _hover(sprite: Sprite2D, active: bool) -> void:
	if not sprite.has_meta("base_scale"):
		sprite.set_meta("base_scale", sprite.scale)
	var base: Vector2 = sprite.get_meta("base_scale")

	var tween := create_tween()
	tween.tween_property(sprite, "scale", base * HOVER_SCALE if active else base, 0.12)
	tween.parallel().tween_property(sprite, "modulate",
		Color(1.15, 1.15, 1.05) if active else Color.WHITE, 0.12)


func _enter(entry: Dictionary) -> void:
	var scene: String = entry["scene"]

	# В лес не пускаем без защитника: иначе игрок упирается в пустой забег
	# и не понимает, почему ничего не происходит
	if scene.ends_with("RunFeed.tscn") and GameState.guardian() == null:
		_status.text = "Некого взять в лес. Сначала подружись с кем-нибудь."
		return

	get_tree().change_scene_to_file(scene)


func _refresh() -> void:
	_purse.text = UIUtil.purse_bbcode(GameState.silver, ShopState.gold)

	var guardian := GameState.guardian()
	if guardian == null:
		_guardian_label.text = "Защитника пока нет"
	else:
		var grade_mark := "" if guardian.grade == MonsterData.Rarity.COMMON \
			else " · %s" % guardian.grade_name()
		_guardian_label.text = "В лес пойдёт: %s%s (ур.%d)" % [
			guardian.display_name(), grade_mark, guardian.level,
		]

	# Готовый урожай — единственная новость, ради которой стоит зайти
	# в огород прямо сейчас. Она и висит во дворе
	var ready_plots := 0
	for i in FarmState.plot_count():
		if FarmState.is_ready(i):
			ready_plots += 1
	_status.text = "В огороде поспело: %d" % ready_plots if ready_plots > 0 else ""


## Прямоугольник ВИДИМОЙ части постройки в координатах двора.
##
## `get_used_rect()` даёт границы непрозрачных пикселей — то, что игрок
## действительно видит. Считается один раз на постройку при входе во двор:
## чтение изображения с видеопамяти дорого, но пять построек за экран
## это выдерживают, а в `_process` эта функция не заходит никогда.
func _visible_bounds(sprite: Sprite2D) -> Rect2:
	var full := Rect2(
		sprite.position - sprite.texture.get_size() * sprite.scale * 0.5,
		sprite.texture.get_size() * sprite.scale)

	var image := sprite.texture.get_image()
	if image == null:
		return full
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return full

	# Из пикселей текстуры в пиксели двора: сдвиг от левого верхнего угла
	# спрайта плюс масштаб
	return Rect2(
		full.position + Vector2(used.position) * sprite.scale,
		Vector2(used.size) * sprite.scale)
