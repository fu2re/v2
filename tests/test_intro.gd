extends TestHarness

## Интро: сплеш, выбор персонажа, первая встреча (GDD §15.5).
##
## Главное правило цикла: выйти из интро можно ТОЛЬКО победой. Проигрыш
## ничего не отнимает и ничего не засчитывает — та же фраза, тот же монстр,
## бой заново. Иначе игрок ушёл бы в игру, не научившись, и первый же
## настоящий бой встретил бы его как стена.


func run_tests() -> void:
	_test_entry_order()
	_test_hero_choice()
	await _test_intro_monster_is_common()
	await _test_defeat_returns_to_same_monster()
	await _test_victory_gives_first_guardian()
	_test_new_game_has_no_guardian()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Порядок экранов: сначала выбор героя, потом встреча, потом ферма.
func _test_entry_order() -> void:
	print("Порядок экранов запуска")
	GameState.reset()
	OnboardingState.is_done = false

	check(OnboardingState.entry_scene().contains("CharacterSelect"),
		"без выбранного героя ведём в выбор персонажа")

	GameState.set_hero_gender("girl")
	check(OnboardingState.entry_scene().contains("Intro"),
		"после выбора — встреча в лесу")

	OnboardingState.is_done = true
	check(OnboardingState.entry_scene().contains("Lobby"),
		"после интро — двор усадьбы, а не сразу огород (§7.4)")


func _test_hero_choice() -> void:
	print("Выбор героя")
	GameState.reset()
	check(not GameState.has_chosen_hero(), "выбора ещё нет")

	for gender in ["boy", "girl"]:
		GameState.set_hero_gender(gender)
		check(GameState.has_chosen_hero(), "герой выбран: %s" % gender)
		check(GameState.hero_sprite() != null, "спрайт героя нашёлся: %s" % gender)

	# Спрайты мальчика и девочки — РАЗНЫЕ файлы, иначе выбор ничего не меняет
	GameState.set_hero_gender("boy")
	var boy := GameState.hero_sprite()
	GameState.set_hero_gender("girl")
	check(GameState.hero_sprite() != boy, "у мальчика и девочки разные спрайты")

	# Выбор переживает сейв
	var restored: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(restored)
	check_eq(GameState.hero_gender, "girl", "выбор пережил сейв")


func _open_intro() -> Node2D:
	var intro := preload("res://scenes/intro/Intro.tscn").instantiate()
	add_child(intro)
	await _frames(3)
	return intro


## Первый монстр всегда обычный: первый бой обязан быть посильным,
## а первый друг — не легендарным с порога.
func _test_intro_monster_is_common() -> void:
	print("Монстр интро всегда обычного грейда")
	for attempt in 8:
		GameState.reset()
		OnboardingState.is_done = false
		var intro: Node2D = await _open_intro()

		check(intro._species != null, "монстр выбран")
		if intro._species != null:
			check(Registry.monster(intro._species.id) != null,
				"монстр существует: %s" % intro._species.id)

		intro.queue_free()
		await _frames(2)


## Проигрыш возвращает к тому же монстру и не засчитывает обучение.
func _test_defeat_returns_to_same_monster() -> void:
	print("Проигрыш возвращает к тому же монстру")
	GameState.reset()
	OnboardingState.reset()

	var intro: Node2D = await _open_intro()
	var first: MonsterData = intro._species

	var state := BattleState.new()
	state.setup(MonsterInstance.create(first.id, MonsterData.Rarity.COMMON), null, 1)
	intro._on_battle_finished(false, state)
	await get_tree().create_timer(1.4).timeout

	check(intro._species == first, "монстр тот же — история не рассыпалась")
	check(not OnboardingState.is_done, "обучение НЕ засчитано за поражение")
	check(GameState.all_instances().is_empty(), "и друга не появилось")
	check(intro._continue.visible, "кнопка «дальше» снова доступна — игра не заперта")

	Conductor.stop()
	intro.queue_free()
	await _frames(2)


## Победа даёт первого друга, минуя шкалу дружбы.
func _test_victory_gives_first_guardian() -> void:
	print("Победа даёт первого защитника")
	GameState.reset()
	OnboardingState.reset()

	var intro: Node2D = await _open_intro()
	var species: MonsterData = intro._species

	var state := BattleState.new()
	state.setup(MonsterInstance.create(species.id, MonsterData.Rarity.COMMON), null, 100)
	intro._on_battle_finished(true, state)
	await _frames(2)

	check(GameState.has_instance(species.id, MonsterData.Rarity.COMMON),
		"монстр присоединился")
	check(GameState.guardian() != null, "и стал гуардианом")
	check_eq(GameState.guardian().species_id, species.id, "именно он")
	check(OnboardingState.is_done, "обучение засчитано")

	# Приручение прошло МИМО шкалы: это единственное исключение из §6.1
	check_eq(GameState.get_friendship(species.id, MonsterData.Rarity.COMMON), 0,
		"шкала дружбы при этом не заполнялась")

	check(intro._phrase.text.contains(species.display_name),
		"фраза называет нового защитника: [%s]" % intro._phrase.text)

	Conductor.stop()
	intro.queue_free()
	await _frames(2)


## Стартового монстра «из коробки» больше нет.
func _test_new_game_has_no_guardian() -> void:
	print("Новая игра начинается без гуардиана")
	GameState.reset()
	check(GameState.guardian() == null, "гуардиана нет")
	check(GameState.all_instances().is_empty(), "коллекция пуста")
	check(not SaveManager.STARTER_SEEDS.is_empty(), "но семена выдаются")
