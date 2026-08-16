extends TestHarness

## Темп игры глазами семилетнего.
##
## Баланс обычно проверяют вопросом «проходимо ли?». Для игры 7+ этого мало:
## проходимое, но нудное ребёнок бросает так же быстро, как непроходимое,
## и по той же причине — ничего не происходит. Поэтому здесь меряется
## не сложность, а ТЕМП: сколько встреч до следующего события, сколько
## ждать урожая, можно ли застрять, не имея ничего.
##
## Числа-пороги ниже — не выведены из теории, а взяты как рубеж терпения
## и записаны явно, чтобы спорить можно было с ними, а не с ощущениями.

const COMMON := MonsterData.Rarity.COMMON

## Сколько встреч ребёнок готов пройти ради следующего друга. Забег —
## это примерно 20–30 полян, и второй друг обязан появиться в ПЕРВОМ забеге,
## иначе первая сессия кончается ничем.
const GLADES_TO_SECOND_FRIEND := 30

## Точность, с которой играет ребёнок, впервые взявший телефон.
## Не 100% и не 50%: попадает в такт чаще, чем мимо, но далеко не всегда.
const CHILD_ACCURACY := 0.75

## Сколько ждать первого урожая. Пятнадцать минут — это «после ужина
## вернусь и соберу», а не «завтра».
const FIRST_HARVEST_MINUTES := 15

## Доля обычных монстров на первых полянах. Ребёнок должен встретить
## посильного противника, а не легендарного на второй минуте.
const COMMON_SHARE_AT_START := 0.85


func run_tests() -> void:
	_test_first_friend_costs_no_grind()
	_test_something_grows_within_one_sitting()
	_test_no_dead_end_with_empty_pockets()
	_test_first_glades_are_gentle()
	_test_defeat_never_takes_away()
	_test_wait_times_do_not_gate_the_loop()


func _fresh() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	OnboardingState.reset()


## Сколько побед нужно, чтобы приручить обычного монстра голыми руками —
## без единого фрукта. Это худший случай: у новичка фермы ещё нет.
func _victories_to_tame_common() -> int:
	var threshold := GameState.friendship_threshold(COMMON)
	var per_win := GameState.friendship_win()
	return int(ceil(float(threshold) / maxf(per_win, 1)))


## Второй друг обязан достаться за один забег, а не за десять.
##
## Считаем честно: победа даёт свою прибавку, любимый фрукт — свою, но фруктов
## у новичка нет, и путь «просто дерись» должен всё равно приводить к цели
## за разумное число встреч.
func _test_first_friend_costs_no_grind() -> void:
	print("Второй друг достаётся за один забег")
	_fresh()

	var wins := _victories_to_tame_common()
	# Не каждая поляна — бой: там ещё кусты, костры и встречи
	var battle_share: float = Balance.glade_weights().get("battle", 50.0) / 100.0
	check(battle_share > 0.0, "бои на полянах вообще встречаются")

	# И не каждый бой — С ТЕМ ЖЕ монстром. Дружба копится НА ВИД (§6.1),
	# а виды в ленте равновероятны, поэтому нужные победы разбавлены
	# всеми остальными видами. Без этого множителя расчёт врёт в разы —
	# и первая версия этой проверки именно так и врала
	var species := maxi(Registry.all_monsters().size(), 1)
	var grind := int(ceil(wins * species / maxf(battle_share, 0.01)))
	print("    голым кулаком: %d полян (%d побед по одному виду из %d)" % [
		grind, wins, species])

	# ЗАМЫСЛЕННЫЙ путь — через ферму (§6.1): одна победа плюс любимые фрукты.
	# Он и обязан укладываться в рубеж; гринд остаётся длинным намеренно,
	# иначе ферма никому не нужна
	var need := GameState.friendship_threshold(COMMON) - GameState.friendship_win()
	var per_fruit := int(round(GameState.friendship_favorite_fruit()
		* FruitData.tier_friendship_scale(3)))
	var fruits := int(ceil(float(need) / maxf(per_fruit, 1)))
	# Один бой ради встречи плюс поход за урожаем между ними
	var glades := int(ceil(1.0 * species / maxf(battle_share, 0.01)))
	print("    через ферму: %d полян и %d любимых фруктов" % [glades, fruits])

	check(glades <= GLADES_TO_SECOND_FRIEND,
		"даже с фермой на второго друга уходит %d полян — больше рубежа %d" % [
			glades, GLADES_TO_SECOND_FRIEND])
	check(fruits <= 4,
		"на второго друга нужно %d любимых фруктов — это %d циклов грядки" % [
			fruits, fruits])

	# И гринд не должен быть НАСТОЛЬКО длинным, чтобы стать единственной
	# правдой для ребёнка, который не разобрался с фермой
	check(grind <= GLADES_TO_SECOND_FRIEND * 4,
		"без фермы второй друг стоит %d полян — ребёнок бросит раньше" % grind)

	# С фермой должно становиться ЗАМЕТНО быстрее, иначе ферма — украшение,
	# а не половина игры
	var favorite := GameState.friendship_favorite_fruit()
	check(favorite >= GameState.friendship_win() * 2,
		"любимый фрукт (+%d) должен стоить хотя бы двух побед (+%d)" % [
			favorite, GameState.friendship_win()])


