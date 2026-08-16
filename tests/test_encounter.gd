extends TestHarness

## Встречи в ленте (GDD §8.2.1).
##
## Поляна-встреча заменила торговца и «событие»: внутри неё случайно
## попадается торговец, куст с гостинцами или бабушка. Главное правило,
## которое здесь стерегут: бабушка НИКОГДА не просит больше, чем есть
## в кармане. Предложение, которое нельзя принять, — издёвка, а не выбор.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	_test_encounter_kinds_appear()
	_test_bush_is_never_empty()
	_test_granny_never_asks_more_than_you_have()
	_test_granny_with_empty_pockets_asks_nothing()
	_test_granny_gives_something_back()
	_test_refusing_granny_costs_nothing()


func _fresh_run() -> void:
	GameState.reset()
	FarmState.reset()
	RunManager.set_seed(31337)
	GameState.tame("disco_sprout", COMMON)
	RunManager.start_run(GameState.guardian_key())


## Сколько семян в мешке ВСЕГО.
##
## Считаем количество, а не число ключей: второе семя того же вида
## не меняет размер словаря, и проверка по размеру пропустила бы выдачу.
func _total_seeds() -> int:
	var total := 0
	for count: int in RunManager.run_seed_bag.values():
		total += count
	return total


## Все три вида встреч должны реально попадаться: доля, записанная
## в таблице, но не выпадающая ни разу, — это мёртвый контент.
func _test_encounter_kinds_appear() -> void:
	print("Все виды встреч попадаются")
	_fresh_run()

	var seen: Dictionary = {}
	for i in 600:
		var glade := RunManager.advance()
		if glade.type == Glade.Type.ENCOUNTER:
			seen[glade.encounter] = int(seen.get(glade.encounter, 0)) + 1
	RunManager.go_home()

	for kind: Glade.Encounter in [Glade.Encounter.MERCHANT,
			Glade.Encounter.LOOT_BUSH, Glade.Encounter.GRANNY]:
		check(seen.has(kind), "встреча «%s» попадалась (%d раз)"
			% [Glade.ENCOUNTER_NAMES[kind], int(seen.get(kind, 0))])

	# Загадка не спроектирована, её доля нулевая — и она не должна выпадать
	check(not seen.has(Glade.Encounter.RIDDLE),
		"загадка не выпадает, пока её нет")


## «Потряс и ничего» — обещание, которое игра не сдержала.
func _test_bush_is_never_empty() -> void:
	print("Куст всегда что-нибудь даёт")
	_fresh_run()

	for i in 40:
		var before_silver := RunManager.run_silver
		var before_seeds := _total_seeds()
		var before_gear := _total_gear()

		var text := RunManager.shake_bush(5)
		check(not text.is_empty(), "куст сказал, что дал")

		var got := RunManager.run_silver > before_silver \
			or _total_seeds() > before_seeds \
			or _total_gear() > before_gear
		check(got, "куст действительно что-то дал (%s)" % text)

	RunManager.go_home()


## Главное правило бабушки.
func _test_granny_never_asks_more_than_you_have() -> void:
	print("Бабушка не просит больше, чем есть")
	_fresh_run()

	for purse in [1, 5, 17, 60, 250, 1000]:
		RunManager.run_silver = purse
		for i in 30:
			var asked := RunManager.granny_request()
			check(asked <= purse,
				"при %d в кармане просит не больше (%d)" % [purse, asked])
			check(asked >= 1, "и просит хоть что-то (%d)" % asked)

	RunManager.go_home()


func _test_granny_with_empty_pockets_asks_nothing() -> void:
	print("С пустым карманом бабушка не просит вовсе")
	_fresh_run()
	RunManager.run_silver = 0
	check_eq(RunManager.granny_request(), 0, "просьбы нет")
	RunManager.go_home()


func _test_granny_gives_something_back() -> void:
	print("За щедрость бабушка благодарит")
	_fresh_run()
	RunManager.run_silver = 200

	const PAID := 10
	for i in 20:
		var before_seeds := _total_seeds()
		var before_gear := _total_gear()
		var before_silver := RunManager.run_silver

		var gift := RunManager.pay_granny(PAID)
		check(not gift.is_empty(), "подарок назван")

		# Серебро тоже считается подарком: не всякий раз находится семя.
		# Сравниваем с тем, что осталось ПОСЛЕ платы, — иначе собственный
		# взнос игрока замаскировал бы отсутствие подарка
		var got := _total_seeds() > before_seeds \
			or _total_gear() > before_gear \
			or RunManager.run_silver > before_silver - PAID
		check(got, "подарок действительно получен (%s)" % gift)

	RunManager.go_home()


## Отказ — законный выбор, а не проступок: он ничего не отнимает.
func _test_refusing_granny_costs_nothing() -> void:
	print("Отказ ничем не наказывается")
	_fresh_run()
	RunManager.run_silver = 120

	var silver_before := RunManager.run_silver
	var health_before := RunManager.health
	var shield_before := RunManager.shield

	# Просьба прозвучала, игрок прошёл мимо — состояние не изменилось
	RunManager.granny_request()

	check_eq(RunManager.run_silver, silver_before, "серебро на месте")
	check_eq(RunManager.health, health_before, "здоровье не тронуто")
	check_eq(RunManager.shield, shield_before, "щит не тронут")

	# И заплатить нельзя больше, чем есть, даже если попросить
	RunManager.pay_granny(99999)
	check(RunManager.run_silver >= 0, "серебро не уходит в минус")

	RunManager.go_home()


## Сколько ЕДИНИЦ снаряжения на руках.
##
## Считаем штуки, а не виды: повторный плащ увеличивает счётчик своего вида,
## но не длину списка, и проверка «дал ли куст хоть что-то» на дубликате
## врала, будто куст оказался пустым.
func _total_gear() -> int:
	var total := 0
	for gear_id: String in GameState.owned_gear_ids():
		total += GameState.gear_count(gear_id)
	return total
