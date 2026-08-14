extends Node

## Проверки петли забега.
##
## Главное здесь — мягкая смерть (GDD §8.4). Коллекция и дружба обязаны
## пережить любое поражение: терять можно только добычу текущего забега.

var _failed := 0
var _passed := 0


func _ready() -> void:
	# Не трогаем реальный сейв игрока: тесты гоняют настоящие подсистемы
	SaveManager.enter_test_mode()
	GameState.reset()
	RunManager.set_seed(20260814)

	_test_start_run()
	_test_glade_distribution()
	_test_rarity_shifts_with_depth()
	_test_rewards_grow_with_depth()
	_test_go_home_keeps_everything()
	_test_death_keeps_collection()
	_test_death_halves_loot()
	_test_groove_is_shared_across_glades()
	_test_loop_is_closed()
	_test_seeds_survive_death()

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


func _test_start_run() -> void:
	print("Старт забега")
	check(RunManager.start_run("disco_sprout"), "забег стартовал")
	check(RunManager.is_active, "забег активен")
	check_eq(RunManager.depth, 0, "глубина ноль до первого свайпа")
	check_eq(RunManager.groove, RunManager.max_groove, "Ритм полный")

	check(not RunManager.start_run("no_such_monster"), "несуществующий гуардиан отклонён")

	var first := RunManager.advance()
	check(first != null, "первая поляна выдана")
	check_eq(RunManager.depth, 1, "глубина выросла")
	RunManager.go_home()


func _test_glade_distribution() -> void:
	print("Доли типов полян")
	RunManager.start_run("disco_sprout")
	var counts := {}
	const SAMPLES := 4000
	for i in SAMPLES:
		var g := RunManager.advance()
		counts[g.type] = counts.get(g.type, 0) + 1
	RunManager.go_home()

	# Бой должен доминировать: лента — поток боёв, а не меню
	var battle_share := float(counts.get(Glade.Type.BATTLE, 0)) / SAMPLES
	check(absf(battle_share - 0.65) < 0.04,
		"боёв около 65%% (получено %.1f%%)" % (battle_share * 100.0))

	for type: Glade.Type in Glade.WEIGHTS:
		check(counts.get(type, 0) > 0, "тип поляны '%s' вообще встречается"
			% Glade.TYPE_NAMES[type])

	# Каждая боевая поляна обязана нести живого монстра
	RunManager.start_run("disco_sprout")
	for i in 200:
		var g := RunManager.advance()
		if g.type == Glade.Type.BATTLE:
			check(Registry.monster(g.monster_id) != null,
				"монстр боя существует: %s" % g.monster_id)
			break
	RunManager.go_home()


func _test_rarity_shifts_with_depth() -> void:
	print("Редкость растёт с глубиной")
	var shallow: Array = RunManager.rarity_weights(0)
	var deep: Array = RunManager.rarity_weights(30)

	check(deep[0] < shallow[0], "обычных вглубь становится меньше")
	check(deep[4] > shallow[4], "легендарных вглубь становится больше")

	# Сдвиг ограничен: иначе редкость обесценится на большой глубине
	var very_deep: Array = RunManager.rarity_weights(1000)
	check_eq(very_deep, RunManager.rarity_weights(30),
		"сдвиг упирается в потолок и дальше не растёт")
	check(very_deep[0] >= 10.0, "обычные не исчезают полностью")


func _test_rewards_grow_with_depth() -> void:
	print("Награды растут с глубиной")
	RunManager.start_run("disco_sprout")
	var first := RunManager.advance()
	var shallow_reward := first.seeds_reward
	for i in 14:
		RunManager.advance()
	var deep_reward := RunManager.current_glade.seeds_reward
	RunManager.go_home()

	check(deep_reward > shallow_reward,
		"на 15-й поляне награда выше (%d против %d)" % [deep_reward, shallow_reward])


func _test_go_home_keeps_everything() -> void:
	print("Выход домой сохраняет всю добычу")
	GameState.reset()
	RunManager.start_run("disco_sprout")
	RunManager.advance()
	RunManager.add_loot_fruit("drum_berry", FruitData.Quality.PLAIN, 8)
	RunManager.add_loot_seeds(100)
	RunManager.go_home()

	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 8,
		"все фрукты дошли до сумки")
	check_eq(GameState.seeds, 100, "все семечки дошли")
	check(not RunManager.is_active, "забег закрыт")


func _test_death_keeps_collection() -> void:
	print("Смерть не трогает коллекцию и дружбу")
	GameState.reset()
	GameState.add_friendship("bass_bear", 60)
	GameState.add_friendship("disco_sprout", 100)  # приручён
	var friendship_before := GameState.get_friendship("bass_bear")

	RunManager.start_run("disco_sprout")
	RunManager.advance()
	RunManager.add_loot_seeds(50)
	RunManager.die()

	check_eq(GameState.get_friendship("bass_bear"), friendship_before,
		"дружба пережила смерть — это ядро защиты от фрустрации")
	check(GameState.is_tamed("disco_sprout"), "приручённый монстр остался в коллекции")


