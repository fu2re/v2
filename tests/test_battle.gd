extends Node

## Проверки боевой логики.
##
## Главное, что здесь охраняется: щит — это буфер прощения. Промахи
## стоят внимания, но не прогресса, пока он держится. Здоровье трогается
## только когда буфер выбит полностью — иначе игра станет злой к детям.

var _failed := 0
var _passed := 0


func _ready() -> void:
	# Не трогаем реальный сейв игрока: тесты гоняют настоящие подсистемы
	SaveManager.enter_test_mode()
	_test_shield_absorbs_before_health()
	_test_shield_note_restores_shield()
	_test_missed_shield_hurts_more()
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
		health := 100, depth := 0) -> BattleState:
	var s := BattleState.new()
	s.setup(Registry.monster(monster_id), Registry.monster(guardian_id), health, depth)
	return s


## Щит — это прощение: промахи стоят внимания, но не прогресса,
## пока буфер держится. Здоровье трогается только когда щит выбит.
func _test_shield_absorbs_before_health() -> void:
	print("Урон идёт сначала в щит, потом в здоровье")
	var s := _make()
	var health_before := s.health
	check_eq(s.shield, s.max_shield, "щит полон на входе в бой")

	s.register_hit(Judge.Grade.MISS)
	check(s.shield < s.max_shield, "промах съел щит")
	check_eq(s.health, health_before, "здоровье не тронуто, пока держится щит")
	check_eq(s.combo, 0, "комбо сбито")

	# Пока щита хватает на весь удар, здоровье не должно шелохнуться.
	# Излишек последнего удара честно перетекает в здоровье — это верно,
	# и тест обязан это допускать, а не считать поломкой
	var guard := 0
	while s.shield >= BattleState.MISS_DAMAGE and guard < 100:
		guard += 1
		s.register_hit(Judge.Grade.MISS)
		check_eq(s.health, health_before,
			"здоровье цело, пока щит покрывает удар (осталось щита %d)" % s.shield)

	# Добиваем остаток щита
	while s.shield > 0 and guard < 200:
		guard += 1
		s.register_hit(Judge.Grade.MISS)
	check_eq(s.shield, 0, "щит выбит")

	var health_at_zero_shield := s.health
	s.register_hit(Judge.Grade.MISS)
	check(s.health < health_at_zero_shield, "без щита промахи бьют прямо по здоровью")
	check_eq(health_at_zero_shield - s.health, BattleState.MISS_DAMAGE,
		"без щита промах стоит ровно свою цену")


func _test_shield_note_restores_shield() -> void:
	print("Попадание по ноте-щиту чинит щит")
	var s := _make()
	for i in 3:
		s.register_hit(Judge.Grade.MISS)
	var damaged := s.shield
	check(damaged < s.max_shield, "щит повреждён")

	s.block_strike()
	check(s.shield > damaged, "принятый щит восстановил буфер")
	check(s.combo > 0, "и нарастил комбо")

	# Восстановление не переливается через край
	for i in 20:
		s.block_strike()
	check_eq(s.shield, s.max_shield, "щит не превышает максимум")


func _test_missed_shield_hurts_more() -> void:
	print("Пропущенный щит бьёт сильнее обычного промаха")
	var a := _make()
	a.register_hit(Judge.Grade.MISS)
	var miss_damage := a.max_shield - a.shield

	var b := _make()
	b.take_strike()
	var strike_damage := b.max_shield - b.shield

	check(strike_damage > miss_damage,
		"атака монстра дороже обычного промаха (%d против %d)"
			% [strike_damage, miss_damage])


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
	lost.shield = 0  # щит уже выбит: урон пойдёт прямо в здоровье
	var defeats := [0]
	lost.defeat.connect(func(): defeats[0] += 1)
	lost.take_strike()
	check(lost.is_over and not lost.did_win, "здоровье кончилось — поражение")
	check_eq(defeats[0], 1, "сигнал поражения ровно один")
	check_eq(lost.health, 0, "здоровье обнулено, не ушло в минус")


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
	print("Перекус восстанавливает здоровье")
	var s := _make("synth_slime", "disco_sprout", 50)
	s.restore_health(15)
	check_eq(s.health, 65, "Здоровье восстановлено")

	s.restore_health(9999)
	check_eq(s.health, s.max_health, "Здоровье не превышает максимум")
