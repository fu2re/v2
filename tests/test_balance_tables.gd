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
	_test_element_matchups_valid()
	_test_weights_sum_to_hundred()
	_test_rarity_weights_shift_with_depth()
	_test_victory_chest_odds()
	_test_tables_complete()
	_test_entity_tables_match_registry()


## Главная проверка файла: значения приходят ИЗ JSON.
##
## Геттеры сверяются с СЫРЫМ разбором файла, а не с литералами: перестанет
## читаться файл — геттер отдаст заглушку и разойдётся с сырым значением,
## а правка баланса дизайнером тест не краснит.
func _test_tables_are_actually_read() -> void:
	Balance.reload()

	var progression := _load_json("res://data/progression.json")
	var multipliers: Dictionary = progression.get("grade_multipliers", {})
	var stat_scale: Dictionary = multipliers.get("stat_scale", {})
	var levels: Dictionary = progression.get("instance_levels", {})

	var legendary := Balance.grade_stat_scale(MonsterData.Rarity.LEGENDARY)
	check_close(legendary, float(stat_scale.get("legendary", -1.0)),
		"множитель легендарного берётся из progression.json")

	# То же число обязано доехать до боевой формулы, а не остаться в таблице.
	# Проверяется НАБЛЮДАЕМЫЙ стат экземпляра, а не обёртка-делегат: обёртка
	# может совпадать с таблицей и при этом не использоваться боем вовсе
	var common_vibe := MonsterInstance.create("disco_sprout",
		MonsterData.Rarity.COMMON).vibe()
	var legendary_vibe := MonsterInstance.create("disco_sprout",
		MonsterData.Rarity.LEGENDARY).vibe()
	check_close(float(legendary_vibe) / float(common_vibe), legendary,
		"Настрой экземпляра растёт по табличному множителю", 0.05)
	check_close(MonsterInstance.create("disco_sprout",
		MonsterData.Rarity.LEGENDARY).strike_scale(),
		Balance.grade_strike_scale(MonsterData.Rarity.LEGENDARY),
		"удар экземпляра считается по табличной шкале удара")

	check_eq(Balance.max_level(), int(levels.get("max_level", -1)),
		"потолок уровня из таблицы")
	check_close(Balance.level_stat_bonus(),
		float(levels.get("stat_bonus_per_level", -1.0)),
		"прибавка за уровень из таблицы")

	# Числа боя тоже обязаны доезжать из таблицы до наблюдаемого результата
	var battle := _load_json("res://data/battle.json")
	var strikes: Dictionary = battle.get("strikes", {})
	var state := BattleState.new()
	state.setup(MonsterInstance.create("disco_sprout", MonsterData.Rarity.COMMON),
		null, 100)
	var dealt := state.take_strike(false)
	var expected := maxi(int(round(float(strikes.get("strike_damage", -1))
		* state.strike_scale)), 1)
	check_eq(dealt, expected,
		"пропущенный щит стоит столько, сколько написано в battle.json")


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

	# Потолок — долгосрочная цель, а не побочный эффект пары забегов:
	# фарм обычных до максимума обязан стоить хотя бы сотню побед. Иначе
	# уровень обгоняет и грейды, и снаряжение, и вся лестница прогрессии
	# схлопывается в «просто подерись ещё вечер» (GDD §6.5)
	check(Balance.xp_for_level(Balance.max_level()) >= 100 * over_common,
		"потолок уровня не берётся быстрее ~ста побед над обычными")


