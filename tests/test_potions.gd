extends TestHarness

## Зелья и нота-зелье (GDD §4.2.3).
##
## Две вещи здесь важнее прочего. Первая: игра никогда не предлагает нажать
## то, что не сработает, — нет зелья, нет и ноты. Вторая: у ноты-зелья есть
## выбор, и он принимается в ритме — особой кнопкой выпить, обычной сберечь.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	_test_registry()
	_test_inventory()
	_test_bag_has_a_limit()

	_test_full_bag_refuses_purchase()
	await _test_note_absent_without_potions()
	await _test_note_present_with_potions()
	await _test_special_drinks_normal_saves()
	_test_survives_save()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _test_registry() -> void:
	print("Зелья загружаются")
	var all := Registry.all_potions()
	# Зелье в игре ровно одно и намеренно: выбор посреди ритмической фразы
	# игрок всё равно не успевает сделать
	check(all.size() >= 1, "зелья в реестре (%d)" % all.size())
	for potion in all:
		check(not potion.id.is_empty(), "у зелья есть id")
		check(potion.restore_health > 0, "%s лечит" % potion.id)
		# Зелья — часть игрового контура: только за серебро (GDD §12)
		check(potion.price > 0, "%s продаётся за серебро" % potion.id)


func _test_inventory() -> void:
	print("Инвентарь зелий")
	GameState.reset()
	check(not GameState.has_any_potion(), "сумка пуста")

	GameState.add_potion("health_potion", 2)
	check_eq(GameState.potion_count("health_potion"), 2, "отваров два")
	check(GameState.has_any_potion(), "есть что пить")

	var restored := GameState.consume_potion()
	check(restored > 0, "глоток вернул здоровье (%d)" % restored)
	check_eq(GameState.potion_count("health_potion"), 1, "остался один")

	GameState.consume_potion()
	check(not GameState.has_any_potion(), "сумка снова пуста")
	check_eq(GameState.consume_potion(), 0, "пить нечего — и ничего не возвращается")


## Сумка зелий ограничена: три глотка — предел, а не склад.
func _test_bag_has_a_limit() -> void:
	print("С собой не больше трёх")
	GameState.reset()

	var taken := GameState.add_potion("health_potion", 10)
	check_eq(taken, GameState.MAX_POTIONS, "взято ровно столько, сколько влезло")
	check_eq(GameState.total_potions(), GameState.MAX_POTIONS, "в сумке предел")
	check(not GameState.has_potion_room(), "места больше нет")

	check_eq(GameState.add_potion("health_potion", 1), 0, "сверх предела не берётся")
	check_eq(GameState.total_potions(), GameState.MAX_POTIONS, "и число не выросло")

	# Выпил — место освободилось
	GameState.consume_potion()
	check(GameState.has_potion_room(), "после глотка место есть")


## Покупка сверх предела не должна забирать серебро: молча съеденные деньги
## выглядят как работающая покупка, и это худший вид поломки.
func _test_full_bag_refuses_purchase() -> void:
	print("Полная сумка не даёт купить")
	GameState.reset()
	GameState.add_silver(500)
	GameState.add_potion("health_potion", GameState.MAX_POTIONS)

	var potion := Registry.potion("health_potion")
	var silver_before := GameState.silver
	check(not MerchantStock.buy(potion), "покупка отклонена")
	check_eq(GameState.silver, silver_before, "серебро на месте")
	check_eq(GameState.total_potions(), GameState.MAX_POTIONS, "зелий не прибавилось")


func _battle(chart_id: String = "demo_disco") -> Node2D:
	var battle := preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	battle.autostart = false
	battle.chart_id = chart_id
	battle.monster_id = "synth_slime"
	battle.guardian_key = GameState.tame("disco_sprout", COMMON).key()
	add_child(battle)
	await _frames(2)
	return battle


func _count_potion_notes(chart: ChartData) -> int:
	var count := 0
	for i in chart.note_count():
		if chart.note_types[i] == ChartData.NoteType.SNACK:
			count += 1
	return count


## Нет зелья — нет и ноты: игра не предлагает нажать то, что не сработает.
func _test_note_absent_without_potions() -> void:
	print("Без зелий нота-зелье не ставится")
	GameState.reset()

	var source := ChartLoader.load_by_id("demo_disco", "normal")
	var original := _count_potion_notes(source)
	check(original > 0, "в исходном чарте нота-зелье есть (%d)" % original)

	var battle: Node2D = await _battle()
	battle.begin(ChartLoader.load_by_id("demo_disco", "normal"))
	await _frames(2)

	check_eq(_count_potion_notes(battle.chart), 0, "в бою нот-зелий не осталось")
	# Ноты не выброшены, а заменены: иначе поехала бы плотность и порвались серии
	check_eq(battle.chart.note_count(), source.note_count(),
		"число нот не изменилось — ноты заменены, а не выброшены")

	Conductor.stop()
	battle.queue_free()
	await _frames(2)


func _test_note_present_with_potions() -> void:
	print("С зельем нота-зелье остаётся")
	GameState.reset()
	GameState.add_potion("health_potion", 3)

	var battle: Node2D = await _battle()
	battle.begin(ChartLoader.load_by_id("demo_disco", "normal"))
	await _frames(2)

	check(_count_potion_notes(battle.chart) > 0, "нота-зелье на месте")

	Conductor.stop()
	battle.queue_free()
	await _frames(2)


## Микрорешение прямо в ритме: выпить или сберечь.
func _test_special_drinks_normal_saves() -> void:
	print("Особая кнопка пьёт, обычная сберегает")
	GameState.reset()
	GameState.add_potion("health_potion", 2)

	var battle: Node2D = await _battle()
	battle.begin(ChartLoader.load_by_id("demo_disco", "normal"))
	await _frames(2)

	battle.state.health = battle.state.max_health - 40

	# Обычной кнопкой: попадание засчитано, зелье цело
	var note: Note = battle._pool.acquire(Conductor.song_beat, ChartData.NoteType.SNACK)
	battle._active.append(note)
	# Тип явно: чтение через узел даёт Variant
	var health_before: int = battle.state.health
	battle._judge_tap(NoteRules.Lane.NORMAL)
	check_eq(GameState.potion_count("health_potion"), 2, "обычной кнопкой зелье сбережено")
	check_eq(battle.state.health, health_before, "и здоровье не изменилось")

	# Особой кнопкой: зелье выпито, здоровье вернулось
	var second: Note = battle._pool.acquire(Conductor.song_beat, ChartData.NoteType.SNACK)
	battle._active.append(second)
	battle._judge_tap(NoteRules.Lane.SPECIAL)
	check_eq(GameState.potion_count("health_potion"), 1, "особой кнопкой зелье выпито")
	check(battle.state.health > health_before, "и здоровье выросло")

	Conductor.stop()
	battle.queue_free()
	await _frames(2)


func _test_survives_save() -> void:
	print("Зелья переживают сейв")
	GameState.reset()
	GameState.add_potion("health_potion", 2)

	var restored: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(restored)

	check_eq(GameState.potion_count("health_potion"), 2, "зелья на месте после сейва")
