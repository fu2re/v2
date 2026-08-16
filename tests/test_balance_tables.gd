extends TestHarness

## Проверки балансовых таблиц.
##
## Таблицы в `data/*.json` объявлены источником истины, но до появления
## `Balance` их не читала ни одна строка кода — и числа успели разойтись:
## множитель легендарного был 1.7 в коде против 2.0 в таблице. Эти тесты
## следят за тем, чтобы таблицы действительно ЧИТАЛИСЬ, а не подменялись
## молча запасными значениями.

const GRADES := ["common", "uncommon", "rare", "unique", "epic", "legendary"]


func run_tests() -> void:
	_test_tables_are_actually_read()
	_test_grade_scale_is_monotonic()
	_test_friendship_thresholds_grow()
	_test_level_curve()
	_test_weights_sum_to_hundred()
	_test_rarity_weights_shift_with_depth()
	_test_victory_chest_odds()
	_test_fallbacks_match_tables()


## Главная проверка файла: значения приходят ИЗ JSON.
##
## Сверяется с числом, которого нет среди запасных констант — если файл
## перестанет читаться, подмена сразу видна.
func _test_tables_are_actually_read() -> void:
	Balance.reload()

	var legendary := Balance.grade_stat_scale(MonsterData.Rarity.LEGENDARY)
	check_close(legendary, 2.0, "множитель легендарного берётся из progression.json")

	# То же число обязано доехать до боевой формулы, а не остаться в таблице
	check_close(MonsterData.rarity_vibe_scale(MonsterData.Rarity.LEGENDARY), 2.0,
		"бой считает Настрой по табличному множителю")
	check_close(MonsterData.rarity_power_scale(MonsterData.Rarity.LEGENDARY), 2.0,
		"удар монстра считается по тому же множителю")

	check_eq(Balance.max_level(), 10, "потолок уровня из таблицы")
	check_close(Balance.level_stat_bonus(), 0.08, "прибавка за уровень из таблицы")


func _test_grade_scale_is_monotonic() -> void:
	var previous := 0.0
	for grade in GRADES.size():
		var scale := Balance.grade_stat_scale(grade)
		check(scale > previous, "множитель грейда %s больше предыдущего" % GRADES[grade])
		previous = scale

	# Разрыв между краями — заявленные «примерно вдвое» из GDD §6.3
	var ratio := Balance.grade_stat_scale(MonsterData.Rarity.LEGENDARY) \
		/ Balance.grade_stat_scale(MonsterData.Rarity.COMMON)
	check(ratio >= 1.8 and ratio <= 2.2, "легендарный примерно вдвое крепче обычного")


## Пороги растут с грейдом: у каждого своя независимая шкала (GDD §6.1),
## и чем реже экземпляр, тем дольше к нему идти.
func _test_friendship_thresholds_grow() -> void:
	var previous := 0
	for grade in GRADES.size():
		var threshold := Balance.friendship_threshold(grade)
		check(threshold > previous, "порог дружбы грейда %s выше предыдущего" % GRADES[grade])
		previous = threshold

	check_eq(Balance.friendship_threshold(MonsterData.Rarity.COMMON), 100,
		"порог обычного")
	check_eq(Balance.friendship_threshold(MonsterData.Rarity.LEGENDARY), 400,
		"порог легендарного")


func _test_level_curve() -> void:
	check_eq(Balance.xp_for_level(1), 0, "первый уровень не требует опыта")

	var previous := -1
	for level in range(1, Balance.max_level() + 1):
		var needed := Balance.xp_for_level(level)
		check(needed > previous, "опыт до уровня %d больше, чем до предыдущего" % level)
		previous = needed

	# Опыт за победу растёт с грейдом противника и за чистый бой
	var over_common := Balance.xp_for_victory(MonsterData.Rarity.COMMON, false)
	var over_legendary := Balance.xp_for_victory(MonsterData.Rarity.LEGENDARY, false)
	check(over_legendary > over_common, "за легендарного дают больше опыта")
	check(Balance.xp_for_victory(MonsterData.Rarity.COMMON, true) > over_common,
		"S-ранг добавляет опыт")


## Публикуемые доли обязаны складываться в сто процентов: таблица, которая
## не сходится, лжёт и дизайнеру, и игроку.
func _test_weights_sum_to_hundred() -> void:
	for table_name in ["поляны", "встречи", "куст с лутом", "подарки бабки"]:
		var weights: Dictionary = _weights_for(table_name)
		if weights.is_empty():
			check(false, "таблица «%s» не прочиталась" % table_name)
			continue
		var total := 0.0
		for value: float in weights.values():
			total += value
		check(absf(total - 100.0) < 0.01, "доли «%s» дают 100%% (сейчас %.1f)"
			% [table_name, total])


