extends TestHarness

## Поляна отдаёт своё ровно один раз.
##
## Найдено на живом прогоне: один и тот же куст можно было трясти сто раз
## подряд, набивая сумку бесконечно. Тот же изъян был у костра (лечение
## без предела), у дикого куста, у бабушки и у события — все они срабатывали
## на каждый тап, потому что разрешение поляны нигде не запоминалось.
##
## Проверяется наблюдаемый результат: сколько добра прибавилось после
## ВТОРОГО нажатия. Проверять флаг бессмысленно — он и был бы верным.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	await _test_wild_bush_gives_once()
	await _test_loot_bush_gives_once()
	await _test_campfire_heals_once()
	await _test_granny_asks_once()
	await _test_merchant_can_be_reopened()
	await _test_next_glade_resets_it()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _feed_with(glade: Glade) -> Node:
	GameState.reset()
	FarmState.reset()
	RunManager.set_seed(2024)
	GameState.tame("disco_sprout", COMMON)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(2)

	RunManager.current_glade = glade
	feed._glade_cleared = false
	feed._glade_used = false
	feed._show_glade(glade)
	await _frames(1)
	return feed


func _make(type: Glade.Type, encounter := Glade.Encounter.MERCHANT) -> Glade:
	var glade := Glade.new()
	glade.type = type
	glade.encounter = encounter
	glade.depth = 4
	glade.monster_id = "synth_slime"
	glade.fruit_id = "drum_berry"
	glade.silver_reward = 12
	return glade


## Сколько всего добра у игрока: любое изменение здесь после второго
## нажатия и есть баг.
func _wealth() -> int:
	var total := RunManager.run_silver + GameState.total_potions()
	for count: int in RunManager.run_seed_bag.values():
		total += count
	for count: int in RunManager.run_fruits.values():
		total += count
	total += GameState.owned_gear_ids().size()
	return total


func _test_wild_bush_gives_once() -> void:
	print("Дикий куст обирается один раз")
	var feed: Node = await _feed_with(_make(Glade.Type.WILD_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()
	check(after_first > 0, "первый сбор что-то дал (%d)" % after_first)

	for i in 5:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), after_first, "пять повторных тапов не дали ничего")
	check(not feed._action_button.visible, "кнопка сбора убрана")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _test_loot_bush_gives_once() -> void:
	print("Куст с гостинцами трясётся один раз")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.LOOT_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()
	check(after_first > 0, "первое потряхивание что-то дало (%d)" % after_first)

	# Ровно то, что нашлось в игре: сто раз подряд по одному кусту
	for i in 20:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), after_first, "двадцать повторов не дали ничего")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _test_campfire_heals_once() -> void:
	print("Костёр лечит один раз")
	var feed: Node = await _feed_with(_make(Glade.Type.CAMPFIRE))
	RunManager.set_health(10)

	feed._resolve_glade()
	await _frames(1)
	var after_first := RunManager.health
	check(after_first > 10, "первый привал вылечил (%d)" % after_first)

	for i in 10:
		feed._resolve_glade()
		await _frames(1)
	check_eq(RunManager.health, after_first, "десять повторов не долечили")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _test_granny_asks_once() -> void:
	print("Бабушка просит один раз")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.GRANNY))
	RunManager.add_loot_silver(200)

	feed._resolve_glade()
	await _frames(1)
	var wealth_after_first := _wealth()

	for i in 10:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), wealth_after_first, "повторные подходы ничего не меняют")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Торговец — исключение: к прилавку можно вернуться, он ничего не раздаёт
## даром, а запирать игрока на одном заходе значило бы наказывать
## за случайное закрытие панели.
func _test_merchant_can_be_reopened() -> void:
	print("К торговцу можно вернуться")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.MERCHANT))

	feed._resolve_glade()
	await _frames(1)
	check(feed._panel_box.visible, "прилавок открылся")

	feed._close_panel()
	await _frames(1)
	check(feed._action_button.visible, "кнопка «Товар» осталась")

	feed._resolve_glade()
	await _frames(1)
	check(feed._panel_box.visible, "прилавок открылся снова")
	check_eq(_wealth(), 0, "но сам по себе он ничего не выдал")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## На следующей поляне всё начинается заново — иначе игрок обошёл бы
## лес, собрав ровно одну поляну.
func _test_next_glade_resets_it() -> void:
	print("Следующая поляна снова щедра")
	var feed: Node = await _feed_with(_make(Glade.Type.WILD_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()

	# Идём дальше и собираем всё, что дают, пока не попадётся дающая поляна
	var gained := false
	for i in 30:
		feed._next_glade()
		await _frames(1)
		var glade := RunManager.current_glade
		if glade == null or glade.type == Glade.Type.BATTLE:
			continue
		if glade.type == Glade.Type.ENCOUNTER \
				and glade.encounter == Glade.Encounter.MERCHANT:
			continue
		var before := _wealth()
		feed._resolve_glade()
		await _frames(1)
		if _wealth() > before:
			gained = true
			break

	check(gained, "на новой поляне добыча снова доступна")
	check(_wealth() > after_first, "и она прибавилась к прежней")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)
