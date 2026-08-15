extends Node

## Проверки фермы.
##
## Два обещания под охраной: урожай не портится никогда (GDD §2), и перевод
## системных часов не ломает экономику (открытый вопрос GDD §15.4).

var _failed := 0
var _passed := 0


func _ready() -> void:
	# Не трогаем реальный сейв игрока: тесты гоняют настоящие подсистемы
	SaveManager.enter_test_mode()
	GameState.reset()
	FarmState.reset()

	_test_planting()
	_test_growth_over_time()
	_test_harvest_never_rots()
	_test_dance_speeds_growth()
	_test_dance_sets_quality()
	_test_dance_once_per_cycle()
	_test_clock_tampering()
	_test_offline_cap()
	_test_plot_purchase()
	_test_save_roundtrip()
	_test_dance_grade_has_no_failure()

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


func _fresh() -> void:
	GameState.reset()
	FarmState.reset()
	FarmState.add_seed("drum_berry", 10)


func _test_planting() -> void:
	print("Посадка")
	_fresh()
	check_eq(FarmState.plot_count(), FarmState.STARTING_PLOTS, "стартовых грядок 4")
	check(FarmState.is_empty_plot(0), "грядка пуста")

	check(FarmState.plant(0, "drum_berry"), "семя посажено")
	check(not FarmState.is_empty_plot(0), "грядка занята")
	check_eq(FarmState.seed_count("drum_berry"), 9, "семя израсходовано")

	check(not FarmState.plant(0, "drum_berry"), "в занятую грядку не посадить")
	check(not FarmState.plant(1, "chord_apple"), "нельзя посадить то, чего нет в амбаре")
	check(not FarmState.plant(99, "drum_berry"), "несуществующая грядка отклонена")


func _test_growth_over_time() -> void:
	print("Рост в реальном времени")
	_fresh()
	FarmState.plant(0, "drum_berry")
	check_eq(FarmState.growth_ratio(0), 0.0, "только посажено — рост нулевой")
	check(not FarmState.is_ready(0), "ещё не созрело")

	# Обычное семя зреет 10 минут; проматываем половину
	FarmState.debug_rewind(300.0)
	FarmState.tick()
	var half := FarmState.growth_ratio(0)
	check(absf(half - 0.5) < 0.05, "за половину срока выросло примерно наполовину (%.2f)" % half)

	FarmState.debug_rewind(400.0)
	FarmState.tick()
	check(FarmState.is_ready(0), "созрело после полного срока")
	check_eq(FarmState.growth_ratio(0), 1.0, "рост не превышает 100%")


func _test_harvest_never_rots() -> void:
	print("Урожай не портится")
	_fresh()
	FarmState.plant(0, "drum_berry")
	FarmState.debug_rewind(700.0)
	FarmState.tick()
	check(FarmState.is_ready(0), "созрело")

	# Ждём МЕСЯЦ и проверяем, что урожай на месте. Никаких «вернись
	# через 4 часа или потеряешь» — это запрещённая механика (GDD §2)
	FarmState.debug_rewind(86400.0 * 30)
	FarmState.tick()
	check(FarmState.is_ready(0), "через месяц урожай всё ещё ждёт")

	var harvested := FarmState.harvest(0)
	check_eq(harvested, "drum_berry", "собрано то, что сажали")
	check_eq(GameState.total_fruit_count("drum_berry"), 1, "фрукт попал в сумку")
	check(FarmState.is_empty_plot(0), "грядка освободилась")
	check_eq(FarmState.harvest(0), "", "с пустой грядки собрать нельзя")


func _test_dance_speeds_growth() -> void:
	print("Танец ускоряет рост")
	var needed := {}
	for level in [0, 1, 2, 3]:
		_fresh()
		FarmState.plant(0, "drum_berry")
		if level > 0:
			check(FarmState.apply_dance(0, level), "танец уровня %d принят" % level)
		needed[level] = FarmState.plots[0].needed

	check(needed[1] < needed[0], "слабый танец уже ускоряет")
	check(needed[2] < needed[1], "хороший танец быстрее слабого")
	check(needed[3] < needed[2], "идеальный быстрее хорошего")

	# -40% на идеальном (GDD §7.2)
	var expected: float = needed[0] * (1.0 - FarmState.DANCE_REDUCTION[3])
	check(absf(needed[3] - expected) < 1.0, "идеальный танец даёт ровно -40%")


func _test_dance_sets_quality() -> void:
	print("Танец задаёт качество урожая")
	check_eq(FarmState.quality_for_dance(0), FruitData.Quality.PLAIN, "без танца — обычный")
	check_eq(FarmState.quality_for_dance(1), FruitData.Quality.PLAIN, "слабо — обычный")
	check_eq(FarmState.quality_for_dance(2), FruitData.Quality.JUICY, "хорошо — сочный")
	check_eq(FarmState.quality_for_dance(3), FruitData.Quality.PERFECT, "идеально — идеальный")

	_fresh()
	FarmState.plant(0, "drum_berry")
	FarmState.apply_dance(0, 3)
	FarmState.debug_rewind(700.0)
	FarmState.tick()
	FarmState.harvest(0)
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PERFECT), 1,
		"идеальный танец дал идеальный фрукт")


