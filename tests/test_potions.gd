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
	_test_cheapest_goes_first()
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
	check(all.size() >= 2, "зелья в реестре (%d)" % all.size())
	for potion in all:
		check(not potion.id.is_empty(), "у зелья есть id")
		check(potion.restore_health > 0, "%s лечит" % potion.id)
		# Зелья — часть игрового контура: только за серебро (GDD §12)
		check(potion.price > 0, "%s продаётся за серебро" % potion.id)


func _test_inventory() -> void:
	print("Инвентарь зелий")
	GameState.reset()
	check(not GameState.has_any_potion(), "сумка пуста")

	GameState.add_potion("berry_cordial", 2)
	check_eq(GameState.potion_count("berry_cordial"), 2, "морсов два")
	check(GameState.has_any_potion(), "есть что пить")

	var restored := GameState.consume_potion()
	check(restored > 0, "глоток вернул здоровье (%d)" % restored)
	check_eq(GameState.potion_count("berry_cordial"), 1, "остался один")

	GameState.consume_potion()
	check(not GameState.has_any_potion(), "сумка снова пуста")
	check_eq(GameState.consume_potion(), 0, "пить нечего — и ничего не возвращается")


## Дорогое бережётся само: в ритме выбирать некогда.
func _test_cheapest_goes_first() -> void:
	print("Первым пьётся самое слабое")
	GameState.reset()
	GameState.add_potion("honey_brew")
	GameState.add_potion("berry_cordial")

	var cordial := Registry.potion("berry_cordial")
	check_eq(GameState.next_potion().id, "berry_cordial", "следующим идёт морс")
	check_eq(GameState.consume_potion(), cordial.restore_health, "он и выпит")
	check_eq(GameState.next_potion().id, "honey_brew", "отвар остался на потом")


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
	GameState.add_potion("berry_cordial", 3)

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
	GameState.add_potion("berry_cordial", 2)

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
	check_eq(GameState.potion_count("berry_cordial"), 2, "обычной кнопкой зелье сбережено")
	check_eq(battle.state.health, health_before, "и здоровье не изменилось")

	# Особой кнопкой: зелье выпито, здоровье вернулось
	var second: Note = battle._pool.acquire(Conductor.song_beat, ChartData.NoteType.SNACK)
	battle._active.append(second)
	battle._judge_tap(NoteRules.Lane.SPECIAL)
	check_eq(GameState.potion_count("berry_cordial"), 1, "особой кнопкой зелье выпито")
	check(battle.state.health > health_before, "и здоровье выросло")

	Conductor.stop()
	battle.queue_free()
	await _frames(2)


func _test_survives_save() -> void:
	print("Зелья переживают сейв")
	GameState.reset()
	GameState.add_potion("honey_brew", 4)

	var restored: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(restored)

	check_eq(GameState.potion_count("honey_brew"), 4, "зелья на месте после сейва")
