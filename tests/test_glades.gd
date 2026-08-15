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
	RunManager.rest_at_campfire()
	check_eq(RunManager.health, 30 + RunManager.CAMPFIRE_RESTORE, "Ритм поднялся")
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


## Победа над монстром даёт снаряжение, и чем выше грейд — тем ценнее.
func _test_victory_gives_gear() -> void:
	print("За победу выдаётся снаряжение")
	GameState.reset()
	RunManager.set_seed(555)

	for grade in [MonsterData.Rarity.COMMON, MonsterData.Rarity.LEGENDARY]:
		var name := MonsterData.rarity_name(grade)
		var before := GameState.owned_gear_ids().size()
		var prize := RunManager.roll_victory_gear(grade)
		check(not prize.is_empty(), "%s: сундук что-то дал" % name)
		check(Registry.gear(prize) != null, "%s: выпавший предмет существует" % name)
		check(GameState.owned_gear_ids().size() >= before,
			"%s: предмет попал в сундук игрока" % name)

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