func _test_dance_once_per_cycle() -> void:
	print("Танец один раз за цикл")
	_fresh()
	FarmState.plant(0, "drum_berry")
	check(FarmState.can_dance(0), "танцевать можно")
	check(FarmState.apply_dance(0, 2), "первый танец принят")
	check(not FarmState.can_dance(0), "второй раз нельзя")
	check(not FarmState.apply_dance(0, 3), "повторный танец отклонён — это ритуал, не гринд")

	# После сбора и новой посадки танцевать снова можно
	FarmState.debug_rewind(700.0)
	FarmState.tick()
	FarmState.harvest(0)
	FarmState.plant(0, "drum_berry")
	check(FarmState.can_dance(0), "новый цикл — новый танец")


func _test_clock_tampering() -> void:
	print("Перевод часов не ломает экономику")
	_fresh()
	FarmState.plant(0, "drum_berry")
	FarmState.debug_rewind(120.0)
	FarmState.tick()
	var honest := FarmState.growth_ratio(0)
	check(honest > 0.0, "честный рост начислен")

	# Часы уводят НАЗАД: смена пояса, перелёт, ручной перевод.
	# Рост не должен ни начисляться, ни откатываться
	FarmState.debug_rewind(-86400.0)
	FarmState.tick()
	check_eq(FarmState.growth_ratio(0), honest,
		"часы назад — рост не изменился и не откатился")

	# И игра не должна залипнуть навсегда: время снова идёт вперёд
	FarmState.debug_rewind(86400.0 + 200.0)
	FarmState.tick()
	check(FarmState.growth_ratio(0) > honest, "после возврата часов рост продолжился")


func _test_offline_cap() -> void:
	print("Оффлайн-рост ограничен сверху")
	_fresh()
	FarmState.add_seed("chord_apple", 1)
	FarmState.plant(0, "chord_apple")  # эпическое семя, 8 часов

	# Перевод часов на год вперёд не должен мгновенно доращивать всё
	FarmState.debug_rewind(86400.0 * 365)
	FarmState.tick()
	var after_cap: float = FarmState.plots[0].grown
	check(after_cap <= FarmState.MAX_OFFLINE_CREDIT + 1.0,
		"за один запуск засчитано не больше лимита (%.0f сек)" % after_cap)


func _test_plot_purchase() -> void:
	print("Расширение фермы")
	_fresh()
	var before := FarmState.plot_count()
	check(not FarmState.buy_plot(), "без серебра грядку не купить")

	GameState.add_silver(FarmState.next_plot_cost())
	check(FarmState.buy_plot(), "грядка куплена")
	check_eq(FarmState.plot_count(), before + 1, "грядок стало больше")
	check_eq(GameState.silver, 0, "серебро списаны")
	check(FarmState.next_plot_cost() > FarmState.PLOT_BASE_COST, "следующая дороже")


func _test_save_roundtrip() -> void:
	print("Сейв фермы")
	_fresh()
	FarmState.plant(0, "drum_berry")
	FarmState.apply_dance(0, 2)
	FarmState.debug_rewind(200.0)
	FarmState.tick()
	var ratio := FarmState.growth_ratio(0)

	var snapshot := FarmState.to_dict()
	FarmState.reset()
	check(FarmState.is_empty_plot(0), "ферма сброшена")

	FarmState.from_dict(snapshot)
	check(not FarmState.is_empty_plot(0), "посадка восстановилась")
	check(absf(FarmState.growth_ratio(0) - ratio) < 0.05, "прогресс роста восстановился")
	check_eq(FarmState.plots[0].dance_level, 2, "результат танца восстановился")
	check(FarmState.known_seeds.has("drum_berry"), "открытые семена восстановились")


func _test_dance_grade_has_no_failure() -> void:
	print("Танец: провала не существует")
	const NOTES := 8

	# Полный промах по всем нотам всё равно даёт уровень выше нуля.
	# Это и есть обещание «попытка обязана что-то дать» (GDD §7.2)
	check_eq(DanceGrade.level_for(0, 0, NOTES), DanceGrade.Level.WEAK,
		"ноль попаданий — всё равно не провал")
	check(DanceGrade.level_for(0, 0, NOTES) != DanceGrade.Level.SKIPPED,
		"станцевать плохо лучше, чем не танцевать")

	check_eq(DanceGrade.level_for(8, 0, NOTES), DanceGrade.Level.PERFECT, "все идеально")
	check_eq(DanceGrade.level_for(7, 1, NOTES), DanceGrade.Level.PERFECT, "почти все идеально")
	check_eq(DanceGrade.level_for(4, 2, NOTES), DanceGrade.Level.GOOD, "половина идеально — хорошо")
	check_eq(DanceGrade.level_for(1, 1, NOTES), DanceGrade.Level.WEAK, "мало попаданий — слабо")

	# SKIPPED возможен только когда нот не было вообще
	check_eq(DanceGrade.level_for(0, 0, 0), DanceGrade.Level.SKIPPED,
		"ноль нот — танца не было")

	# Уровень не падает при росте попаданий
	var previous := -1
	for perfect in range(0, NOTES + 1):
		var level: int = DanceGrade.level_for(perfect, 0, NOTES)
		check(level >= previous, "с ростом точности уровень не падает (%d попаданий)" % perfect)
		previous = level

	# Каждый уровень танца соответствует своему качеству фрукта
	check_eq(FarmState.quality_for_dance(DanceGrade.Level.PERFECT),
		FruitData.Quality.PERFECT, "идеальный танец — идеальный фрукт")
	check_eq(FarmState.quality_for_dance(DanceGrade.Level.GOOD),
		FruitData.Quality.JUICY, "хороший танец — сочный фрукт")
