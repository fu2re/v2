extends TestHarness

## Проверки приручения.
##
## Эти тесты стоят на страже обещания «ребёнок никогда не услышит
## "не получилось"» (GDD §6.1). Любой исход встречи обязан двигать шкалу
## вперёд или хотя бы не откатывать её назад.
##
## Дружба копится отдельно на каждую пару «вид + грейд», поэтому во всех
## проверках грейд указывается явно — молчаливого «грейда вида» больше нет.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	GameState.reset()

	_test_win_always_counts()
	_test_perfect_run_gives_more()
	_test_no_fruit_still_progresses()
	_test_wrong_fruit_still_progresses()
	_test_favorite_fruit_is_faster()
	_test_grade_changes_length_not_chance()
	_test_grade_scales_are_independent()
	_test_progress_never_goes_backwards()


func _test_win_always_counts() -> void:
	print("Победа засчитывается до всякого угощения")
	GameState.reset()
	GameState.add_friendship("synth_slime", COMMON, GameState.FRIENDSHIP_WIN)
	check_eq(GameState.get_friendship("synth_slime", COMMON), GameState.FRIENDSHIP_WIN,
		"дружба выросла от одной победы")


func _test_perfect_run_gives_more() -> void:
	print("S-ранг даёт больше")
	check(GameState.FRIENDSHIP_PERFECT_WIN > GameState.FRIENDSHIP_WIN,
		"идеальный бой ценнее обычного")


func _test_no_fruit_still_progresses() -> void:
	print("Без фруктов встреча всё равно продвигает")
	GameState.reset()
	check_eq(GameState.fruits.size(), 0, "сумка пуста")

	var before := GameState.get_friendship("banjo_moth", COMMON)
	GameState.add_friendship("banjo_moth", COMMON, GameState.FRIENDSHIP_WIN)
	check(GameState.get_friendship("banjo_moth", COMMON) > before,
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
	var threshold := GameState.friendship_threshold(COMMON)
	var meetings_lazy := 0
	while GameState.get_friendship("bass_bear", COMMON) < threshold:
		GameState.add_friendship("bass_bear", COMMON, GameState.FRIENDSHIP_WIN)
		meetings_lazy += 1

	GameState.reset()
	var meetings_smart := 0
	while GameState.get_friendship("bass_bear", COMMON) < threshold:
		GameState.add_friendship("bass_bear", COMMON, GameState.FRIENDSHIP_WIN + favorite)
		meetings_smart += 1

	check(meetings_smart < meetings_lazy,
		"с любимым фруктом встреч нужно меньше (%d против %d)"
			% [meetings_smart, meetings_lazy])


## Грейд удлиняет дорогу, но не превращает её в лотерею: заполнил шкалу —
## забрал гарантированно, сколько бы встреч ни потребовалось.
func _test_grade_changes_length_not_chance() -> void:
	print("Грейд меняет длину пути, но не шанс")
	var previous_meetings := 0
	# Идём по лестнице снизу вверх и НЕ сбрасываем прогресс: перепрыгнуть
	# ступень нельзя (§6.1), поэтому каждый следующий грейд открывается
	# приручением предыдущего
	GameState.reset()
	for grade in MonsterData.RARITY_NAMES.size():
		var meetings := 0
		var tamed := false
		while meetings < 1000 and not tamed:
			meetings += 1
			tamed = GameState.add_friendship("disco_sprout", grade, GameState.FRIENDSHIP_WIN)

		var expected := int(ceil(float(GameState.friendship_threshold(grade))
			/ GameState.FRIENDSHIP_WIN))
		check_eq(meetings, expected,
			"%s: ровно %d встреч, без разброса"
				% [MonsterData.rarity_name(grade), expected])
		check(tamed, "%s приручается гарантированно" % MonsterData.rarity_name(grade))
		check(meetings > previous_meetings,
			"%s требует больше встреч, чем предыдущий грейд" % MonsterData.rarity_name(grade))
		previous_meetings = meetings

		# Приручается ИМЕННО тот экземпляр, с которым дружили
		check(GameState.has_instance("disco_sprout", grade),
			"в коллекции появился экземпляр нужного грейда")


## Главная проверка новой модели: шкалы грейдов не сообщаются между собой.
##
## Ошибку легко сделать, ключуя дружбу видом по привычке, и заметить её
## в игре трудно — она выглядит как «редкий приручился подозрительно быстро».
func _test_grade_scales_are_independent() -> void:
	print("Шкалы разных грейдов независимы")
	GameState.reset()

	# Полностью приручаем обычного
	var common_threshold := GameState.friendship_threshold(COMMON)
	GameState.add_friendship("synth_slime", COMMON, common_threshold)
	check(GameState.has_instance("synth_slime", COMMON), "обычный приручён")

	# Редкий при этом остаётся нетронутым
	var rare := MonsterData.Rarity.RARE
	check_eq(GameState.get_friendship("synth_slime", rare), 0,
		"дружба с обычным не начислилась редкому")
	check(not GameState.has_instance("synth_slime", rare), "редкий не приручился заодно")

	# И наоборот: прогресс редкого не трогает обычного
	GameState.add_friendship("synth_slime", rare, 50)
	check_eq(GameState.get_friendship("synth_slime", COMMON), common_threshold,
		"шкала обычного осталась на месте")
	check_eq(GameState.get_friendship("synth_slime", rare), 50,
		"шкала редкого выросла ровно на своё")

	# Вид считается приручённым, но не в каждом грейде
	check(GameState.is_tamed("synth_slime"), "вид числится знакомым")
	check(GameState.is_tamed_at_least("synth_slime", COMMON), "обычный превзойдён")
	check(not GameState.is_tamed_at_least("synth_slime", rare), "редкий ещё нет")


func _test_progress_never_goes_backwards() -> void:
	print("Шкала не откатывается назад")
	GameState.reset()
	var previous := 0
	for i in 30:
		GameState.add_friendship("beat_serpent", COMMON, GameState.FRIENDSHIP_WIN)
		var current := GameState.get_friendship("beat_serpent", COMMON)
		check(current >= previous, "шаг %d: шкала не уменьшилась" % i)
		previous = current
