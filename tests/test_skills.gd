extends TestHarness

## Спецдвижения гуардиана (GDD §4.2.4).
##
## Скилл — единственная механика, где стихия влияет не на множитель урона,
## а на само действие. Эффекты маленькие и мгновенные намеренно: скилл
## приправа к бою, а не вторая боевая система.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	_test_miss_costs_more_than_beat()
	_test_stone_boosts_next_attack()
	_test_sun_repairs_shield()
	_test_leaf_restores_health()
	_test_spark_raises_combo()
	_test_wind_widens_windows()
	_test_without_guardian_skill_is_plain_beat()


## Бой, где гуардиан заданной стихии.
func _battle_with(genre: int) -> BattleState:
	GameState.reset()
	var species := _species_of(genre)
	var guardian := GameState.tame(species, COMMON)
	var state := BattleState.new()
	state.setup(MonsterInstance.create("beat_serpent", COMMON), guardian, 100)
	return state


## Кто из монстров какой стихии. Берём из реестра, а не хардкодим: список
## монстров растёт, и тест не должен разъезжаться с данными.
func _species_of(genre: int) -> String:
	for monster in Registry.all_monsters():
		if monster.genre == genre:
			return monster.id
	return "disco_sprout"


## Промах по особой ноте дороже промаха по обычной — иначе левая кнопка
## ничем не отличалась бы от правой.
func _test_miss_costs_more_than_beat() -> void:
	print("Промах по скиллу бьёт больнее обычного")
	var plain := _battle_with(MonsterData.Genre.ROCK)
	plain.register_hit(Judge.Grade.MISS)
	var plain_damage := plain.max_shield - plain.shield

	var skill := _battle_with(MonsterData.Genre.ROCK)
	skill.use_skill(Judge.Grade.MISS)
	var skill_damage := skill.max_shield - skill.shield

	check(skill_damage > plain_damage,
		"промах по скиллу дороже (%d против %d)" % [skill_damage, plain_damage])
	check_eq(skill.combo, 0, "и сбивает комбо")
	check(not skill.series_clean, "и пачкает серию")


func _test_stone_boosts_next_attack() -> void:
	print("Камень: топот усиливает следующий удар")
	var plain := _battle_with(MonsterData.Genre.ROCK)
	var plain_damage := _clean_attack(plain)

	var boosted := _battle_with(MonsterData.Genre.ROCK)
	boosted.use_skill(Judge.Grade.PERFECT)
	var boosted_damage := _clean_attack(boosted)

	check(boosted_damage > plain_damage,
		"удар после топота сильнее (%d против %d)" % [boosted_damage, plain_damage])

	# Бонус тратится на ОДНОМ ударе: иначе скилл в начале боя тихо усиливал бы
	# весь бой целиком
	var second := _clean_attack(boosted)
	check(second < boosted_damage, "второй удар уже обычный (%d)" % second)


func _test_sun_repairs_shield() -> void:
	print("Солнце: вспышка чинит щит")
	var state := _battle_with(MonsterData.Genre.DISCO)
	for i in 4:
		state.register_hit(Judge.Grade.MISS)
	var damaged := state.shield

	state.use_skill(Judge.Grade.PERFECT)
	check(state.shield > damaged, "щит подрос (%d → %d)" % [damaged, state.shield])

	# Не переливается через край
	for i in 10:
		state.use_skill(Judge.Grade.PERFECT)
	check_eq(state.shield, state.max_shield, "щит не превышает максимум")


func _test_leaf_restores_health() -> void:
	print("Листва: дыхание леса возвращает силы")
	var state := _battle_with(MonsterData.Genre.FOLK)
	state.health = state.max_health - 20
	var before := state.health

	state.use_skill(Judge.Grade.PERFECT)
	check(state.health > before, "здоровье выросло (%d → %d)" % [before, state.health])
	check(state.health <= state.max_health, "и не вышло за максимум")


func _test_spark_raises_combo() -> void:
	print("Искра: разряд подбрасывает комбо")
	var state := _battle_with(MonsterData.Genre.ELECTRO)
	for i in 3:
		state.register_hit(Judge.Grade.PERFECT)
	var before := state.combo

	state.use_skill(Judge.Grade.PERFECT)
	check(state.combo > before + 1,
		"комбо прыгнуло больше, чем на одно попадание (%d → %d)" % [before, state.combo])


## Ветер расширяет окна на четыре такта и ровно на четыре: эффект обязан
## закончиться сам, иначе он превращается в постоянное свойство.
func _test_wind_widens_windows() -> void:
	print("Ветер: порыв расширяет окна на четыре такта")
	var state := _battle_with(MonsterData.Genre.LATIN)
	var normal := state.effective_window_scale(0.0)

	state.use_skill(Judge.Grade.PERFECT, 0.0, 4)
	check(state.effective_window_scale(0.0) > normal, "сразу после скилла окна шире")
	check(state.effective_window_scale(8.0) > normal, "через два такта ещё действует")
	check_eq(state.effective_window_scale(17.0), normal,
		"через четыре такта эффект кончился")


## В интро гуардиана нет (GDD §15.5), и скилл обязан вести себя как обычный
## бит: иначе бой упрётся в отсутствующую стихию.
func _test_without_guardian_skill_is_plain_beat() -> void:
	print("Без гуардиана скилл — обычный бит")
	GameState.reset()
	var state := BattleState.new()
	state.setup(MonsterInstance.create("disco_sprout", COMMON), null, 100)

	var before_health := state.health
	state.use_skill(Judge.Grade.PERFECT)

	check_eq(state.combo, 1, "комбо выросло на единицу, как от обычной ноты")
	check_eq(state.series_length, 1, "серия набирается")
	check_eq(state.health, before_health, "и ничего не вылечило")
	check_eq(state.effective_window_scale(0.0), state.window_scale,
		"окна не расширились")


func _clean_attack(state: BattleState) -> int:
	for i in BattleState.min_series_length():
		state.register_hit(Judge.Grade.PERFECT)
	return state.register_attack(Judge.Grade.PERFECT)
