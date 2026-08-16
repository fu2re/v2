extends TestHarness

## Двор усадьбы и торговец (GDD §8.2.2).
##
## Двор — единственная развилка игры: отсюда расходятся все места и сюда же
## возвращаются. Если постройка перестанет открываться или из места пропадёт
## дорога обратно, игрок окажется заперт — а это ровно тот класс поломок,
## который компиляция пропускает (CLAUDE.md).

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	await _test_lobby_opens_every_place()
	await _test_forest_needs_a_guardian()
	await _test_every_place_returns_to_lobby()
	_test_farm_stock_always_has_seeds()
	_test_rotation_is_time_based()
	_test_buying_costs_silver()
	_test_forest_stock_is_stable()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _open_lobby() -> Node2D:
	var lobby := preload("res://scenes/lobby/Lobby.tscn").instantiate()
	add_child(lobby)
	await _frames(3)
	return lobby


## У каждой постройки должна быть живая кнопка и существующая сцена.
func _test_lobby_opens_every_place() -> void:
	print("Во дворе открываются все места")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)

	var lobby: Node2D = await _open_lobby()

	for entry: Dictionary in lobby.BUILDINGS:
		var node_name: String = entry["node"]
		var scene: String = entry["scene"]

		check(ResourceLoader.exists(scene), "%s: сцена существует (%s)"
			% [entry["title"], scene])

		# Постройка либо стоит во дворе с кнопкой, либо честно спрятана,
		# потому что её арт ещё не нарисован
		var sprite: Sprite2D = lobby._buildings.get_node_or_null(node_name)
		check(sprite != null, "%s: узел постройки на месте" % entry["title"])
		if sprite == null:
			continue

		if sprite.visible:
			check(lobby._hotspots.has(node_name),
				"%s: у видимой постройки есть кнопка" % entry["title"])
		else:
			note("%s: арт ещё не нарисован, постройка скрыта" % entry["title"])

	lobby.queue_free()
	await _frames(2)


## В лес без защитника не пускают — иначе игрок упрётся в пустой забег.
func _test_forest_needs_a_guardian() -> void:
	print("Без защитника лес не пускает")
	GameState.reset()
	FarmState.reset()

	var lobby: Node2D = await _open_lobby()
	var forest: Dictionary = {}
	for entry: Dictionary in lobby.BUILDINGS:
		if String(entry["scene"]).ends_with("RunFeed.tscn"):
			forest = entry

	check(not forest.is_empty(), "постройка леса найдена")
	if not forest.is_empty():
		lobby._enter(forest)
		await _frames(1)
		# Сцена не сменилась, зато игроку сказали, почему
		check(not lobby._status.text.is_empty(),
			"двор объяснил отказ: [%s]" % lobby._status.text)

	lobby.queue_free()
	await _frames(2)


## Из каждого места есть дорога назад. Заперть игрока в комнате — худшее,
## что может сделать навигация.
func _test_every_place_returns_to_lobby() -> void:
	print("Из каждого места есть путь во двор")
	GameState.reset()
	FarmState.reset()
	GameState.tame("disco_sprout", COMMON)

	var places := [
		"res://scenes/farm/Farm.tscn",
		"res://scenes/collection/Collection.tscn",
		"res://scenes/inventory/Inventory.tscn",
		"res://scenes/merchant/Merchant.tscn",
	]

	for path: String in places:
		# Тип явно: load() возвращает Variant, и вывод типа невозможен
		var packed: PackedScene = load(path)
		var place: Node = packed.instantiate()
		add_child(place)
		await _frames(2)

		var back: Button = place.get_node_or_null("BackButton")
		check(back != null, "%s: кнопка возврата на месте" % path)
		if back != null:
			check(back.visible and not back.disabled,
				"%s: кнопка возврата доступна" % path)
			# Наличия кнопки мало: несработавшая кнопка выглядит точно так же,
			# как рабочая, и запирает игрока в комнате. Проверяем, что к ней
			# вообще кто-то подключён — мутационный прогон показал, что без
			# этой строки тест пропускает отключённый обработчик
			check(not back.pressed.get_connections().is_empty(),
				"%s: кнопка возврата подключена к обработчику" % path)

		place.queue_free()
		await _frames(2)


