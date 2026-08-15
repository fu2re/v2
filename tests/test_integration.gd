extends Node

## Интеграционный прогон всей игры.
##
## Юнит-тесты проверяют подсистемы поодиночке, но все найденные до сих пор
## баги жили на СТЫКАХ: оверлей читал поля, переехавшие в другой класс;
## стартовый набор выдавался только на одном экране; спрайт монстра не
## выставлялся при обходе публичного входа. Такое ловится только проходом
## целиком.

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()
	_fresh_game()

	await _test_all_scenes_instantiate()
	_test_full_player_journey()
	_test_deep_run_survives()
	_test_whole_state_survives_save()
	_test_new_player_can_reach_first_taming()

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


func _fresh_game() -> void:
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	RunManager.set_seed(20260815)
	ShopState.set_seed(20260815)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Каждая реальная сцена должна подниматься без единой ошибки.
##
## Именно так ловится класс багов «узел обращается к тому, чего больше нет»:
## компиляция их пропускает, а падают они у игрока на экране.
func _test_all_scenes_instantiate() -> void:
	print("Все сцены поднимаются без ошибок")
	var scenes := [
		"res://scenes/farm/Farm.tscn",
		"res://scenes/collection/Collection.tscn",
		"res://scenes/shop/Shop.tscn",
		"res://scenes/inventory/Inventory.tscn",
		"res://scenes/run/RunFeed.tscn",
		"res://scenes/battle/DanceBattle.tscn",
		"res://scenes/battle/TamingScreen.tscn",
		"res://scenes/farm/PlantDance.tscn",
		"res://scenes/onboarding/Onboarding.tscn",
		"res://scenes/calibration/Calibration.tscn",
		"res://tools/chart_forge/ChartForge.tscn",
	]

	for path: String in scenes:
		var packed: PackedScene = load(path)
		check(packed != null, "%s загружается" % path)
		if packed == null:
			continue

		var instance := packed.instantiate()
		check(instance != null, "%s инстанцируется" % path)
		if instance == null:
			continue

		add_child(instance)
		await _frames(3)
		check(is_instance_valid(instance), "%s пережил три кадра" % path)

		instance.queue_free()
		await _frames(2)

	Conductor.stop()


