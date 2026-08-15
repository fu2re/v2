extends TestHarness

## Уровни экземпляра (GDD §6.5).
##
## Долгая прогрессия стоит на двух опорах: уровни и снаряжение. Уровень
## растёт от побед и от угощений, и второй источник здесь не менее важен
## первого: без него фрукты становились не нужны в тот самый миг, когда вид
## приручён, и половина игры выпадала из смысла.

const COMMON := MonsterData.Rarity.COMMON
const LEGENDARY := MonsterData.Rarity.LEGENDARY


func run_tests() -> void:
	_test_level_raises_stats()
	_test_xp_curve_and_cap()
	_test_victory_gives_xp()
	_test_defeat_gives_xp_too()
	_test_progression_breaks_the_deadlock()
	_test_harder_enemy_gives_more_xp()
	_test_feeding_gives_xp()
	_test_favorite_fruit_feeds_better()
	_test_levels_survive_save()


func _test_level_raises_stats() -> void:
	print("Уровень делает экземпляр сильнее")
	var first := MonsterInstance.create("disco_sprout", COMMON)
	var tenth := MonsterInstance.create("disco_sprout", COMMON)
	tenth.level = Balance.max_level()

	check(tenth.stat_scale() > first.stat_scale(), "статы выросли")
	check(tenth.max_health() > first.max_health(), "здоровья больше")
	check(tenth.power() > first.power(), "удар сильнее")

	# Заявленное в GDD «примерно вдвое» на десятом уровне
	var ratio := tenth.stat_scale() / first.stat_scale()
	check(ratio >= 1.6 and ratio <= 2.2,
		"десятый уровень примерно вдвое сильнее первого (x%.2f)" % ratio)

	# Грейд и уровень умножаются: легендарный десятого — вершина
	var legendary := MonsterInstance.create("disco_sprout", LEGENDARY)
	legendary.level = Balance.max_level()
	check(legendary.stat_scale() > tenth.stat_scale(),
		"легендарный десятого сильнее обычного десятого")


func _test_xp_curve_and_cap() -> void:
	print("Опыт копится и упирается в потолок")
	var friend := MonsterInstance.create("bass_bear", COMMON)
	check_eq(friend.level, 1, "начинается с первого уровня")

	# Один большой кусок опыта может дать несколько уровней сразу
	var gained := friend.add_xp(Balance.xp_for_level(3))
	check(gained >= 2, "крупное угощение дало несколько уровней (%d)" % gained)

	friend.add_xp(999999)
	check_eq(friend.level, Balance.max_level(), "уровень упёрся в потолок")
	check_eq(friend.add_xp(999999), 0, "на потолке опыт больше не растит уровень")

	var progress := friend.xp_progress()
	check_eq(progress.x, progress.y, "полоска на потолке заполнена")


func _test_victory_gives_xp() -> void:
	print("Победа растит гуардиана")
	GameState.reset()
	var guardian := GameState.tame("disco_sprout", COMMON)
	RunManager.start_run(guardian.key())

	var before := guardian.xp
	RunManager.reward_guardian_xp(COMMON, false)
	check(guardian.xp > before, "опыт начислен (%d → %d)" % [before, guardian.xp])

	RunManager.go_home()


## Опыт идёт и за убежавшего монстра.
##
## Без этого новичок запирается намертво: бой с незнакомым видом обязателен,
## добить его пока нечем, а гуардиан от таких боёв не растёт — то есть
## не станет сильнее никогда. Именно в это упёрся живой прогон.
func _test_defeat_gives_xp_too() -> void:
	print("Опыт идёт и за проигранный бой")
	GameState.reset()
	var guardian := GameState.tame("disco_sprout", COMMON)
	RunManager.start_run(guardian.key())

	var before := guardian.xp
	RunManager.reward_guardian_xp(COMMON, false, false)
	check(guardian.xp > before,
		"после поражения опыт вырос (%d → %d)" % [before, guardian.xp])

	# Но победа всё же ценнее: иначе проигрывать было бы так же выгодно
	check(Balance.xp_for_defeat(COMMON) < Balance.xp_for_victory(COMMON, false),
		"за победу дают больше, чем за поражение")
	check(Balance.xp_for_defeat(COMMON) > 0, "но за поражение — не ноль")

	RunManager.go_home()


## Главная проверка проходимости: прокачка обязана выводить из тупика.
##
## Живой прогон показал, что монстра нельзя было добить даже идеальной игрой:
## восемь атак по шесть урона против Настроя в сто пять. Здесь проверяется
## и то, что чистая игра теперь побеждает, и то, что уровень с опытом
## действительно решают за игрока, который играет неровно.
func _test_progression_breaks_the_deadlock() -> void:
	print("Прокачка выводит из тупика")
	GameState.reset()
	var chart := ChartSelect.load_for(Registry.monster("synth_slime"), COMMON)
	check(chart != null, "боевой чарт загрузился")
	if chart == null:
		return

	var fresh := GameState.tame("bass_bear", COMMON)
	check(_play(chart, fresh, 1.0, 1).did_win,
		"новичок побеждает при идеальной игре — иначе бой непроходим в принципе")

	var sloppy_fresh := _win_rate(chart, fresh, 0.85)
	check(sloppy_fresh < 20, "новичок с точностью 85%% побеждает редко (%d из 40)"
		% sloppy_fresh)

	GameState.reset()
	var veteran := GameState.tame("bass_bear", COMMON)
	veteran.add_xp(Balance.xp_for_level(5))
	for i in 15:
		GameState.add_battle_experience("synth_slime")

	var sloppy_veteran := _win_rate(chart, veteran, 0.85)
	check(sloppy_veteran > sloppy_fresh * 2,
		"прокачанный с той же точностью побеждает заметно чаще (%d против %d из 40)"
			% [sloppy_veteran, sloppy_fresh])


