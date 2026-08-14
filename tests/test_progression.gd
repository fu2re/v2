extends Node

## Проверки прогрессии: реестр, дружба, приручение, инвентарь, сейв.
##
## Ключевое, что здесь охраняется — обещание «ноль рандома» из GDD §6.1.
## Если приручение станет вероятностным, эти тесты обязаны упасть.

var _failed := 0
var _passed := 0


func _ready() -> void:
	# Не трогаем реальный сейв игрока: тесты гоняют настоящие подсистемы
	SaveManager.enter_test_mode()
	GameState.reset()

	_test_registry()
	_test_genre_triangle()
	_test_friendship_is_deterministic()
	_test_friendship_never_lost()
	_test_fruit_bonus()
	_test_inventory()
	_test_save_roundtrip()

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


func _test_registry() -> void:
	print("Registry: загрузка контента")
	var monsters := Registry.all_monsters()
	var fruits := Registry.all_fruits()
	check(monsters.size() >= 5, "монстры загрузились (%d)" % monsters.size())
	check(fruits.size() >= 5, "фрукты загрузились (%d)" % fruits.size())

	var slime := Registry.monster("synth_slime")
	check(slime != null, "synth_slime найден")
	if slime != null:
		check_eq(slime.genre, MonsterData.Genre.ELECTRO, "жанр синт-слайма")
		check(slime.sprite() != null, "спрайт монстра грузится: %s" % slime.sprite_path)

	# Любимый фрукт каждого монстра обязан существовать, иначе приручить
	# его штатным путём невозможно вообще
	for m in monsters:
		check(Registry.fruit(m.favorite_fruit_id) != null,
			"%s: любимый фрукт '%s' есть в реестре" % [m.id, m.favorite_fruit_id])


func _test_genre_triangle() -> void:
	print("MonsterData: треугольник жанров")
	var G := MonsterData.Genre
	check_eq(MonsterData.genre_multiplier(G.ROCK, G.DISCO), 1.4, "рок бьёт диско")
	check_eq(MonsterData.genre_multiplier(G.DISCO, G.ROCK), 0.7, "диско слаб против рока")
	check_eq(MonsterData.genre_multiplier(G.ROCK, G.FOLK), 1.0, "нет связи — без множителя")

	# Хип-хоп нейтрален в обе стороны
	for g in [G.ROCK, G.DISCO, G.FOLK, G.ELECTRO]:
		check_eq(MonsterData.genre_multiplier(G.HIPHOP, g), 1.0, "хип-хоп не имеет преимуществ")
		check_eq(MonsterData.genre_multiplier(g, G.HIPHOP), 1.0, "хип-хоп не имеет слабостей")


func _test_friendship_is_deterministic() -> void:
	print("Дружба: ноль рандома, гарантированное приручение")
	GameState.reset()
	var m := Registry.monster("disco_sprout")
	var threshold := m.friendship_threshold()

	var tamed_at := -1
	var wins := 0
	while wins < 100:
		wins += 1
		if GameState.add_friendship("disco_sprout", GameState.FRIENDSHIP_WIN):
			tamed_at = wins
			break

	# 100 порога при +10 за победу — ровно 10 побед, без разброса
	check_eq(tamed_at, int(ceil(float(threshold) / GameState.FRIENDSHIP_WIN)),
		"приручение ровно на расчётной победе, без броска кубика")
	check(GameState.is_tamed("disco_sprout"), "монстр в коллекции")

	# Шкала не переполняется
	GameState.add_friendship("disco_sprout", 999)
	check_eq(GameState.get_friendship("disco_sprout"), threshold, "дружба не выходит за порог")


func _test_friendship_never_lost() -> void:
	print("Дружба: не теряется никогда")
	GameState.reset()
	GameState.add_friendship("bass_bear", 40)
	var before := GameState.get_friendship("bass_bear")

	# Имитация смерти в забеге: теряется добыча, но не дружба (GDD §8.4)
	GameState.fruits.clear()
	GameState.add_seeds(-GameState.seeds)

	check_eq(GameState.get_friendship("bass_bear"), before,
		"после смерти в забеге дружба сохранилась")


func _test_fruit_bonus() -> void:
	print("Дружба: вклад фрукта")
	var Q := FruitData.Quality
	check_eq(GameState.friendship_from_fruit("bass_bear", "bass_plum", Q.PLAIN),
		GameState.FRIENDSHIP_FAVORITE_FRUIT, "любимый фрукт даёт полную прибавку")
	check_eq(GameState.friendship_from_fruit("bass_bear", "drum_berry", Q.PLAIN),
		GameState.FRIENDSHIP_OTHER_FRUIT, "нелюбимый даёт меньше, но даёт")

	# Качество умножает: 35 * 1.6 = 56
	check_eq(GameState.friendship_from_fruit("bass_bear", "bass_plum", Q.PERFECT), 56,
		"идеальный фрукт даёт множитель 1.6")

	# Даже худший случай продвигает вперёд — «не получилось» не бывает
	check(GameState.friendship_from_fruit("bass_bear", "drum_berry", Q.PLAIN) > 0,
		"худшее угощение всё равно двигает шкалу")


func _test_inventory() -> void:
	print("Инвентарь фруктов")
	GameState.reset()
	var Q := FruitData.Quality

	GameState.add_fruit("drum_berry", Q.PLAIN, 3)
	GameState.add_fruit("drum_berry", Q.PERFECT, 2)
	check_eq(GameState.fruit_count("drum_berry", Q.PLAIN), 3, "обычных 3")
	check_eq(GameState.fruit_count("drum_berry", Q.PERFECT), 2, "идеальных 2")
	check_eq(GameState.total_fruit_count("drum_berry"), 5, "всего 5 — качества считаются раздельно")

	check(GameState.consume_fruit("drum_berry", Q.PERFECT), "фрукт потрачен")
	check_eq(GameState.fruit_count("drum_berry", Q.PERFECT), 1, "остался 1")

	check(not GameState.consume_fruit("loop_fig", Q.PLAIN), "нельзя потратить то, чего нет")

	GameState.add_seeds(50)
	GameState.add_seeds(-80)
	check_eq(GameState.seeds, 0, "семечки не уходят в минус")


func _test_save_roundtrip() -> void:
	print("Сейв: сериализация и чтение")
	GameState.reset()
	GameState.add_friendship("banjo_moth", 75)
	GameState.add_fruit("loop_fig", FruitData.Quality.JUICY, 4)
	GameState.add_seeds(120)
	GameState.add_friendship("disco_sprout", 100)

	var snapshot := GameState.to_dict()
	GameState.reset()
	check_eq(GameState.get_friendship("banjo_moth"), 0, "состояние сброшено")

	GameState.from_dict(snapshot)
	check_eq(GameState.get_friendship("banjo_moth"), 75, "дружба восстановилась")
	check_eq(GameState.fruit_count("loop_fig", FruitData.Quality.JUICY), 4, "фрукты восстановились")
	check_eq(GameState.seeds, 120, "семечки восстановились")
	check(GameState.is_tamed("disco_sprout"), "коллекция восстановилась")

	# Сейв из будущей версии не должен ронять игру
	var future := snapshot.duplicate()
	future["version"] = 999
	GameState.from_dict(future)
	check_eq(GameState.seeds, 120, "сейв новой версии читается без падения")