## Таблица матчапов обязана ссылаться только на существующие стихии
## и не противоречить сама себе: «уязвим к X и сопротивляюсь X» — это два
## множителя на одну пару, и бой молча выбрал бы один из них.
func _test_element_matchups_valid() -> void:
	var matchups := Balance.element_matchups()
	check(not matchups.is_empty(), "матчапы стихий прочитались")
	for key: String in matchups:
		check(MonsterData.GENRE_KEYS.has(key), "стихия %s существует" % key)
		var row: Dictionary = matchups[key]
		var vulnerable: Array = row.get("vulnerable_to", [])
		var resists: Array = row.get("resists", [])
		for other: String in vulnerable + resists:
			check(MonsterData.GENRE_KEYS.has(other),
				"%s ссылается на существующую стихию %s" % [key, other])
			check(other != key, "%s не в отношениях сама с собой" % key)
		for other: String in vulnerable:
			check(not resists.has(other),
				"%s не может одновременно быть уязвимой к %s и сопротивляться" % [key, other])

	# Множители читаются и осмысленны: уязвимость усиливает, сопротивление режет
	check(Balance.element_vulnerability_outgoing() > 1.0, "исходящая уязвимость — бонус")
	check(Balance.element_vulnerability_incoming() > 1.0, "входящая уязвимость — штраф")
	check(Balance.element_resistance() < 1.0 and Balance.element_resistance() > 0.0,
		"сопротивление режет, но не обнуляет")


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

	# За последней строкой таблица не меняется: сколько ни иди глубже,
	# действует её последняя ступень
	var drops := _load_json("res://data/drop_tables.json")
	var rarity: Dictionary = drops.get("monster_rarity_by_depth", {})
	var rows: Array = rarity.get("by_depth", [])
	if rows.is_empty():
		check(false, "таблица by_depth пуста")
	else:
		var last: Dictionary = rows[rows.size() - 1]
		var last_depth := int(last.get("from_depth", 0))
		check_eq(Balance.rarity_weights(last_depth + 1000),
			Balance.rarity_weights(last_depth),
			"за последней строкой ничего не меняется")
		# И каждая строка обязана давать 100: публикуемая таблица не лжёт
		for entry: Variant in rows:
			var table_row: Dictionary = entry
			var total := 0.0
			for key: String in GRADES:
				total += float(table_row.get(key, 0.0))
			check(absf(total - 100.0) < 0.01,
				"строка from_depth=%d даёт 100%% (сейчас %.1f)"
					% [int(table_row.get("from_depth", -1)), total])


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


## Полнота таблиц: каждый ключ, который читает код, обязан существовать
## в JSON. Заглушки в геттерах включаются молча, и дырка в таблице иначе
## подменила бы баланс так, что этого не видит никто. Раньше эту роль играл
## тест паритета fallback-констант, но копии таблиц в коде краснели бы
## от каждой легитимной правки баланса в редакторе.
##
## Список инвариантов продублирован в валидаторе админки
## (tools/balance_admin) — правь ОБА места.
func _test_tables_complete() -> void:
	var required := _required_paths()
	for file: String in required:
		var parsed := _load_json(file)
		if parsed.is_empty():
			check(false, "таблица пуста или не прочиталась: %s" % file)
			continue
		for path: String in required[file]:
			check(_has_path(parsed, path), "%s: есть %s" % [file.get_file(), path])


