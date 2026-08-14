extends Node

## Проверки приручения.
##
## Эти тесты стоят на страже обещания «ребёнок никогда не услышит
## "не получилось"» (GDD §6.1). Любой исход встречи обязан двигать шкалу
## вперёд или хотя бы не откатывать её назад.

var _failed := 0
var _passed := 0


func _ready() -> void:
	GameState.reset()

	_test_win_always_counts()
	_test_perfect_run_gives_more()
	_test_no_fruit_still_progresses()
	_test_wrong_fruit_still_progresses()
	_test_favorite_fruit_is_faster()
	_test_rarity_changes_length_not_chance()
	_test_progress_never_goes_backwards()

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


func _test_win_always_counts() -> void:
	print("Победа засчитывается до всякого угощения")
	GameState.reset()
	GameState.add_friendship("synth_slime", GameState.FRIENDSHIP_WIN)
	check_eq(GameState.get_friendship("synth_slime"), GameState.FRIENDSHIP_WIN,
		"дружба выросла от одной победы")


func _test_perfect_run_gives_more() -> void:
	print("S-ранг даёт больше")
	check(GameState.FRIENDSHIP_PERFECT_WIN > GameState.FRIENDSHIP_WIN,
		"идеальный бой ценнее обычного")


func _test_no_fruit_still_progresses() -> void:
	print("Без фруктов встреча всё равно продвигает")
	GameState.reset()
	check_eq(GameState.fruits.size(), 0, "сумка пуста")

	var before := GameState.get_friendship("banjo_moth")
	GameState.add_friendship("banjo_moth", GameState.FRIENDSHIP_WIN)
	check(GameState.get_friendship("banjo_moth") > before,
		"пустая сумка не отменяет прогресс — это и есть защита от фрустрации")


func _test_wrong_fruit_still_progresses() -> void:
	print("Нелюбимый фрукт тоже даёт прибавку")
	var bear := Registry.monster("bass_bear")
	var wrong := "drum_berry"
	check(bear.favorite_fruit_id != wrong, "фрукт действительно не любимый")

	var bonus := GameState.friendship_from_fruit("bass_bear", wrong, FruitData.Quality.PLAIN)
	check(bonus > 0, "прибавка положительная даже за нелюбимый фрукт")

	# Ни одно сочетание фрукта и качества не даёт ноль или минус
	for fruit in Registry.all_fruits():
		for quality in [FruitData.Quality.PLAIN, FruitData.Quality.JUICY,
				FruitData.Quality.PERFECT]:
			var value := GameState.friendship_from_fruit("bass_bear", fruit.id, quality)
			check(value > 0, "%s/%s даёт положительную прибавку"
				% [fruit.id, FruitData.quality_name(quality)])


func _test_favorite_fruit_is_faster() -> void:
	print("Любимый фрукт сокращает путь")
	var favorite := GameState.friendship_from_fruit("bass_bear", "bass_plum",
		FruitData.Quality.PLAIN)
	var other := GameState.friendship_from_fruit("bass_bear", "drum_berry",
		FruitData.Quality.PLAIN)
	check(favorite > other, "любимый фрукт выгоднее")

	# Взрослый оптимизирует: с любимым фруктом встреч нужно заметно меньше
	GameState.reset()
	var threshold := Registry.monster("bass_bear").friendship_threshold()
	var meetings_lazy := 0
	while GameState.get_friendship("bass_bear") < threshold:
		GameState.add_friendship("bass_bear", GameState.FRIENDSHIP_WIN)
		meetings_lazy += 1

	GameState.reset()
	var meetings_smart := 0
	while GameState.get_friendship("bass_bear") < threshold:
		GameState.add_friendship("bass_bear", GameState.FRIENDSHIP_WIN + favorite)
		meetings_smart += 1

	check(meetings_smart < meetings_lazy,
		"с любимым фруктом встреч нужно меньше (%d против %d)"
			% [meetings_smart, meetings_lazy])


func _test_rarity_changes_length_not_chance() -> void:
	print("Редкость меняет длину пути, но не шанс")
	for rarity in [MonsterData.Rarity.COMMON, MonsterData.Rarity.UNCOMMON,
			MonsterData.Rarity.RARE, MonsterData.Rarity.EPIC,
			MonsterData.Rarity.LEGENDARY]:
		var monsters := Registry.monsters_of_rarity(rarity)
		if monsters.is_empty():
			continue
		var m: MonsterData = monsters[0]

		GameState.reset()
		var meetings := 0
		var tamed := false
		while meetings < 1000 and not tamed:
			meetings += 1
			tamed = GameState.add_friendship(m.id, GameState.FRIENDSHIP_WIN)

		var expected := int(ceil(float(m.friendship_threshold()) / GameState.FRIENDSHIP_WIN))
		check_eq(meetings, expected,
			"%s (%s): ровно %d встреч, без разброса"
				% [m.id, MonsterData.rarity_name(rarity), expected])
		check(tamed, "%s приручается гарантированно" % m.id)


func _test_progress_never_goes_backwards() -> void:
	print("Шкала не откатывается назад")
	GameState.reset()
	var previous := 0
	for i in 30:
		GameState.add_friendship("beat_serpent", GameState.FRIENDSHIP_WIN)
		var current := GameState.get_friendship("beat_serpent")
		check(current >= previous, "шаг %d: шкала не уменьшилась" % i)
		previous = current
