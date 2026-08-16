extends TestHarness

## Проверки боевой логики.
##
## Главное, что здесь охраняется: щит — это буфер прощения. Промахи
## стоят внимания, но не прогресса, пока он держится. Здоровье трогается
## только когда буфер выбит полностью — иначе игра станет злой к детям.

func run_tests() -> void:
	_test_crit_hits_four_times_harder()
	_test_one_blow_never_ends_the_run()
	_test_miss_reports_damage()
	_test_shield_absorbs_before_health()
	_test_shield_note_restores_shield()
	_test_missed_shield_hurts_more()
	_test_plain_beats_do_not_damage()
	_test_attack_needs_clean_series()
	_test_series_resets_after_attack()
	_test_pause_breaks_series()
	_test_gear_raises_attack_damage()
	_test_fruit_buffs_raise_attack_damage()
	_test_attack_quality_matters()
	_test_genre_advantage()
	_test_depth_scaling()
	_test_victory_and_defeat()
	_test_perfect_run()
	_test_snack()
	_test_rarity_scales_monster()
	_test_experience_raises_damage()


## С полного здоровья ни один удар не заканчивает забег.
##
## Множители перемножаются: ×4 за крит и ×5 за легендарный грейд давали удар
## на 300 при 172 здоровья — полностью прокачанный гуардиан умирал с ПЕРВОГО
## пропуска, не успев понять, что случилось. Проверяется наблюдаемый результат
## (жив и бой не кончен), а не сама доля: порог можно двигать, обещание — нет.
func _test_one_blow_never_ends_the_run() -> void:
	print("Один удар не кончает забег с полного здоровья")
	# Именно С ПОЛНОГО: 9999 обрезается setup'ом до max_health. Со 100 тест
	# мерил бы уже раненого гуардиана — обещание касается не его
	for grade in range(MonsterData.Rarity.size()):
		var s := _make("beat_serpent", "disco_sprout", 9999, 12, grade)
		check_eq(s.health, s.max_health, "%s: старт с полного здоровья"
			% MonsterData.rarity_name(grade))
		s.take_strike(true)
		check(s.health > 0, "%s: после крита с полного здоровья гуардиан жив"
			% MonsterData.rarity_name(grade))
		check(not s.is_over, "%s: бой продолжается" % MonsterData.rarity_name(grade))

	# Но не бессмертие: криты подряд добивают. Иначе порог сделал бы пропуск
	# крита бесплатным, и особая нота перестала бы что-то значить
	var top := _make("beat_serpent", "disco_sprout", 9999, 12,
		MonsterData.Rarity.LEGENDARY)
	for i in 4:
		top.take_strike(true)
	check(top.health <= 0, "криты подряд на легендарном всё же добивают")


