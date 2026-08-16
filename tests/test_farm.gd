extends TestHarness

## Проверки фермы.
##
## Два обещания под охраной: урожай не портится никогда (GDD §2), и перевод
## системных часов не ломает экономику (открытый вопрос GDD §15.4).

func run_tests() -> void:
	GameState.reset()
	FarmState.reset()

	_test_planting()
	_test_growth_over_time()
	_test_harvest_never_rots()
	_test_tier_sets_quality()
	_test_no_tier_is_pointless()
	_test_clock_tampering()
	_test_offline_cap()
	_test_plot_purchase()
	_test_save_roundtrip()


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


## Качество урожая задаёт СОРТ семечка.
##
## Мини-игру танца убрали, и качество переехало на то, что у фрукта уже было.
## Проверяем не таблицу саму по себе, а НАБЛЮДАЕМЫЙ результат: что собранный
## плод действительно лёг в сумку нужным качеством.
func _test_tier_sets_quality() -> void:
	print("Качество урожая задаёт сорт семечка")
	check_eq(FarmState.quality_for_tier(0), FruitData.Quality.PLAIN, "нулевой сорт — обычный")
	check_eq(FarmState.quality_for_tier(1), FruitData.Quality.JUICY, "первый сорт — сочный")
	check_eq(FarmState.quality_for_tier(3), FruitData.Quality.PERFECT, "третий сорт — идеальный")

	_fresh()
	FarmState.plant(0, "drum_berry")
	FarmState.debug_rewind(700.0)
	FarmState.tick()
	FarmState.harvest(0)
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 1,
		"дешёвое семечко дало обычный плод")


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
	FarmState.debug_rewind(200.0)
	FarmState.tick()
	var ratio := FarmState.growth_ratio(0)

	var snapshot := FarmState.to_dict()
	FarmState.reset()
	check(FarmState.is_empty_plot(0), "ферма сброшена")

	FarmState.from_dict(snapshot)
	check(not FarmState.is_empty_plot(0), "посадка восстановилась")
	check(absf(FarmState.growth_ratio(0) - ratio) < 0.05, "прогресс роста восстановился")
	check(FarmState.known_seeds.has("drum_berry"), "открытые семена восстановились")



## Ни один тир семечка не должен быть бессмысленным.
##
## Проверка появилась после разбора: качеств было три, а тиров четыре,
## и редкий инжир давал РОВНО столько же дружбы, сколько необычная сливка,
## при вчетверо большем времени роста и вдвое большей цене. Такой предмет
## не сажают никогда, и заметить это по коду нельзя — только посчитав.
func _test_no_tier_is_pointless() -> void:
	print("Каждый тир семечка чем-то лучше предыдущего")
	_fresh()

	var species := Registry.all_monsters()[0]
	var favorite: String = species.favorite_fruit_id
	var favorite_fruit := Registry.fruit(favorite)
	check(favorite_fruit != null, "любимый фрукт вида найден")
	if favorite_fruit == null:
		return

	var previous := -1
	var previous_time := -1
	for tier in range(4):
		var value := int(round(GameState.FRIENDSHIP_FAVORITE_FRUIT
			* FruitData.tier_friendship_scale(tier)))
		var seconds := Balance.fruit_grow_seconds(tier)

		check(value > previous,
			"тир %d даёт %d дружбы — не больше предыдущего (%d)" % [
				tier, value, previous])
		check(seconds > previous_time,
			"тир %d растёт %d сек — не дольше предыдущего" % [tier, seconds])
		previous = value
		previous_time = seconds

	# Верхний плод обязан быть событием, а не прибавкой: за восемь часов
	# ожидания игрок должен получить целого друга, иначе ждать незачем
	var top := int(round(GameState.FRIENDSHIP_FAVORITE_FRUIT
		* FruitData.tier_friendship_scale(3)))
	check(top >= Balance.friendship_threshold(MonsterData.Rarity.COMMON),
		"верхний плод (%d) не закрывает обычную шкалу (%d) — ночь потрачена зря" % [
			top, Balance.friendship_threshold(MonsterData.Rarity.COMMON)])