## Семена продаются ВСЕГДА: без них новая ферма — пустой экран, и «опоздал
## к витрине» превратилось бы в «не могу играть».
func _test_farm_stock_always_has_seeds() -> void:
	print("Семена в лавке есть при любой витрине")
	for rotation in [0, 1, 7, 42, 999]:
		var stock := MerchantStock.farm_stock(rotation)
		var seeds := 0
		for item: Resource in stock:
			if item is FruitData:
				seeds += 1
		check(seeds > 0, "витрина %d: семена в продаже (%d)" % [rotation, seeds])
		check(stock.size() > seeds, "витрина %d: есть и другой товар" % rotation)


## Витрина считается от часов, а не от рандома: перезаход в игру
## не должен перебрасывать товар.
func _test_rotation_is_time_based() -> void:
	print("Витрина зависит от времени, а не от случая")
	var stamp := 1_700_000_000
	check_eq(MerchantStock.rotation_index(stamp), MerchantStock.rotation_index(stamp),
		"один и тот же момент даёт ту же витрину")

	var next := stamp + MerchantStock.ROTATION_SECONDS
	check(MerchantStock.rotation_index(next) > MerchantStock.rotation_index(stamp),
		"через десять минут витрина другая")

	# И состав действительно меняется, а не только номер
	var before := MerchantStock.farm_stock(MerchantStock.rotation_index(stamp))
	var after := MerchantStock.farm_stock(MerchantStock.rotation_index(next))
	var differs := false
	for i in mini(before.size(), after.size()):
		if before[i] != after[i]:
			differs = true
	check(differs, "состав витрины обновился")

	var left := MerchantStock.seconds_until_rotation(stamp)
	check(left > 0 and left <= MerchantStock.ROTATION_SECONDS,
		"до смены витрины осталось разумное время (%d с)" % left)


func _test_buying_costs_silver() -> void:
	print("Покупка тратит серебро")
	GameState.reset()
	FarmState.reset()

	var stock := MerchantStock.farm_stock(0)
	check(not stock.is_empty(), "на витрине есть товар")
	if stock.is_empty():
		return

	var item: Resource = stock[0]
	var price := MerchantStock.price_of(item)
	check(price > 0, "у товара есть цена")

	# Пустой кошелёк — покупка не проходит и ничего не списывает
	check(not MerchantStock.buy(item), "без серебра купить нельзя")
	check_eq(GameState.silver, 0, "и ничего не списалось")

	GameState.add_silver(price * 2)
	check(MerchantStock.buy(item), "с серебром покупка проходит")
	check_eq(GameState.silver, price, "списана ровно цена")

	# Купленное действительно попало к игроку
	if item is FruitData:
		check(FarmState.seed_count(item.id) > 0, "семя легло в мешок")
	else:
		check(GameState.gear_count(item.id) > 0, "вещь легла в сундук")


## У лесного торговца витрина привязана к глубине: игрок, увидевший товар
## и решивший сначала добить бой, обязан застать его на месте.
func _test_forest_stock_is_stable() -> void:
	print("Лесной торговец не меняет товар")
	var first := MerchantStock.forest_stock(7)
	var again := MerchantStock.forest_stock(7)
	check_eq(first.size(), MerchantStock.FOREST_SLOTS, "три товара")

	var same := true
	for i in first.size():
		if first[i] != again[i]:
			same = false
	check(same, "повторный заход даёт тот же товар")

	var other := MerchantStock.forest_stock(8)
	var differs := false
	for i in first.size():
		if first[i] != other[i]:
			differs = true
	check(differs, "на другой глубине товар другой")