func _test_death_halves_loot() -> void:
	print("Смерть забирает половину добычи")
	GameState.reset()
	RunManager.start_run("disco_sprout")
	RunManager.advance()
	RunManager.add_loot_fruit("drum_berry", FruitData.Quality.PLAIN, 10)
	RunManager.add_loot_seeds(80)
	RunManager.die()

	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 5,
		"половина фруктов сохранилась")
	check_eq(GameState.seeds, 40, "половина семечек сохранилась")

	# Даже с одним фруктом игрок не должен уходить с пустыми руками навсегда:
	# проверяем, что округление не уводит в минус
	GameState.reset()
	RunManager.start_run("disco_sprout")
	RunManager.advance()
	RunManager.add_loot_fruit("echo_pear", FruitData.Quality.PLAIN, 1)
	RunManager.die()
	check(GameState.fruit_count("echo_pear", FruitData.Quality.PLAIN) >= 0,
		"округление половины не даёт отрицательных значений")


func _test_groove_is_shared_across_glades() -> void:
	print("Ритм сквозной между полянами")
	RunManager.start_run("disco_sprout")
	var full := RunManager.groove

	RunManager.advance()
	RunManager.set_groove(full - 40)
	RunManager.advance()
	check_eq(RunManager.groove, full - 40,
		"Ритм не восстановился сам на новой поляне — в этом всё напряжение забега")

	RunManager.rest_at_campfire()
	check_eq(RunManager.groove, full - 40 + RunManager.CAMPFIRE_RESTORE,
		"костёр восстанавливает Ритм")

	RunManager.restore_groove(9999)
	check_eq(RunManager.groove, RunManager.max_groove, "Ритм не превышает максимум")
	RunManager.go_home()


## Контур игры: лес -> семена -> ферма -> фрукты -> приручение -> лес.
## Если хоть одно звено рвётся, игра распадается на несвязанные мини-игры.
func _test_loop_is_closed() -> void:
	print("Контур лес → ферма → приручение замкнут")
	GameState.reset()
	FarmState.reset()

	# 1. В лесу нашли дикий куст с неизвестной культурой
	RunManager.start_run("disco_sprout")
	RunManager.advance()
	check(not FarmState.known_seeds.has("loop_fig"), "культура ещё не открыта")
	RunManager.add_loot_seed("loop_fig", 1)
	RunManager.go_home()

	# 2. Семя доехало до амбара фермы
	check(FarmState.known_seeds.has("loop_fig"), "новая культура открыта")
	check_eq(FarmState.seed_count("loop_fig"), 1, "семя в амбаре")

	# 3. Посадили, станцевали, вырастили
	check(FarmState.plant(0, "loop_fig"), "семя посажено")
	FarmState.apply_dance(0, DanceGrade.Level.PERFECT)
	FarmState.debug_rewind(86400.0)
	FarmState.tick()
	check(FarmState.is_ready(0), "выросло")
	check_eq(FarmState.harvest(0), "loop_fig", "собран фрукт")

	# 4. Фрукт годится для приручения — и это тот вид, который любит мотылёк
	var moth := Registry.monster("banjo_moth")
	check_eq(moth.favorite_fruit_id, "loop_fig", "мотылёк любит именно этот фрукт")
	check(GameState.fruit_count("loop_fig", FruitData.Quality.PERFECT) > 0,
		"идеальный фрукт в сумке")

	var bonus := GameState.friendship_from_fruit("banjo_moth", "loop_fig",
		FruitData.Quality.PERFECT)
	var plain_bonus := GameState.friendship_from_fruit("banjo_moth", "loop_fig",
		FruitData.Quality.PLAIN)
	check(bonus > plain_bonus, "танец на грядке окупился прибавкой к дружбе")

	GameState.consume_fruit("loop_fig", FruitData.Quality.PERFECT)
	GameState.add_friendship("banjo_moth", bonus)
	check(GameState.get_friendship("banjo_moth") > 0, "дружба выросла — контур замкнулся")


## Семена новых культур не теряются при смерти: это открытый прогресс,
## а не добыча. Потерять только что найденный вид ребёнок воспримет
## как наказание за то, что дошёл дальше.
func _test_seeds_survive_death() -> void:
	print("Новые культуры переживают смерть")
	GameState.reset()
	FarmState.reset()
	RunManager.start_run("disco_sprout")
	RunManager.advance()
	RunManager.add_loot_seed("chord_apple", 2)
	RunManager.add_loot_seeds(100)
	RunManager.die()

	check_eq(FarmState.seed_count("chord_apple"), 2, "семена дошли целиком")
	check(FarmState.known_seeds.has("chord_apple"), "культура осталась открытой")
	check_eq(GameState.seeds, 50, "а вот семечек половина — это добыча")
