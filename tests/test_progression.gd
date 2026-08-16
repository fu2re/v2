extends TestHarness

## Проверки прогрессии: реестр, дружба, приручение, инвентарь, сейв.
##
## Ключевое, что здесь охраняется — обещание «ноль рандома» из GDD §6.1.
## Если приручение станет вероятностным, эти тесты обязаны упасть.

func run_tests() -> void:
	GameState.reset()

	_test_registry()
	_test_genre_triangle()
	_test_friendship_is_deterministic()
	_test_friendship_never_lost()
	_test_fruit_bonus()
	_test_inventory()
	_test_save_roundtrip()


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
		check_eq(MonsterData.genre_multiplier(G.LATIN, g), 1.0, "латина не имеет преимуществ")
		check_eq(MonsterData.genre_multiplier(g, G.LATIN), 1.0, "латина не имеет слабостей")


func _test_friendship_is_deterministic() -> void:
	print("Дружба: ноль рандома, гарантированное приручение")
	GameState.reset()
	var common := MonsterData.Rarity.COMMON
	var threshold := GameState.friendship_threshold(common)

	var tamed_at := -1
	var wins := 0
	while wins < 100:
		wins += 1
		if GameState.add_friendship("disco_sprout", common, GameState.FRIENDSHIP_WIN):
			tamed_at = wins
			break

	# 100 порога при +10 за победу — ровно 10 побед, без разброса
	check_eq(tamed_at, int(ceil(float(threshold) / GameState.FRIENDSHIP_WIN)),
		"приручение ровно на расчётной победе, без броска кубика")
	check(GameState.is_tamed("disco_sprout"), "монстр в коллекции")
	check(GameState.has_instance("disco_sprout", common), "приручён именно обычный экземпляр")

	# Шкала своего грейда не переполняется
	GameState.add_friendship("disco_sprout", common, 999)
	check_eq(GameState.get_friendship("disco_sprout", common), threshold,
		"дружба не выходит за порог своего грейда")

	# А у соседнего грейда она вообще не двигалась
	check_eq(GameState.get_friendship("disco_sprout", MonsterData.Rarity.RARE), 0,
		"шкала редкого осталась нетронутой")


func _test_friendship_never_lost() -> void:
	print("Дружба: не теряется никогда")
	GameState.reset()
	var common := MonsterData.Rarity.COMMON
	GameState.add_friendship("bass_bear", common, 40)
	var before := GameState.get_friendship("bass_bear", common)

	# Имитация смерти в забеге: теряется добыча, но не дружба (GDD §8.4)
	GameState.fruits.clear()
	GameState.add_silver(-GameState.silver)

	check_eq(GameState.get_friendship("bass_bear", common), before,
		"после смерти в забеге дружба сохранилась")


func _test_fruit_bonus() -> void:
	print("Дружба: вклад фрукта")
	var Q := FruitData.Quality
	check(GameState.friendship_from_fruit("bass_bear", "bass_plum", Q.PLAIN)
		> GameState.friendship_from_fruit("bass_bear", "drum_berry", Q.PLAIN),
		"любимый фрукт даёт больше нелюбимого")
	check_eq(GameState.friendship_from_fruit("bass_bear", "drum_berry", Q.PLAIN),
		GameState.FRIENDSHIP_OTHER_FRUIT, "нелюбимый даёт меньше, но даёт")

	# Щедрость задаёт ТИР семечка, а не качество: у любимой сливки тир 1,
	# поэтому прибавка выше базовой ровно на его множитель
	var plum := Registry.fruit("bass_plum")
	check_eq(GameState.friendship_from_fruit("bass_bear", "bass_plum", Q.PLAIN),
		int(round(GameState.FRIENDSHIP_FAVORITE_FRUIT
			* FruitData.tier_friendship_scale(plum.tier))),
		"прибавка считается от тира семечка")

	# И тир действительно что-то меняет: верхний плод щедрее нижнего
	var apple := Registry.fruit("chord_apple")
	check(FruitData.tier_friendship_scale(apple.tier)
		> FruitData.tier_friendship_scale(0),
		"верхний тир щедрее нижнего")

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

	GameState.add_silver(50)
	GameState.add_silver(-80)
	check_eq(GameState.silver, 0, "серебро не уходят в минус")


func _test_save_roundtrip() -> void:
	print("Сейв: сериализация и чтение")
	GameState.reset()
	var common := MonsterData.Rarity.COMMON
	var rare := MonsterData.Rarity.RARE

	GameState.add_friendship("banjo_moth", common, 75)
	GameState.add_fruit("loop_fig", FruitData.Quality.JUICY, 4)
	GameState.add_silver(120)
	GameState.add_friendship("disco_sprout", common, GameState.friendship_threshold(common))
	# Второй экземпляр того же вида, но другого грейда — именно это отличает
	# новую схему от старой, и именно это должно пережить сейв
	GameState.add_friendship("disco_sprout", rare, GameState.friendship_threshold(rare))
	GameState.instance(MonsterInstance.key_for("disco_sprout", rare)).add_xp(150)

	var snapshot := GameState.to_dict()
	GameState.reset()
	check_eq(GameState.get_friendship("banjo_moth", common), 0, "состояние сброшено")

	GameState.from_dict(snapshot)
	check_eq(GameState.get_friendship("banjo_moth", common), 75, "дружба восстановилась")
	check_eq(GameState.fruit_count("loop_fig", FruitData.Quality.JUICY), 4, "фрукты восстановились")
	check_eq(GameState.silver, 120, "серебро восстановились")
	check(GameState.has_instance("disco_sprout", common), "обычный экземпляр восстановился")
	check(GameState.has_instance("disco_sprout", rare), "редкий экземпляр восстановился")

	var restored := GameState.instance(MonsterInstance.key_for("disco_sprout", rare))
	check(restored != null and restored.level > 1, "уровень экземпляра пережил сейв")

	# Через настоящий JSON: ключи словарей там становятся строками, и без
	# обратного приведения коллекция молча теряется
	var parsed: Variant = JSON.parse_string(JSON.stringify(snapshot))
	GameState.reset()
	GameState.from_dict(parsed)
	check(GameState.has_instance("disco_sprout", rare),
		"экземпляр пережил круг через настоящий JSON")
	check_eq(GameState.get_friendship("banjo_moth", common), 75,
		"дружба пережила круг через настоящий JSON")
