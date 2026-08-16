extends TestHarness

## Проверки магазина.
##
## Здесь под охраной не игровой баланс, а регуляторные требования (GDD §12.3).
## Нарушение любого из них — это не «неприятный баг», а игра, которую не примут
## в сторы или запретят в отдельных странах. Поэтому проверяем инварианты,
## а не поведение отдельных кнопок.

func run_tests() -> void:
	ShopState.reset()
	ShopState.set_seed(1337)

	_test_cosmetics_cannot_affect_gameplay()
	_test_every_crate_item_sold_directly()
	_test_odds_sum_to_hundred()
	_test_odds_disclosed_before_purchase()
	_test_pity_guarantees_rare()
	_test_duplicates_never_wasted()
	_test_region_ban_blocks_crates()
	_test_daily_limit()
	_test_no_purchase_without_funds()
	_test_save_roundtrip()


## Правило 4 из GDD §12.3: ни один предмет за реальные деньги не влияет
## на цифры геймплея. Проверяется по СТРУКТУРЕ данных, а не по значениям:
## у косметики физически нет полей, которыми можно дать преимущество.
func _test_cosmetics_cannot_affect_gameplay() -> void:
	print("Косметика не может влиять на геймплей")
	var forbidden := [
		"window_scale", "power_bonus", "health_bonus", "shield_reduction",
		"base_power", "base_vibe", "base_health", "friendship_bonus",
	]
	var items := Registry.all_cosmetics()
	check(items.size() >= 10, "косметика загрузилась (%d)" % items.size())

	for item in items:
		for field in forbidden:
			check(not (field in item),
				"%s не имеет поля '%s' — pay-to-win невозможен по структуре"
					% [item.id, field])


## Правило 5: в Бельгии и Нидерландах лутбоксы запрещены, поэтому ЛЮБОЙ
## предмет из сундука обязан продаваться напрямую. Без этого игра
## непубликуема в этих странах.
func _test_every_crate_item_sold_directly() -> void:
	print("Всё из сундуков продаётся напрямую")
	var pool := ShopState.crate_pool()
	check(not pool.is_empty(), "пул сундука не пуст (%d)" % pool.size())
	for item in pool:
		check(item.price_gold > 0,
			"%s имеет цену прямой покупки (%d)" % [item.id, item.price_gold])

	# И наоборот: предмет вне сундуков тоже должен быть доступен
	for item in Registry.all_cosmetics():
		check(item.price_gold > 0, "%s можно купить напрямую" % item.id)


## Правило 1: публикуемые шансы обязаны быть настоящими.
func _test_odds_sum_to_hundred() -> void:
	print("Шансы в сумме дают ровно 100%")
	check(absf(ShopState.odds_total() - 100.0) < 0.001,
		"сумма шансов %.3f" % ShopState.odds_total())

	for rarity: MonsterData.Rarity in ShopState.CRATE_ODDS:
		check(ShopState.CRATE_ODDS[rarity] > 0.0,
			"%s имеет ненулевой шанс" % MonsterData.rarity_name(rarity))


func _test_odds_disclosed_before_purchase() -> void:
	print("Шансы раскрыты в тексте покупки")
	var text := ShopState.odds_disclosure()
	for rarity: MonsterData.Rarity in ShopState.CRATE_ODDS:
		check(text.contains(MonsterData.rarity_name(rarity)),
			"в раскрытии есть %s" % MonsterData.rarity_name(rarity))
	check(text.contains("%"), "проценты показаны")
	check(text.to_lower().contains("гарантированный"), "pity-счётчик показан")


## Правило 2: гарантированный редкий предмет, и счётчик виден игроку.
func _test_pity_guarantees_rare() -> void:
	print("Pity гарантирует редкий предмет")
	ShopState.reset()
	ShopState.set_seed(99)
	ShopState.add_gold(ShopState.CRATE_PRICE * ShopState.PITY_THRESHOLD * 2)
	ShopState.daily_limit = 999999

	var best_seen := -1
	var opens := 0
	while opens < ShopState.PITY_THRESHOLD:
		opens += 1
		var id := ShopState.open_crate()
		if id.is_empty():
			break
		var item := Registry.cosmetic(id)
		best_seen = maxi(best_seen, item.rarity)

	check(best_seen >= ShopState.PITY_MIN_RARITY,
		"за %d открытий редкий предмет выпал гарантированно (лучшее: %s)"
			% [ShopState.PITY_THRESHOLD, MonsterData.rarity_name(best_seen)])

	# Счётчик всегда в допустимых пределах, иначе цифра в интерфейсе врёт
	check(ShopState.pity_counter >= 0 and ShopState.pity_counter < ShopState.PITY_THRESHOLD,
		"счётчик pity в пределах: %d" % ShopState.pity_counter)


