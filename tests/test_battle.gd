extends Node

## Проверки боевой логики.
##
## Главное, что здесь охраняется — обещание из GDD §4.3: обычный промах
## НЕ отнимает у игрока ничего, наказывает только пропущенный щит.
## Если это сломается, игра станет злой к детям, а тесты обязаны упасть.

var _failed := 0
var _passed := 0


func _ready() -> void:
	# Не трогаем реальный сейв игрока: тесты гоняют настоящие подсистемы
	SaveManager.enter_test_mode()
	_test_groove_only_lost_to_shields()
	_test_vibe_and_combo()
	_test_genre_advantage()
	_test_depth_scaling()
	_test_victory_and_defeat()
	_test_perfect_run()
	_test_snack()

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


func _make(monster_id := "synth_slime", guardian_id := "disco_sprout",
		groove := 100, depth := 0) -> BattleState:
	var s := BattleState.new()
	s.setup(Registry.monster(monster_id), Registry.monster(guardian_id), groove, depth)
	return s


func _test_groove_only_lost_to_shields() -> void:
	print("Ритм теряется только от пропущенного щита")
	var s := _make()
	var before := s.groove

	for i in 30:
		s.register_hit(Judge.Grade.MISS)
	check_eq(s.groove, before, "30 обычных промахов не отняли Ритм")
	check_eq(s.combo, 0, "но комбо сбито")

	s.take_strike()
	check_eq(s.groove, before - BattleState.STRIKE_DAMAGE, "пропущенный щит отнял Ритм")

	s.block_strike()
	check_eq(s.groove, before - BattleState.STRIKE_DAMAGE, "принятый щит Ритм не отнимает")
	check(s.combo > 0, "принятый щит наращивает комбо")


func _test_vibe_and_combo() -> void:
	print("Настрой сбивается с учётом комбо")
	var s := _make()

	var first := s.register_hit(Judge.Grade.PERFECT)
	check(first > 0, "идеальное попадание сбивает Настрой")

	var good := _make().register_hit(Judge.Grade.GOOD)
	check(good < first, "Good слабее Perfect")

	var late := _make().register_hit(Judge.Grade.EARLY_LATE)
	check(late < good, "Early/Late слабее Good")
	check_eq(_make().register_hit(Judge.Grade.MISS), 0, "промах не сбивает Настрой")

	# Комбо усиливает: на 10-м попадании множитель 1.5
	var s2 := _make()
	var hits: Array[int] = []
	for i in 12:
		hits.append(s2.register_hit(Judge.Grade.PERFECT))
	check(hits[10] > hits[0], "с ростом комбо урон по Настрою растёт")
	check_eq(s2.max_combo, 12, "максимум комбо запомнен")


func _test_genre_advantage() -> void:
	print("Преимущество жанра")
	# disco_sprout (диско) против bass_bear (рок): диско слабо против рока
	var weak := _make("bass_bear", "disco_sprout")
	check_eq(weak.genre_multiplier(), MonsterData.DISADVANTAGE_MULTIPLIER,
		"диско в невыгоде против рока")

	# bass_bear (рок) против disco_sprout (диско): рок бьёт диско
	var strong := _make("disco_sprout", "bass_bear")
	check_eq(strong.genre_multiplier(), MonsterData.ADVANTAGE_MULTIPLIER,
		"рок в преимуществе над диско")

	check(strong.register_hit(Judge.Grade.PERFECT) > weak.register_hit(Judge.Grade.PERFECT),
		"выгодный жанр бьёт сильнее")


func _test_depth_scaling() -> void:
	print("Настрой растёт с глубиной забега")
	var shallow := _make("synth_slime", "disco_sprout", 100, 0)
	var deep := _make("synth_slime", "disco_sprout", 100, 10)
	check(deep.max_vibe > shallow.max_vibe, "на 10-й поляне монстр крепче")

	# +12% за поляну: 100 * (1 + 0.12*10) = 220
	var expected := int(round(shallow.max_vibe * (1.0 + BattleState.VIBE_DEPTH_SCALE * 10)))
	check_eq(deep.max_vibe, expected, "масштаб ровно по формуле GDD")


func _test_victory_and_defeat() -> void:
	print("Победа и поражение")
	var won := _make()
	# Счётчик в массиве, а не в переменной: лямбды в GDScript захватывают
	# локальные переменные ПО ЗНАЧЕНИЮ, и обычный счётчик снаружи не менялся бы
	var victories := [0]
	won.victory.connect(func(): victories[0] += 1)
	while not won.is_over:
		won.register_hit(Judge.Grade.PERFECT)
	check(won.did_win, "Настрой сбит — победа")
	check_eq(victories[0], 1, "сигнал победы ровно один")
	check_eq(won.vibe, 0, "Настрой обнулён, не ушёл в минус")

	# После конца боя состояние не меняется
	var vibe_after := won.vibe
	won.register_hit(Judge.Grade.PERFECT)
	check_eq(won.vibe, vibe_after, "после победы попадания уже не считаются")

	var lost := _make("synth_slime", "disco_sprout", BattleState.STRIKE_DAMAGE)
	var defeats := [0]
	lost.defeat.connect(func(): defeats[0] += 1)
	lost.take_strike()
	check(lost.is_over and not lost.did_win, "Ритм кончился — поражение")
	check_eq(defeats[0], 1, "сигнал поражения ровно один")
	check_eq(lost.groove, 0, "Ритм обнулён, не ушёл в минус")


func _test_perfect_run() -> void:
	print("S-ранг")
	var s := _make()
	for i in 10:
		s.register_hit(Judge.Grade.PERFECT)
	s.block_strike()
	check(s.is_perfect_run(), "без промахов и пропущенных атак — S-ранг")

	s.register_hit(Judge.Grade.MISS)
	check(not s.is_perfect_run(), "один промах снимает S-ранг")

	var s2 := _make()
	s2.register_hit(Judge.Grade.GOOD)
	s2.take_strike()
	check(not s2.is_perfect_run(), "пропущенная атака снимает S-ранг")


func _test_snack() -> void:
	print("Перекус восстанавливает Ритм")
	var s := _make("synth_slime", "disco_sprout", 50)
	s.restore_groove(15)
	check_eq(s.groove, 65, "Ритм восстановлен")

	s.restore_groove(9999)
	check_eq(s.groove, s.max_groove, "Ритм не превышает максимум")
