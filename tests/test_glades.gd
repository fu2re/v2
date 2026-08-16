extends TestHarness

## Проверки торговца и костра.
##
## Костёр — единственная точка смены гуардиана в забеге (GDD §15.1), и он
## не должен превращаться в бесплатный хил: смена переносит ДОЛЮ Ритма.

func run_tests() -> void:
	GameState.reset()
	RunManager.set_seed(4242)

	_test_campfire_restores()
	_test_swap_carries_ratio_not_amount()
	_test_swap_requires_tamed()
	_test_gear_raises_run_health()
	_test_merchant_stock_is_stable()
	_test_victory_gives_gear()
	_test_wild_bush_follows_the_table()


## Завести экземпляры обычного грейда — минимальная подготовка коллекции.
func _tame(ids: Array) -> void:
	for id: String in ids:
		GameState.tame(id, MonsterData.Rarity.COMMON)


func _key(species_id: String) -> String:
	return MonsterInstance.key_for(species_id, MonsterData.Rarity.COMMON)


func _test_campfire_restores() -> void:
	print("Костёр восстанавливает Ритм")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run(_key("disco_sprout"))
	RunManager.set_health(30)
	# Костёр лечит съеденным фруктом, а не сам по себе
	GameState.add_fruit("drum_berry", FruitData.Quality.PLAIN, 1)
	var berry := Registry.fruit("drum_berry")
	RunManager.restore_health(berry.heal())
	check_eq(RunManager.health, 30 + berry.heal(), "Ритм поднялся от фрукта")
	RunManager.go_home()


func _test_swap_carries_ratio_not_amount() -> void:
	print("Смена гуардиана переносит долю Ритма, а не число")
	GameState.reset()
	_tame(["disco_sprout", "beat_serpent"])

	RunManager.start_run(_key("disco_sprout"))
	var small_max := RunManager.max_health
	RunManager.set_health(int(small_max * 0.5))

	check(RunManager.swap_guardian(_key("beat_serpent")), "смена прошла")
	check_eq(RunManager.guardian_key, _key("beat_serpent"), "гуардиан сменился")

	var big_max := RunManager.max_health
	check(big_max > small_max, "у змея запас больше")

	var ratio := float(RunManager.health) / float(big_max)
	check(absf(ratio - 0.5) < 0.02,
		"перенеслась доля 50%%, а не число (получено %.2f)" % ratio)

	# Если бы переносилось число, смена на крупного стала бы кнопкой хила
	check(RunManager.health < big_max, "смена не долечила до полного — костёр не хил")
	RunManager.go_home()


func _test_swap_requires_tamed() -> void:
	print("Позвать можно только друга")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run(_key("disco_sprout"))
	check(not RunManager.swap_guardian(_key("beat_serpent")), "неприручённого позвать нельзя")
	check_eq(RunManager.guardian_key, _key("disco_sprout"), "гуардиан не сменился")
	RunManager.go_home()

	check(not RunManager.swap_guardian(_key("disco_sprout")), "вне забега смена не работает")


func _test_gear_raises_run_health() -> void:
	print("Амулет поднимает Ритм в забеге")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run(_key("disco_sprout"))
	var bare := RunManager.max_health
	RunManager.go_home()

	GameState.add_gear("heartwood_amulet")
	GameState.equip(_key("disco_sprout"), "heartwood_amulet")
	RunManager.start_run(_key("disco_sprout"))
	check(RunManager.max_health > bare,
		"амулет поднял запас забега (%d против %d)" % [RunManager.max_health, bare])
	RunManager.go_home()


func _test_merchant_stock_is_stable() -> void:
	print("Ассортимент торговца детерминирован")
	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)

	# Игрок, увидевший товар и решивший сначала добить бой, обязан
	# застать его на месте — иначе выбор превращается в лотерею
	var first: Array = feed._merchant_stock(7)
	var again: Array = feed._merchant_stock(7)
	check_eq(first.size(), 3, "торговец показывает три позиции")
	var same := true
	for i in first.size():
		if first[i].id != again[i].id:
			same = false
	check(same, "повторный заход даёт тот же товар")

	var other: Array = feed._merchant_stock(8)
	var differs := false
	for i in first.size():
		if first[i].id != other[i].id:
			differs = true
	check(differs, "на другой глубине товар другой")

	feed.queue_free()