func _weights_for(table_name: String) -> Dictionary:
	match table_name:
		"поляны":
			return Balance.glade_weights()
		"встречи":
			return Balance.encounter_weights()
		"куст с лутом":
			return Balance.loot_bush_weights()
		_:
			return Balance.granny_gift_weights()


## С глубиной редкие вытесняют обычных, но обычные не исчезают никогда:
## приручение обычного обязано оставаться доступным на любой глубине.
func _test_rarity_weights_shift_with_depth() -> void:
	var shallow := Balance.rarity_weights(0)
	var deep := Balance.rarity_weights(40)

	check_eq(shallow.size(), GRADES.size(), "весов столько же, сколько грейдов")
	check(deep[MonsterData.Rarity.LEGENDARY] > shallow[MonsterData.Rarity.LEGENDARY],
		"легендарные чаще на глубине")
	check(deep[MonsterData.Rarity.COMMON] < shallow[MonsterData.Rarity.COMMON],
		"обычные реже на глубине")
	check(deep[MonsterData.Rarity.COMMON] > 0.0, "обычные не исчезают совсем")

	# Сдвиг ограничен: иначе на сороковой поляне встречались бы одни легендарные
	var deepest := Balance.rarity_weights(400)
	check_close(deepest[MonsterData.Rarity.LEGENDARY], deep[MonsterData.Rarity.LEGENDARY],
		"сдвиг упирается в потолок", 0.01)


func _test_victory_chest_odds() -> void:
	for grade in GRADES.size():
		var odds := Balance.victory_chest_odds(grade)
		check_eq(odds.size(), 3, "у грейда %s три тира сундука" % GRADES[grade])
		var total := 0.0
		for w: float in odds:
			total += w
		check(absf(total - 100.0) < 0.01, "шансы сундука грейда %s дают 100%%" % GRADES[grade])

	# Чем опаснее монстр, тем ценнее награда — иначе за редкими незачем идти
	var common := Balance.victory_chest_odds(MonsterData.Rarity.COMMON)
	var legendary := Balance.victory_chest_odds(MonsterData.Rarity.LEGENDARY)
	check(legendary[2] > common[2], "за легендарного чаще выпадает дорогая вещь")


## Запасные константы обязаны совпадать с таблицами. Они включаются молча —
## только при битом JSON — и разъехавшийся fallback подменяет баланс так,
## что этого не видит никто. Ровно так жил FALLBACK_STRIKE_SCALE:
## 1.0/1.4/2.0… в коде против 1.5/1.9/2.4… в таблице.
func _test_fallbacks_match_tables() -> void:
	var progression := _load_json("res://data/progression.json")
	var multipliers: Dictionary = progression.get("grade_multipliers", {})
	var stat: Dictionary = multipliers.get("stat_scale", {})
	var strike: Dictionary = multipliers.get("strike_scale", {})
	var friendship: Dictionary = progression.get("friendship", {})
	var thresholds: Dictionary = friendship.get("thresholds", {})

	for i in GRADES.size():
		var key: String = GRADES[i]
		check_close(float(stat.get(key, -1.0)), Balance.FALLBACK_STAT_SCALE[i],
			"fallback крепости совпадает с таблицей (%s)" % key)
		check_close(float(strike.get(key, -1.0)), Balance.FALLBACK_STRIKE_SCALE[i],
			"fallback удара совпадает с таблицей (%s)" % key)
		check_eq(int(thresholds.get(key, -1)), int(Balance.FALLBACK_THRESHOLDS[i]),
			"fallback порога дружбы совпадает с таблицей (%s)" % key)

	var levels: Dictionary = progression.get("instance_levels", {})
	var curve: Array = levels.get("xp_to_next_level", [])
	check_eq(curve.size(), Balance.FALLBACK_XP_CURVE.size(),
		"длина запасной кривой опыта совпадает с таблицей")
	for i in mini(curve.size(), Balance.FALLBACK_XP_CURVE.size()):
		check_eq(int(curve[i]), int(Balance.FALLBACK_XP_CURVE[i]),
			"fallback кривой опыта: ступень %d" % (i + 1))

	var drops := _load_json("res://data/drop_tables.json")
	var glades: Dictionary = drops.get("glade_types", {})
	var glade_weights: Dictionary = glades.get("weights_percent", {})
	for key: String in Balance.FALLBACK_GLADE_WEIGHTS:
		check_close(float(glade_weights.get(key, -1.0)),
			float(Balance.FALLBACK_GLADE_WEIGHTS[key]),
			"fallback весов полян совпадает с таблицей (%s)" % key)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		check(false, "таблица не прочиталась: %s" % path)
		return {}
	return parsed