## Правило 3: дубль конвертируется в валюту, открытие не пропадает впустую.
func _test_duplicates_never_wasted() -> void:
	print("Дубли не пропадают")
	ShopState.reset()
	ShopState.set_seed(5)
	ShopState.daily_limit = 999999

	# Скупаем весь пул напрямую, чтобы гарантировать дубль из сундука
	var pool := ShopState.crate_pool()
	ShopState.add_gold(1000000)
	for item in pool:
		ShopState.buy_direct(item.id)
	check_eq(ShopState.owned.size(), pool.size(), "весь пул куплен")

	var before := ShopState.gold
	var id := ShopState.open_crate()
	check(not id.is_empty(), "сундук открылся")

	# Потратили CRATE_PRICE, но получили возврат — итог мягче полной потери
	var spent := before - ShopState.gold
	check(spent < ShopState.CRATE_PRICE,
		"дубль вернул часть золота (потрачено %d из %d)" % [spent, ShopState.CRATE_PRICE])

	for rarity: MonsterData.Rarity in ShopState.DUPLICATE_REFUND:
		check(ShopState.DUPLICATE_REFUND[rarity] > 0,
			"возврат за %s положителен" % MonsterData.rarity_name(rarity))


## Правило 5: региональная блокировка платного рандома.
func _test_region_ban_blocks_crates() -> void:
	print("Региональный запрет лутбоксов")
	ShopState.reset()
	ShopState.add_gold(100000)
	ShopState.daily_limit = 999999

	for region in ShopState.LOOTBOX_BANNED_REGIONS:
		ShopState.region = region
		check(ShopState.lootboxes_banned(), "%s: сундуки запрещены" % region)
		var before := ShopState.gold
		check_eq(ShopState.open_crate(), "", "%s: сундук не открылся" % region)
		check_eq(ShopState.gold, before, "%s: деньги не списаны" % region)

		# Но весь состав остаётся доступен прямой покупкой.
		# Владение сбрасываем: иначе второй регион уткнётся в «уже куплено»
		# от первого и тест начнёт врать
		ShopState.owned.clear()
		var pool := ShopState.crate_pool()
		check(not pool.is_empty(), "%s: пул есть" % region)
		for item in pool:
			check(ShopState.buy_direct(item.id),
				"%s: %s покупается напрямую" % [region, item.id])

	ShopState.region = "XX"
	check(ShopState.lootboxes_allowed(), "в остальных регионах сундуки доступны")


## Правило 6: родительский контроль. Дневной лимит трат.
func _test_daily_limit() -> void:
	print("Дневной лимит трат")
	ShopState.reset()
	ShopState.add_gold(100000)
	ShopState.daily_limit = 200

	check_eq(ShopState.remaining_today(), 200, "лимит на старте дня полный")

	var cheap := _cheapest()
	check(ShopState.buy_direct(cheap.id), "первая покупка прошла")
	check(ShopState.remaining_today() < 200, "лимит уменьшился")

	ShopState.spent_today = ShopState.daily_limit
	check_eq(ShopState.remaining_today(), 0, "лимит исчерпан")

	var blocked: Array[String] = []
	ShopState.purchase_blocked.connect(func(reason): blocked.append(reason))

	var before := ShopState.gold
	check(not ShopState.open_crate(), "сундук за лимитом не открылся")
	check_eq(ShopState.gold, before, "деньги не списаны")
	check(not blocked.is_empty(), "игроку объяснили причину")


func _cheapest() -> CosmeticData:
	var all := Registry.all_cosmetics()
	var best: CosmeticData = all[0]
	for item in all:
		if item.price_gold < best.price_gold:
			best = item
	return best


func _test_no_purchase_without_funds() -> void:
	print("Без золота покупки нет")
	ShopState.reset()
	ShopState.daily_limit = 999999
	var item := _cheapest()

	check(not ShopState.buy_direct(item.id), "покупка без средств отклонена")
	check(not ShopState.is_owned(item.id), "предмет не выдан")
	check_eq(ShopState.gold, 0, "баланс не ушёл в минус")

	check_eq(ShopState.open_crate(), "", "сундук без средств не открылся")
	check_eq(ShopState.gold, 0, "баланс по-прежнему ноль")


func _test_save_roundtrip() -> void:
	print("Сейв магазина")
	ShopState.reset()
	ShopState.add_gold(777)
	ShopState.daily_limit = 999999
	var item := _cheapest()
	ShopState.buy_direct(item.id)
	ShopState.equip(item.id)
	ShopState.pity_counter = 17
	ShopState.region = "NL"

	# Через настоящий JSON: ключи слотов там становятся строками
	var restored: Dictionary = JSON.parse_string(JSON.stringify(ShopState.to_dict()))
	ShopState.reset()
	ShopState.from_dict(restored)

	check(ShopState.is_owned(item.id), "покупка восстановилась")
	check(ShopState.equipped_in(item.slot) != null, "надетое нашлось после JSON-цикла")
	check_eq(ShopState.pity_counter, 17, "счётчик pity восстановился")
	check(ShopState.lootboxes_banned(), "регион восстановился и запрет действует")