## Путь игрока целиком: лес, бой, приручение, ферма, лавка.
func _test_full_player_journey() -> void:
	print("Полный путь игрока")
	_fresh_game()

	# Стартовый набор, как его выдаёт SaveManager новой игре
	FarmState.add_seed("drum_berry", 3)
	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.set_guardian("disco_sprout")
	check(GameState.is_tamed("disco_sprout"), "стартовый друг есть")

	# 1. Уходим в лес
	check(RunManager.start_run(GameState.guardian_id()), "забег начался")

	# 2. Идём, пока не встретим бой
	var battle_glade: Glade = null
	for i in 60:
		var glade := RunManager.advance()
		if glade.type == Glade.Type.BATTLE:
			battle_glade = glade
			break
	check(battle_glade != null, "боевая поляна встретилась")
	if battle_glade == null:
		return

	# 3. Бой до победы
	var monster := Registry.monster(battle_glade.monster_id)
	var state := BattleState.new()
	state.setup(monster, Registry.monster(RunManager.guardian_id), RunManager.health,
		battle_glade.depth)
	var swings := 0
	while not state.is_over and swings < 500:
		swings += 1
		_clean_attack(state)
	check(state.did_win, "бой выигран за %d попаданий" % swings)
	check(swings < 500, "победа достижима, а не бесконечна")

	# 4. Приручение: победа плюс угощение
	var before := GameState.get_friendship(monster.id)
	GameState.add_friendship(monster.id, GameState.FRIENDSHIP_WIN)
	check(GameState.get_friendship(monster.id) > before, "дружба выросла после боя")

	# 5. Ритм переносится на следующую поляну
	RunManager.set_health(state.health)
	RunManager.add_loot_silver(battle_glade.silver_reward)
	RunManager.add_loot_seed("drum_berry", 2)

	# 6. Домой с добычей
	var seeds_before := GameState.silver
	RunManager.go_home()
	check(GameState.silver > seeds_before, "серебро доехали домой")
	check(FarmState.seed_count("drum_berry") >= 2, "семена доехали на ферму")

	# 7. Ферма: посадить, станцевать, вырастить, собрать
	check(FarmState.plant(0, "drum_berry"), "посажено")
	check(FarmState.apply_dance(0, DanceGrade.Level.PERFECT), "станцевано")
	FarmState.debug_rewind(86400.0)
	FarmState.tick()
	check(FarmState.is_ready(0), "выросло")
	check_eq(FarmState.harvest(0), "drum_berry", "собрано")
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PERFECT), 1,
		"идеальный танец дал идеальный фрукт")

	# 8. Лавка: купить и надеть косметику
	ShopState.add_gold(1000)
	ShopState.daily_limit = 999999
	var cosmetic := Registry.all_cosmetics()[0]
	check(ShopState.buy_direct(cosmetic.id), "косметика куплена")
	check(ShopState.equip(cosmetic.id), "косметика надета")

	# 9. Косметика не изменила ни одной боевой цифры.
	#
	# Сравниваем РЕЗУЛЬТАТ, а не промежуточные поля: проверка поля
	# power_bonus пропускала утечку, спрятанную в расчёте урона.
	# Мутационный прогон это показал, и тест переписан под факт.
	var geared := BattleState.new()
	geared.setup(monster, Registry.monster("disco_sprout"), 100, 0)
	var damage_with_cosmetics := _clean_attack(geared)
	var groove_with_cosmetics := geared.max_health

	var owned_backup := ShopState.owned.duplicate()
	var equipped_backup := ShopState.equipped.duplicate()
	ShopState.owned.clear()
	ShopState.equipped.clear()

	var bare := BattleState.new()
	bare.setup(monster, Registry.monster("disco_sprout"), 100, 0)
	var damage_bare := _clean_attack(bare)

	check_eq(damage_with_cosmetics, damage_bare,
		"косметика не изменила урон (%d против %d) — pay-to-win не просочился"
			% [damage_with_cosmetics, damage_bare])
	check_eq(groove_with_cosmetics, bare.max_health, "косметика не изменила Ритм")
	check_eq(geared.window_scale, bare.window_scale, "косметика не изменила окна")

	ShopState.owned = owned_backup
	ShopState.equipped = equipped_backup


## Глубокий забег не должен ломаться на росте чисел.
func _test_deep_run_survives() -> void:
	print("Глубокий забег выдерживает 60 полян")
	_fresh_game()
	GameState.add_friendship("disco_sprout", 999)
	GameState.set_guardian("disco_sprout")
	RunManager.start_run("disco_sprout")

	var battles := 0
	for i in 60:
		var glade := RunManager.advance()
		check(glade != null, "поляна %d выдана" % (i + 1))
		if glade == null:
			break
		if glade.type != Glade.Type.BATTLE:
			continue

		battles += 1
		var monster := Registry.monster(glade.monster_id)
		check(monster != null, "поляна %d: монстр существует" % glade.depth)
		if monster == null:
			continue

		var state := BattleState.new()
		state.setup(monster, Registry.monster("disco_sprout"), RunManager.health, glade.depth)
		check(state.max_vibe > 0, "глубина %d: Настрой положителен" % glade.depth)

		var swings := 0
		while not state.is_over and swings < 5000:
			swings += 1
			_clean_attack(state)
		check(state.is_over, "глубина %d: бой завершим" % glade.depth)

	check(battles > 20, "за 60 полян было больше 20 боёв (%d)" % battles)
	RunManager.go_home()


