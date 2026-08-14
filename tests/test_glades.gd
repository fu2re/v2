extends Node

## Проверки торговца и костра.
##
## Костёр — единственная точка смены гуардиана в забеге (GDD §15.1), и он
## не должен превращаться в бесплатный хил: смена переносит ДОЛЮ Ритма.

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()
	RunManager.set_seed(4242)

	_test_campfire_restores()
	_test_swap_carries_ratio_not_amount()
	_test_swap_requires_tamed()
	_test_gear_raises_run_groove()
	_test_merchant_stock_is_stable()

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


func check_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s (получено %s, ожидалось %s)" % [description, actual, expected])


func _tame(ids: Array) -> void:
	for id: String in ids:
		GameState.add_friendship(id, Registry.monster(id).friendship_threshold())


func _test_campfire_restores() -> void:
	print("Костёр восстанавливает Ритм")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run("disco_sprout")
	RunManager.set_groove(30)
	RunManager.rest_at_campfire()
	check_eq(RunManager.groove, 30 + RunManager.CAMPFIRE_RESTORE, "Ритм поднялся")
	RunManager.go_home()


func _test_swap_carries_ratio_not_amount() -> void:
	print("Смена гуардиана переносит долю Ритма, а не число")
	GameState.reset()
	_tame(["disco_sprout", "beat_serpent"])

	RunManager.start_run("disco_sprout")
	var small_max := RunManager.max_groove
	RunManager.set_groove(int(small_max * 0.5))

	check(RunManager.swap_guardian("beat_serpent"), "смена прошла")
	check_eq(RunManager.guardian_id, "beat_serpent", "гуардиан сменился")

	var big_max := RunManager.max_groove
	check(big_max > small_max, "у змея запас больше")

	var ratio := float(RunManager.groove) / float(big_max)
	check(absf(ratio - 0.5) < 0.02,
		"перенеслась доля 50%%, а не число (получено %.2f)" % ratio)

	# Если бы переносилось число, смена на крупного стала бы кнопкой хила
	check(RunManager.groove < big_max, "смена не долечила до полного — костёр не хил")
	RunManager.go_home()


func _test_swap_requires_tamed() -> void:
	print("Позвать можно только друга")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run("disco_sprout")
	check(not RunManager.swap_guardian("beat_serpent"), "неприручённого позвать нельзя")
	check_eq(RunManager.guardian_id, "disco_sprout", "гуардиан не сменился")
	RunManager.go_home()

	check(not RunManager.swap_guardian("disco_sprout"), "вне забега смена не работает")


func _test_gear_raises_run_groove() -> void:
	print("Амулет поднимает Ритм в забеге")
	GameState.reset()
	_tame(["disco_sprout"])
	RunManager.start_run("disco_sprout")
	var bare := RunManager.max_groove
	RunManager.go_home()

	GameState.add_gear("heartwood_amulet")
	GameState.equip("disco_sprout", "heartwood_amulet")
	RunManager.start_run("disco_sprout")
	check(RunManager.max_groove > bare,
		"амулет поднял запас забега (%d против %d)" % [RunManager.max_groove, bare])
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