## Победа над монстром ИНОГДА даёт снаряжение, и чем выше грейд — тем чаще
## и тем ценнее.
##
## Именно «иногда»: сундук падал за каждую победу, и снаряжение перестало
## быть событием — вещей набиралось больше, чем игрок успевал надеть,
## а торговец стал не нужен.
func _test_victory_gives_gear() -> void:
	print("За победу иногда выдаётся снаряжение")
	GameState.reset()
	RunManager.set_seed(555)

	# Шанс растёт с грейдом: награда обязана отражать риск
	check(Balance.victory_chest_chance(MonsterData.Rarity.LEGENDARY)
		> Balance.victory_chest_chance(MonsterData.Rarity.COMMON),
		"с легендарного сундук падает чаще")
	check(Balance.victory_chest_chance(MonsterData.Rarity.COMMON) < 0.5,
		"с обычного сундук — удача, а не норма (%.0f%%)" % [
			Balance.victory_chest_chance(MonsterData.Rarity.COMMON) * 100.0])

	# Выпавшее обязано быть настоящим предметом, попавшим в сундук игрока
	for grade in [MonsterData.Rarity.COMMON, MonsterData.Rarity.LEGENDARY]:
		var name := MonsterData.rarity_name(grade)
		var dropped := 0
		for i in 200:
			var prize := RunManager.roll_victory_gear(grade)
			if prize.is_empty():
				continue
			dropped += 1
			check(Registry.gear(prize) != null,
				"%s: выпавший предмет существует" % name)
		check(dropped > 0, "%s: за две сотни побед сундук выпал хоть раз" % name)

	# Чем выше грейд ЭКЗЕМПЛЯРА, тем дороже средняя добыча: награда обязана
	# отражать риск, иначе за редкими незачем идти
	var cheap_total := 0
	var rich_total := 0
	for i in 60:
		GameState.reset()
		var a := Registry.gear(RunManager.roll_victory_gear(MonsterData.Rarity.COMMON))
		var b := Registry.gear(RunManager.roll_victory_gear(MonsterData.Rarity.LEGENDARY))
		if a != null:
			cheap_total += a.price
		if b != null:
			rich_total += b.price

	check(rich_total > cheap_total,
		"с редкого монстра добыча ценнее (%d против %d)" % [rich_total, cheap_total])
	GameState.reset()


## Куст выдаёт по ТАБЛИЦЕ, а не по числу в коде.
##
## Живой отчёт: «почему такой большой лут? ожидался очень мелкий шанс
## на дроп плода». В коде стояло жёсткое «два плода и семя», а таблица,
## где записаны пятнадцать процентов на ОДИН плод, не читалась вовсе:
## куст исправно выдавал два золотых яблока подряд — восемь часов роста
## каждое, — и грядка становилась необязательной.
##
## Доля сверяется С ТАБЛИЦЕЙ, а не с зашитым здесь числом: иначе тест
## пришлось бы править при каждой подкрутке баланса, и он перестал бы
## что-либо охранять.
func _test_wild_bush_follows_the_table() -> void:
	print("Дикий куст выдаёт по таблице")
	var chance := Balance.wild_bush_fruit_chance()
	check(chance > 0.0 and chance < 0.5,
		"плод с куста — редкая удача, а не норма (%.0f%%)" % (chance * 100.0))

	var runs := 600
	var with_fruit := 0
	var fruits_total := 0
	var seeds_total := 0
	RunManager.set_seed(31337)
	for i in runs:
		RunManager.run_fruits.clear()
		RunManager.run_seed_bag.clear()
		var picked := RunManager.harvest_wild_bush("chord_apple", 8)
		if picked > 0:
			with_fruit += 1
			fruits_total += picked
		for count: int in RunManager.run_seed_bag.values():
			seeds_total += count

	# Семена — то, ради чего к кусту подходят: они падают ВСЕГДА
	check_eq(seeds_total, runs * Balance.wild_bush_seeds(),
		"семя даёт каждый куст")

	var observed := float(with_fruit) / float(runs)
	check(absf(observed - chance) < 0.06,
		"доля плодоносных кустов близка к таблице: %.0f%% против %.0f%%"
			% [observed * 100.0, chance * 100.0])

	# И удачный куст даёт РОВНО столько, сколько сказано, — не больше
	if with_fruit > 0:
		check_eq(fruits_total, with_fruit * Balance.wild_bush_lucky_fruits(),
			"удачный куст даёт ровно %d плод(а)" % Balance.wild_bush_lucky_fruits())

	RunManager.run_fruits.clear()
	RunManager.run_seed_bag.clear()