## Всё состояние целиком переживает запись и чтение через настоящий JSON.
func _test_whole_state_survives_save() -> void:
	print("Всё состояние переживает сейв")
	_fresh_game()

	GameState.add_friendship("bass_bear", 70)
	GameState.add_friendship("disco_sprout", 999)
	GameState.set_guardian("disco_sprout")
	GameState.add_fruit("loop_fig", FruitData.Quality.JUICY, 3)
	GameState.add_silver(250)
	GameState.add_gear("spring_boots")
	GameState.equip("disco_sprout", "spring_boots")

	FarmState.add_seed("echo_pear", 4)
	FarmState.plant(0, "echo_pear")
	FarmState.apply_dance(0, DanceGrade.Level.GOOD)

	ShopState.add_gold(600)
	ShopState.daily_limit = 999999
	var cosmetic := Registry.all_cosmetics()[0]
	ShopState.buy_direct(cosmetic.id)
	ShopState.pity_counter = 9

	var snapshot := {
		"game": GameState.to_dict(),
		"farm": FarmState.to_dict(),
		"shop": ShopState.to_dict(),
	}
	var restored: Dictionary = JSON.parse_string(JSON.stringify(snapshot))

	_fresh_game()
	GameState.from_dict(restored["game"])
	FarmState.from_dict(restored["farm"])
	ShopState.from_dict(restored["shop"])

	check_eq(GameState.get_friendship("bass_bear"), 70, "дружба восстановилась")
	check_eq(GameState.guardian_id(), "disco_sprout", "гуардиан восстановился")
	check_eq(GameState.fruit_count("loop_fig", FruitData.Quality.JUICY), 3, "фрукты на месте")
	check_eq(GameState.silver, 250, "серебро на месте")
	check(GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS) != null,
		"снаряжение осталось надетым")
	check(not FarmState.is_empty_plot(0), "грядка засажена")
	check_eq(FarmState.plots[0].dance_level, DanceGrade.Level.GOOD, "танец запомнен")
	check(ShopState.is_owned(cosmetic.id), "покупка на месте")
	check_eq(ShopState.pity_counter, 9, "счётчик pity на месте")


## Новый игрок обязан дойти до первого приручения без тупика.
##
## Самый вероятный способ сломать игру для новичка — оставить его без
## стартового гуардиана, семян или доступных монстров.
func _test_new_player_can_reach_first_taming() -> void:
	print("Новый игрок доходит до первого друга")
	_fresh_game()

	# Ровно то, что выдаёт SaveManager новой игре.
	#
	# Существование стартового контента проверяется ЯВНО. Раньше тест
	# при опечатке в id просто выполнял меньше проверок и всё равно
	# отчитывался «0 провалено» — мутационный прогон это вскрыл.
	var starter := Registry.monster(SaveManager.STARTER_GUARDIAN)
	check(starter != null,
		"стартовый гуардиан '%s' существует в реестре" % SaveManager.STARTER_GUARDIAN)
	if starter == null:
		return

	check(not SaveManager.STARTER_SEEDS.is_empty(), "стартовые семена заданы")
	for fruit_id: String in SaveManager.STARTER_SEEDS:
		check(Registry.fruit(fruit_id) != null, "стартовое семя '%s' существует" % fruit_id)
		FarmState.add_seed(fruit_id, SaveManager.STARTER_SEEDS[fruit_id])

	GameState.add_friendship(SaveManager.STARTER_GUARDIAN, starter.friendship_threshold())
	GameState.set_guardian(SaveManager.STARTER_GUARDIAN)
	check_eq(GameState.guardian_id(), SaveManager.STARTER_GUARDIAN,
		"стартовый гуардиан действительно выбран")

	check(not GameState.guardian_id().is_empty(), "есть с кем идти в лес")
	check(not FarmState.available_seeds().is_empty(), "есть что сажать")

	# Дойти до нового друга, кроме стартового
	RunManager.start_run(GameState.guardian_id())
	var tamed_new := ""
	for i in 400:
		var glade := RunManager.advance()
		if glade.type != Glade.Type.BATTLE:
			continue
		if glade.monster_id == SaveManager.STARTER_GUARDIAN:
			continue
		if GameState.add_friendship(glade.monster_id, GameState.FRIENDSHIP_WIN):
			tamed_new = glade.monster_id
			break
	RunManager.go_home()

	check(not tamed_new.is_empty(), "новый друг достижим за разумное число боёв")
	check(GameState.tamed.size() >= 2, "коллекция выросла (%d)" % GameState.tamed.size())


## Провести чистую серию и ударить. Обычные биты урона не наносят,
## поэтому победить можно только так (GDD §4.3).
func _clean_attack(state: BattleState, grade := Judge.Grade.PERFECT) -> int:
	for i in BattleState.MIN_SERIES_LENGTH:
		state.register_hit(Judge.Grade.PERFECT)
	return state.register_attack(grade)