func _win_rate(chart: ChartData, guardian: MonsterInstance, accuracy: float) -> int:
	var wins := 0
	for seed_value in 40:
		if _play(chart, guardian, accuracy, seed_value + 1).did_win:
			wins += 1
	return wins


## Проиграть чарт с заданной точностью, как это делает боевая сцена.
func _play(chart: ChartData, guardian: MonsterInstance, accuracy: float,
		seed_value: int) -> BattleState:
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", COMMON), guardian, 100, 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in chart.note_count():
		if state.is_over:
			break
		if i > 0 and chart.note_beats[i] - chart.note_beats[i - 1] > ChartValidator.SERIES_GAP:
			state.break_series()
		var hit: bool = rng.randf() < accuracy
		var grade: int = Judge.Grade.PERFECT if hit else Judge.Grade.MISS
		match chart.note_types[i]:
			ChartData.NoteType.ATTACK:
				state.register_attack(grade)
			ChartData.NoteType.SHIELD:
				if hit:
					state.block_strike()
				else:
					state.take_strike()
			ChartData.NoteType.SKILL:
				state.use_skill(grade)
			_:
				state.register_hit(grade)
	return state


## За легендарного дают больше: иначе выгоднее фармить самых безопасных.
func _test_harder_enemy_gives_more_xp() -> void:
	print("За редкого противника опыта больше")
	var over_common := Balance.xp_for_victory(COMMON, false)
	var over_legendary := Balance.xp_for_victory(LEGENDARY, false)
	check(over_legendary > over_common,
		"легендарный ценнее обычного (%d против %d)" % [over_legendary, over_common])

	check(Balance.xp_for_victory(COMMON, true) > over_common,
		"S-ранг добавляет опыта")


## Второй источник опыта: ферма остаётся нужной после приручения.
func _test_feeding_gives_xp() -> void:
	print("Угощение растит уровень")
	GameState.reset()
	var friend := GameState.tame("bass_bear", COMMON)
	GameState.add_fruit("drum_berry", FruitData.Quality.PLAIN, 2)

	var before := friend.xp
	var gained := GameState.feed(friend.key(), "drum_berry", FruitData.Quality.PLAIN)

	check(gained > 0, "угощение дало опыт (%d)" % gained)
	check(friend.xp > before, "опыт экземпляра вырос")
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 1,
		"фрукт потрачен ровно один")

	# Нечем кормить — ничего и не происходит
	GameState.reset()
	var hungry := GameState.tame("bass_bear", COMMON)
	check_eq(GameState.feed(hungry.key(), "drum_berry", FruitData.Quality.PLAIN), 0,
		"без фрукта угощение не проходит")

	# На потолке уровня угощение не тратит фрукт впустую
	GameState.add_fruit("drum_berry", FruitData.Quality.PLAIN, 1)
	hungry.level = Balance.max_level()
	check_eq(GameState.feed(hungry.key(), "drum_berry", FruitData.Quality.PLAIN), 0,
		"на потолке угощать бессмысленно")
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 1,
		"и фрукт остался цел")


func _test_favorite_fruit_feeds_better() -> void:
	print("Любимый фрукт кормит сытнее")
	var favorite := GameState.feeding_xp("bass_bear", "bass_plum", FruitData.Quality.PLAIN)
	var other := GameState.feeding_xp("bass_bear", "drum_berry", FruitData.Quality.PLAIN)
	check(favorite > other, "любимый ценнее (%d против %d)" % [favorite, other])

	# Качество тоже умножает — то же правило, что у дружбы
	var perfect := GameState.feeding_xp("bass_bear", "drum_berry", FruitData.Quality.PERFECT)
	check(perfect > other, "идеальный фрукт ценнее обычного (%d против %d)"
		% [perfect, other])

	# Тир фрукта важен: долгие культуры кормят лучше
	var high_tier := GameState.feeding_xp("bass_bear", "chord_apple", FruitData.Quality.PLAIN)
	check(high_tier > other, "фрукт старшего тира кормит сытнее")


func _test_levels_survive_save() -> void:
	print("Уровни переживают сейв")
	GameState.reset()
	var friend := GameState.tame("banjo_moth", COMMON)
	friend.add_xp(Balance.xp_for_level(3))
	var level_before := friend.level
	var xp_before := friend.xp

	var restored: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(restored)

	var back := GameState.instance(MonsterInstance.key_for("banjo_moth", COMMON))
	check(back != null, "экземпляр восстановился")
	if back != null:
		check_eq(back.level, level_before, "уровень тот же")
		check_eq(back.xp, xp_before, "опыт тот же")