func _required_paths() -> Dictionary:
	var paths := {
		"res://data/progression.json": [
			"instance_levels.max_level",
			"instance_levels.stat_bonus_per_level",
			"instance_levels.xp_to_next_level",
			"xp_sources.battle_victory_base",
			"xp_sources.battle_victory_per_enemy_grade",
			"xp_sources.battle_victory_s_rank_bonus",
			"xp_sources.battle_defeat_share",
			"xp_sources.feeding_by_fruit_tier",
			"xp_sources.feeding_favorite_multiplier",
			"battle.vibe_depth_scale",
			"species_experience.damage_step_per_encounter",
			"species_experience.damage_cap",
			"friendship.gains.victory",
			"friendship.gains.victory_s_rank",
			"friendship.gains.favorite_fruit",
			"friendship.gains.other_fruit",
		],
		"res://data/drop_tables.json": [
			"run_rewards.base_silver_per_glade",
			"run_rewards.depth_scale",
			"run_rewards.loot_bush_silver_base",
			"run_rewards.granny_fallback_silver",
			"glade_types.weights_percent.battle",
			"glade_types.weights_percent.wild_bush",
			"glade_types.weights_percent.campfire",
			"glade_types.weights_percent.encounter",
			"encounter_types.weights_percent.merchant",
			"loot_bush.weights_percent.silver_handful",
			"granny.ask_min_fraction",
			"granny.ask_max_fraction",
			"granny.gift_weights_percent.seed_tier_up",
			"monster_rarity_by_depth.by_depth",
			"wild_bush.yield.seed_of_same_fruit",
			"wild_bush.yield.fruit_chance_percent",
			"wild_bush.yield.fruits_when_lucky",
			"soft_death.lost_percent.run_fruits",
			"soft_death.lost_percent.run_silver",
			"cosmetic_crate.price_gold",
			"cosmetic_crate.pity.guaranteed_after_opens",
			"cosmetic_crate.pity.min_rarity",
		],
		"res://data/merchant.json": [
			"forest_merchant.stock_size",
			"farm_merchant.rotation_minutes",
			"farm_merchant.rotating_gear_slots",
			"farm_merchant.base_seed_ids",
			"prices_silver.seeds_by_tier.0",
			"prices_silver.seeds_by_tier.1",
			"prices_silver.seeds_by_tier.2",
			"prices_silver.seeds_by_tier.3",
		],
		"res://data/fruits.json": [
			"buffs.max_total",
		],
		"res://data/battle.json": [
			"strikes.strike_damage",
			"strikes.crit_multiplier",
			"strikes.miss_damage",
			"strikes.skill_miss_damage",
			"strikes.stray_free_taps",
			"strikes.stray_tap_damage",
			"strikes.max_blow_share",
			"attack.attack_multiplier",
			"attack.min_series_length",
			"shield.base_shield",
			"shield.shield_restore",
			"skills.attack_bonus",
			"skills.shield_gain",
			"skills.health_gain",
			"skills.combo_gain",
			"skills.window_boost",
			"skills.window_bars",
			"judge.perfect_window",
			"judge.good_window",
			"judge.late_window",
			"judge.effects.perfect",
			"judge.effects.good",
			"judge.effects.early_late",
			"judge.effects.miss",
			"judge.combo_steps",
			"elements.vulnerability_outgoing",
			"elements.vulnerability_incoming",
			"elements.resistance",
			"elements.matchups.rock",
			"elements.matchups.disco",
			"elements.matchups.folk",
			"elements.matchups.electro",
			"elements.matchups.latin",
			"grade_gap.outgoing_by_gap",
		],
	}
	for grade: String in GRADES:
		paths["res://data/progression.json"].append("grade_multipliers.stat_scale.%s" % grade)
		paths["res://data/progression.json"].append("grade_multipliers.strike_scale.%s" % grade)
		paths["res://data/progression.json"].append("friendship.thresholds.%s" % grade)
		paths["res://data/drop_tables.json"].append("victory_chest.drop_chance_percent_by_monster_rarity.%s" % grade)
		paths["res://data/drop_tables.json"].append("victory_chest.odds_percent_by_monster_rarity.%s" % grade)
	for tier in 4:
		paths["res://data/fruits.json"].append("tiers.%d.grow_seconds" % tier)
		paths["res://data/fruits.json"].append("tiers.%d.friendship_scale" % tier)
		paths["res://data/fruits.json"].append("tiers.%d.heal" % tier)
	return paths


func _has_path(root: Dictionary, path: String) -> bool:
	var node: Variant = root
	for part in path.split("."):
		if typeof(node) != TYPE_DICTIONARY or not node.has(part):
			return false
		node = node[part]
	return true


## Таблицы сущностей и .tres обязаны описывать один и тот же набор:
## строка без ресурса — мусор, ресурс без строки — статы-невидимки
## из дефолтов класса. Оба случая — ошибка данных, а не «ну подставится».
func _test_entity_tables_match_registry() -> void:
	Registry.reload()

	var monsters := _load_json("res://data/monsters.json")
	var species: Dictionary = monsters.get("species", {})
	var monster_list := Registry.all_monsters()
	check(not monster_list.is_empty(), "в реестре есть монстры")
	for m in monster_list:
		check(species.has(m.id), "монстр %s описан в monsters.json" % m.id)
	for id: String in species:
		check(Registry.monster(id) != null, "строка %s в monsters.json имеет .tres" % id)

	var gear_table := _load_json("res://data/gear.json")
	var gear_items: Dictionary = gear_table.get("items", {})
	var gear_list := Registry.all_gear()
	check(not gear_list.is_empty(), "в реестре есть снаряжение")
	for g in gear_list:
		check(gear_items.has(g.id), "снаряжение %s описано в gear.json" % g.id)
		# Цена — единственное, по чему сортируются трети сундука: нулевая
		# означает, что строка не доехала до ресурса
		check(g.price > 0, "у %s цена из таблицы больше нуля" % g.id)
	for id: String in gear_items:
		check(Registry.gear(id) != null, "строка %s в gear.json имеет .tres" % id)

	var cosmetics := _load_json("res://data/cosmetics.json")
	var cosmetic_items: Dictionary = cosmetics.get("items", {})
	var cosmetic_list := Registry.all_cosmetics()
	check(not cosmetic_list.is_empty(), "в реестре есть косметика")
	for c in cosmetic_list:
		check(cosmetic_items.has(c.id), "косметика %s описана в cosmetics.json" % c.id)
	for id: String in cosmetic_items:
		check(Registry.cosmetic(id) != null, "строка %s в cosmetics.json имеет .tres" % id)


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		check(false, "таблица не прочиталась: %s" % path)
		return {}
	return parsed
