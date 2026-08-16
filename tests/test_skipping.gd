extends TestHarness

## Правило пропуска боёв (GDD §8.1) и витрина награды (§8.1.2).
##
## Пропустить можно только то, что уже превзойдено: вид приручён в этом
## грейде или выше. Всё новое — обязательный бой. Правило живёт в одной
## точке `_blocks_swipe`, и эти тесты стерегут именно её.

const COMMON := MonsterData.Rarity.COMMON
const RARE := MonsterData.Rarity.RARE
const LEGENDARY := MonsterData.Rarity.LEGENDARY


func run_tests() -> void:
	await _test_unknown_species_blocks()
	await _test_same_grade_lets_pass()
	await _test_higher_grade_blocks()
	await _test_lower_grade_lets_pass()
	_test_skipping_changes_nothing()
	await _test_card_shows_stakes()


func _fresh() -> void:
	GameState.reset()
	FarmState.reset()
	RunManager.set_seed(4242)


## Сцена ленты с подставленной боевой поляной: правило проверяем на живом
## объекте, а не на копии логики в тесте.
func _feed_with_battle(species_id: String, grade: int) -> Node:
	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(2)

	var glade := Glade.new()
	glade.type = Glade.Type.BATTLE
	glade.depth = 3
	glade.monster_id = species_id
	glade.grade = grade
	glade.silver_reward = 12
	RunManager.current_glade = glade
	feed._glade_cleared = false
	return feed


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _blocks(species_id: String, grade: int) -> bool:
	var feed: Node = await _feed_with_battle(species_id, grade)
	var blocked: bool = feed._blocks_swipe()

	# Заблокированная кнопка обязана СКАЗАТЬ, почему: серая «Дальше ↑»
	# на живом прогоне читалась как сломанная, и игрок жал её впустую
	feed._refresh_buttons()
	var label: String = feed._next_button.text
	if blocked:
		check(feed._next_button.disabled, "%s: кнопка «дальше» выключена" % species_id)
		check(label != "Дальше ↑",
			"%s: подпись объясняет отказ, а не молчит: [%s]" % [species_id, label])
	else:
		check(not feed._next_button.disabled, "%s: кнопка «дальше» доступна" % species_id)

	feed.queue_free()
	await _frames(1)
	return blocked


## Проверяем НАБЛЮДАЕМОЕ поведение ленты (`_blocks_swipe`), а не удобное
## внутреннее поле: сломайся правило в сцене — и проверка модели этого
## не заметила бы.
func _test_unknown_species_blocks() -> void:
	print("Незнакомый вид держит на месте")
	_fresh()
	GameState.tame("bass_bear", COMMON)

	check(await _blocks("synth_slime", COMMON), "слайм незнаком — мимо не пройти")
	check(not await _blocks("bass_bear", COMMON), "медведь приручён — можно мимо")


func _test_same_grade_lets_pass() -> void:
	print("Превзойдённый в этом же грейде пропускается")
	_fresh()
	GameState.tame("disco_sprout", COMMON)
	check(not await _blocks("disco_sprout", COMMON),
		"обычный экземпляр превзойдён — лента отпускает")


## Главный случай новой модели: редкий Ростик при обычном в коллекции —
## всё ещё обязательный бой.
func _test_higher_grade_blocks() -> void:
	print("Грейд выше приручённого держит на месте")
	_fresh()
	GameState.tame("disco_sprout", COMMON)

	check(await _blocks("disco_sprout", RARE),
		"редкий того же вида не превзойдён — бой обязателен")
	check(await _blocks("disco_sprout", LEGENDARY),
		"легендарный тем более")


func _test_lower_grade_lets_pass() -> void:
	print("Грейд ниже приручённого пропускается")
	_fresh()
	GameState.tame("disco_sprout", LEGENDARY)

	# «В этом грейде ИЛИ ВЫШЕ»: легендарный друг закрывает весь вид
	for grade in MonsterData.RARITY_NAMES.size():
		check(not await _blocks("disco_sprout", grade),
			"легендарный друг превзошёл грейд %s" % MonsterData.rarity_name(grade))


## Пропуск не даёт ничего: ни дружбы, ни опыта. Это честная цена решения.
func _test_skipping_changes_nothing() -> void:
	print("Пропуск ничего не начисляет")
	_fresh()
	GameState.tame("disco_sprout", COMMON)

	var friendship_before := GameState.get_friendship("disco_sprout", COMMON)
	var xp_before := GameState.battle_experience("disco_sprout")

	RunManager.start_run(GameState.guardian_key())
	var skipped := 0
	for i in 40:
		var glade := RunManager.advance()
		if glade.type == Glade.Type.BATTLE:
			skipped += 1
	RunManager.go_home()

	check(skipped > 0, "боевые поляны в ленте попались (%d)" % skipped)
	check_eq(GameState.get_friendship("disco_sprout", COMMON), friendship_before,
		"дружба не выросла от одного лишь прохода мимо")
	check_eq(GameState.battle_experience("disco_sprout"), xp_before,
		"опыт против вида тоже не вырос")


## Карточка обязана показывать, что игрок теряет, пролистывая.
func _test_card_shows_stakes() -> void:
	print("Карточка показывает награду за бой")
	_fresh()
	GameState.tame("bass_bear", COMMON)

	# Дружба почти полна: следующая победа приручит — это самый дорогой
	# для пропуска случай, и он обязан быть виден крупно
	var threshold := GameState.friendship_threshold(COMMON)
	GameState.add_friendship("synth_slime", COMMON, threshold - GameState.FRIENDSHIP_WIN)

	var feed: Node = await _feed_with_battle("synth_slime", COMMON)
	feed._show_glade(RunManager.current_glade)
	await _frames(2)

	check(feed._tame_banner.visible, "пометка «можно подружиться» показана")
	check(feed._friendship_label.text.contains("%d" % threshold),
		"на карточке виден порог дружбы: [%s]" % feed._friendship_label.text)
	check(feed._reward_label.text.contains("серебра"),
		"на карточке видна награда серебром: [%s]" % feed._reward_label.text)

	# У монстра, до которого ещё далеко, крупной пометки быть не должно
	var far := Glade.new()
	far.type = Glade.Type.BATTLE
	far.depth = 3
	far.monster_id = "banjo_moth"
	far.grade = LEGENDARY
	far.silver_reward = 12
	RunManager.current_glade = far
	feed._show_glade(far)
	await _frames(2)
	check(not feed._tame_banner.visible,
		"до легендарного далеко — обещания подружиться нет")

	# На небоевой поляне витрина прячется целиком
	var bush := Glade.new()
	bush.type = Glade.Type.WILD_BUSH
	bush.depth = 4
	bush.fruit_id = "drum_berry"
	RunManager.current_glade = bush
	feed._show_glade(bush)
	await _frames(2)
	check(not feed._friendship_track.visible, "на кусте полоски дружбы нет")
	check(not feed._tame_banner.visible, "и пометки о дружбе тоже")

	feed.queue_free()
	await _frames(2)
	RunManager.go_home()