## В каждый заход должно быть что собрать. Если всё зреет часами, ребёнок
## возвращается в пустой огород и перестаёт возвращаться вовсе.
func _test_something_grows_within_one_sitting() -> void:
	print("Что-то поспевает за один заход")
	var quickest := 1 << 30
	for fruit in Registry.all_fruits():
		quickest = mini(quickest, fruit.grow_seconds())

	check(quickest <= FIRST_HARVEST_MINUTES * 60,
		"самый быстрый фрукт зреет %d мин — дольше рубежа %d" % [
			quickest / 60, FIRST_HARVEST_MINUTES])

	# И этот быстрый фрукт обязан быть по карману сразу: семя, на которое
	# надо копить, не спасает первую сессию
	var cheapest := 1 << 30
	for fruit in Registry.all_fruits():
		if fruit.grow_seconds() <= FIRST_HARVEST_MINUTES * 60:
			cheapest = mini(cheapest, Balance.seed_price(fruit.tier))
	check(cheapest <= 20,
		"самое дешёвое быстрое семя стоит %d серебра — дороговато для старта" % cheapest)


## Игрок без семян, без серебра и без фруктов обязан иметь путь вперёд.
## Это главный страх детской игры: застрял и не понял почему.
func _test_no_dead_end_with_empty_pockets() -> void:
	print("С пустыми карманами игра не кончается")
	_fresh()
	GameState.tame("disco_sprout", COMMON)
	GameState.set_guardian("disco_sprout:0")

	check_eq(GameState.silver, 0, "серебра нет")
	check(FarmState.available_seeds().is_empty(), "семян нет")

	# Источник семян, не требующий ничего, — дикий куст в лесу
	var weights := Balance.glade_weights()
	var bush: float = weights.get("wild_bush", 0.0)
	check(bush > 0.0, "дикие кусты на первой поляне не выпадают — семян взять негде")

	# И вход в лес не заперт: защитник есть, здоровье полное
	check(GameState.guardian() != null, "защитник на месте")
	check(RunManager.start_run(GameState.guardian_key()), "забег начинается")


## Первые поляны — почти всегда обычные монстры. Легендарный на второй минуте
## это не «интересный вызов», а стена, за которой ребёнок бросает игру.
func _test_first_glades_are_gentle() -> void:
	print("Первые поляны щадящие")
	var weights := Balance.rarity_weights(1)
	var total := 0.0
	for w in weights:
		total += w
	check(total > 0.0, "веса грейдов заданы")

	var common_share := weights[COMMON] / maxf(total, 0.001)
	check(common_share >= COMMON_SHARE_AT_START,
		"на первой поляне обычных всего %.0f%% — меньше рубежа %.0f%%" % [
			common_share * 100.0, COMMON_SHARE_AT_START * 100.0])

	# И ничего страшнее редкого в самом начале не появляется вовсе
	for grade in range(MonsterData.Rarity.UNIQUE, MonsterData.Rarity.size()):
		check(weights[grade] <= 0.0,
			"на первой поляне встречается %s — рано" % MonsterData.rarity_name(grade))


## Проигрыш ничего не отнимает. Это прямое требование §2.1: наказание
## за неудачу для семилетнего означает, что играть страшно.
func _test_defeat_never_takes_away() -> void:
	print("Поражение ничего не отнимает")
	_fresh()
	GameState.tame("disco_sprout", COMMON)
	GameState.set_guardian("disco_sprout:0")
	GameState.add_silver(50)
	GameState.add_friendship("beat_serpent", COMMON, 40)

	var silver_before := GameState.silver
	var friendship_before := GameState.get_friendship("beat_serpent", COMMON)
	var tamed_before := GameState.instances.size()

	# Забег окончен поражением
	RunManager.start_run(GameState.guardian_key())
	RunManager.set_health(0)
	RunManager.die()

	check_eq(GameState.silver, silver_before, "серебро после поражения")
	check_eq(GameState.get_friendship("beat_serpent", COMMON), friendship_before,
		"дружба после поражения")
	check_eq(GameState.instances.size(), tamed_before, "друзья после поражения")

	# И опыт за проигранный бой всё-таки капает — иначе новичок,
	# которому нечем добить, не растёт вовсе
	check(Balance.xp_for_defeat(COMMON) > 0,
		"за проигранный бой не дают опыта — новичку нечем расти")


## Ожидание не должно перекрывать петлю: пока зреет долгий фрукт, играть
## по-прежнему есть чем.
func _test_wait_times_do_not_gate_the_loop() -> void:
	print("Ожидание урожая не запирает игру")
	_fresh()
	GameState.tame("disco_sprout", COMMON)
	GameState.set_guardian("disco_sprout:0")

	# Занял все грядки самым долгим, что есть
	var slowest: FruitData = null
	for fruit in Registry.all_fruits():
		if slowest == null or fruit.grow_seconds() > slowest.grow_seconds():
			slowest = fruit
	check(slowest != null, "фрукты в реестре есть")
	if slowest == null:
		return

	FarmState.add_seed(slowest.id, FarmState.plot_count())
	for i in FarmState.plot_count():
		FarmState.plant(i, slowest.id)

	# Лес открыт независимо от фермы: ждать урожая, ничего не делая, не нужно
	check(RunManager.start_run(GameState.guardian_key()),
		"с занятыми грядками в лес не пускают — игроку нечем заняться")