## Бой между двумя экземплярами. Грейд противника — параметр: он и есть
## главный множитель сложности встречи (GDD §6.3).
func _make(monster_id := "synth_slime", guardian_id := "disco_sprout",
		health := 100, depth := 0, monster_grade := MonsterData.Rarity.COMMON) -> BattleState:
	var s := BattleState.new()
	s.setup(
		MonsterInstance.create(monster_id, monster_grade),
		GameState.tame(guardian_id, MonsterData.Rarity.COMMON),
		health, depth)
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
	# Урон масштабируется злостью грейда (strike_scale), поэтому сверяем
	# с ценой ПОСЛЕ множителя, а не с голой константой
	var expected := maxi(int(round(BattleState.MISS_DAMAGE * s.strike_scale)), 1)
	check_eq(health_at_zero_shield - s.health, expected,
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


## Обычные биты НЕ бьют монстра. Это ядро новой боевой модели:
## они собирают серию, а урон приходит только с атакой в её конце.
func _test_plain_beats_do_not_damage() -> void:
	print("Обычные биты не сбивают Настрой")
	var s := _make()
	var before := s.vibe

	for i in 20:
		s.register_hit(Judge.Grade.PERFECT)
	check_eq(s.vibe, before, "20 идеальных обычных попаданий не тронули Настрой")
	check_eq(s.series_length, 20, "но серия набрана")
	check(s.series_clean, "серия чиста")


func _test_attack_needs_clean_series() -> void:
	print("Атака срабатывает только после чистой серии")

	# Чистая серия достаточной длины — атака проходит
	var clean := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		clean.register_hit(Judge.Grade.PERFECT)
	var dealt := clean.register_attack(Judge.Grade.PERFECT)
	check(dealt > 0, "после чистой серии атака нанесла урон (%d)" % dealt)
	check(clean.vibe < clean.max_vibe, "Настрой сбит")
	check_eq(clean.attacks_landed, 1, "атака засчитана")

	# Один промах в серии — атака вхолостую
	var dirty := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		dirty.register_hit(Judge.Grade.PERFECT)
	dirty.register_hit(Judge.Grade.MISS)
	for i in BattleState.MIN_SERIES_LENGTH:
		dirty.register_hit(Judge.Grade.PERFECT)
	var wasted := dirty.register_attack(Judge.Grade.PERFECT)
	check_eq(wasted, 0, "промах в серии обнулил атаку")
	check_eq(dirty.vibe, dirty.max_vibe, "Настрой не тронут")
	check_eq(dirty.attacks_wasted, 1, "холостая атака посчитана")

	# Слишком короткая серия — атака тоже вхолостую
	var short := _make()
	short.register_hit(Judge.Grade.PERFECT)
	check_eq(short.register_attack(Judge.Grade.PERFECT), 0,
		"после серии из одной ноты атака не проходит")


func _test_series_resets_after_attack() -> void:
	print("Атака завершает серию")
	var s := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		s.register_hit(Judge.Grade.PERFECT)
	s.register_attack(Judge.Grade.PERFECT)
	check_eq(s.series_length, 0, "серия обнулена")
	check(s.series_clean, "новая серия начинается чистой")

	# Сразу вторая атака без новой серии не проходит
	check_eq(s.register_attack(Judge.Grade.PERFECT), 0,
		"вторая атака подряд не проходит — серии перед ней нет")


func _test_pause_breaks_series() -> void:
	print("Пауза обрывает серию")
	var s := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		s.register_hit(Judge.Grade.PERFECT)
	s.break_series()
	check_eq(s.series_length, 0, "пауза обнулила серию")
	check_eq(s.register_attack(Judge.Grade.PERFECT), 0,
		"атака после паузы не проходит")


func _test_gear_raises_attack_damage() -> void:
	print("Снаряжение усиливает атаку")
	GameState.reset()
	var bare := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		bare.register_hit(Judge.Grade.PERFECT)
	var bare_damage := bare.register_attack(Judge.Grade.PERFECT)

	GameState.add_gear("thunder_pick")
	GameState.equip(GameState.tame("disco_sprout", MonsterData.Rarity.COMMON).key(), "thunder_pick")
	var geared := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		geared.register_hit(Judge.Grade.PERFECT)
	var geared_damage := geared.register_attack(Judge.Grade.PERFECT)

	check(geared_damage > bare_damage,
		"собранные предметы бьют сильнее (%d против %d)" % [geared_damage, bare_damage])
	GameState.reset()


## Съеденный у костра фрукт — вложение: его баф обязан доехать до боя.
## Проверяется НАБЛЮДАЕМЫЙ результат (урон атаки), а не поле run_buffs:
## бафы уже копились и показывались в сумке, но бой их не читал вовсе.
func _test_fruit_buffs_raise_attack_damage() -> void:
	print("Бафы съеденных фруктов действуют в бою")
	GameState.reset()
	RunManager.run_buffs.clear()

	var plain := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		plain.register_hit(Judge.Grade.PERFECT)
	var plain_damage := plain.register_attack(Judge.Grade.PERFECT)

	# Инжир (тир 2): удар +1.2 — ровно то, что обещает сумка
	RunManager.add_buff({"power_bonus": 1.2})
	var fed := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		fed.register_hit(Judge.Grade.PERFECT)
	var fed_damage := fed.register_attack(Judge.Grade.PERFECT)

	check(fed_damage > plain_damage,
		"съеденный фрукт бьёт сильнее (%d против %d)" % [fed_damage, plain_damage])

	# Окно: доля фрукта конвертируется в множитель снаряжения
	RunManager.add_buff({"window_scale": 0.15})
	var widened := _make()
	check_close(widened.effective_window_scale(), 1.15,
		"окно шире на долю из таблицы фруктов")

	RunManager.run_buffs.clear()
	GameState.reset()


func _test_attack_quality_matters() -> void:
	print("Точность атаки влияет на урон")
	var damages := {}
	for grade in [Judge.Grade.PERFECT, Judge.Grade.GOOD, Judge.Grade.EARLY_LATE]:
		var s := _make()
		for i in BattleState.MIN_SERIES_LENGTH:
			s.register_hit(Judge.Grade.PERFECT)
		damages[grade] = s.register_attack(grade)

	check(damages[Judge.Grade.PERFECT] > damages[Judge.Grade.GOOD],
		"идеальная атака сильнее хорошей")
	check(damages[Judge.Grade.GOOD] > damages[Judge.Grade.EARLY_LATE],
		"хорошая сильнее приблизительной")
	check(damages[Judge.Grade.EARLY_LATE] > 0, "даже приблизительная что-то делает")


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

	# Урон приходит только с атакой, поэтому сравниваем её, а не обычный бит
	for i in BattleState.MIN_SERIES_LENGTH:
		strong.register_hit(Judge.Grade.PERFECT)
		weak.register_hit(Judge.Grade.PERFECT)
	check(strong.register_attack(Judge.Grade.PERFECT)
		> weak.register_attack(Judge.Grade.PERFECT),
		"выгодный жанр бьёт сильнее")


func _test_depth_scaling() -> void:
	print("Настрой растёт с глубиной забега")
	var shallow := _make("synth_slime", "disco_sprout", 100, 0)
	var deep := _make("synth_slime", "disco_sprout", 100, 10)
	check(deep.max_vibe > shallow.max_vibe, "на 10-й поляне монстр крепче")

	# Доля за поляну живёт в progression.json → battle.vibe_depth_scale
	var expected := int(round(shallow.max_vibe * (1.0 + Balance.vibe_depth_scale() * 10)))
	check_eq(deep.max_vibe, expected, "масштаб ровно по формуле GDD")


func _test_victory_and_defeat() -> void:
	print("Победа и поражение")
	var won := _make()
	# Счётчик в массиве, а не в переменной: лямбды в GDScript захватывают
	# локальные переменные ПО ЗНАЧЕНИЮ, и обычный счётчик снаружи не менялся бы
	var victories := [0]
	won.victory.connect(func(): victories[0] += 1)
	while not won.is_over:
		for i in BattleState.MIN_SERIES_LENGTH:
			won.register_hit(Judge.Grade.PERFECT)
		won.register_attack(Judge.Grade.PERFECT)
	check(won.did_win, "Настрой сбит — победа")
	check_eq(victories[0], 1, "сигнал победы ровно один")
	check_eq(won.vibe, 0, "Настрой обнулён, не ушёл в минус")

	# После конца боя состояние не меняется
	var vibe_after := won.vibe
	won.register_attack(Judge.Grade.PERFECT)
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


## Грейд монстра меняет и его крепость, и его удар.
func _test_rarity_scales_monster() -> void:
	print("Грейд делает монстра крепче и злее")
	GameState.reset()
	# ОДИН И ТОТ ЖЕ вид в двух грейдах: грейд принадлежит экземпляру,
	# и разница обязана появляться именно от него, а не от выбора вида
	var common := _make("disco_sprout", "disco_sprout", 100, 0, MonsterData.Rarity.COMMON)
	var epic := _make("disco_sprout", "disco_sprout", 100, 0, MonsterData.Rarity.EPIC)

	check(epic.max_vibe > common.max_vibe,
		"монстр выше грейдом крепче (%d против %d)" % [epic.max_vibe, common.max_vibe])
	check(epic.strike_scale > common.strike_scale,
		"и бьёт сильнее (x%.2f против x%.2f)" % [epic.strike_scale, common.strike_scale])

	# Шкала грейдов монотонна: каждый следующий не слабее предыдущего
	var previous := 0.0
	for r in MonsterData.Rarity.values():
		var scale: float = Balance.grade_stat_scale(r)
		check(scale >= previous, "грейд %s не слабее предыдущего" % MonsterData.rarity_name(r))
		previous = scale
	check_eq(MonsterData.RARITY_NAMES.size(), 6, "грейдов шесть")


## Повторные встречи с видом усиливают удар по нему.
func _test_experience_raises_damage() -> void:
	print("Опыт против вида усиливает удар")
	GameState.reset()
	var fresh := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		fresh.register_hit(Judge.Grade.PERFECT)
	var first := fresh.register_attack(Judge.Grade.PERFECT)

	for i in 10:
		GameState.add_battle_experience("synth_slime")
	var learned := _make()
	for i in BattleState.MIN_SERIES_LENGTH:
		learned.register_hit(Judge.Grade.PERFECT)
	var later := learned.register_attack(Judge.Grade.PERFECT)

	check(later > first, "после 10 встреч удар сильнее (%d против %d)" % [later, first])

	# Потолок есть: иначе сотая встреча превратит бой в формальность
	for i in 500:
		GameState.add_battle_experience("synth_slime")
	check(GameState.experience_multiplier("synth_slime")
		<= 1.0 + GameState.xp_damage_cap() + 0.001, "прибавка упирается в потолок")

	# Опыт по одному виду не влияет на другой
	check_eq(GameState.experience_multiplier("bass_bear"), 1.0,
		"опыт не протекает на другие виды")
	GameState.reset()


## Крит монстра бьёт вчетверо больнее обычного удара (GDD §4.2.3).
##
## Раньше на этом месте стояла нота-зелье, и после упразднения зелий она
## осталась нарисованной бутылочкой: игрок ждал лечения и получал по лбу.
func _test_crit_hits_four_times_harder() -> void:
	print("Крит бьёт вчетверо")
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", MonsterData.Rarity.COMMON),
		null, 500, 0)
	state.shield = 0

	var normal := state.take_strike(false)
	var crit := state.take_strike(true)
	# Сравниваем ОТНОШЕНИЕ с допуском: множитель применяется до округления,
	# и 23×4 не обязано в точности совпасть с round(60×1.5)
	var ratio := float(crit) / maxf(normal, 1.0)
	check(absf(ratio - BattleState.CRIT_MULTIPLIER) < 0.15,
		"крит (%d) примерно вчетверо больше обычного (%d), отношение %.2f" % [
			crit, normal, ratio])
	check(crit > 0, "и он вообще что-то снимает")


## Промах по герою обязан ВОЗВРАЩАТЬ урон: по этому числу рисуется цифра
## над героем, и без него удары по себе не видно вовсе.
func _test_miss_reports_damage() -> void:
	print("Промах сообщает, сколько стоил")
	var state := BattleState.new()
	state.setup(MonsterInstance.create("synth_slime", MonsterData.Rarity.COMMON),
		null, 500, 0)
	state.shield = 0

	# Минус означает «получил сам», плюс — «снял с монстра»
	check(state.register_hit(Judge.Grade.MISS) < 0,
		"обычный промах вернул урон по герою")
	check(state.use_skill(Judge.Grade.MISS) < 0,
		"промах по скиллу вернул урон по герою")
	check(state.use_skill(Judge.Grade.PERFECT) == 0,
		"удачный скилл героя не бьёт")
