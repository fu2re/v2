extends TestHarness

## Спрайты монстров по грейдам и герой (GDD §6.3, §15.5).
##
## Картинка, которой нет, превращается в розовый квадрат — и замечают это
## обычно на живом экране, а не в коде. Здесь проверяется, что лестница
## фолбэков ВСЕГДА разрешается в существующий файл, даже если арт неполон.

const GRADES := ["common", "uncommon", "rare", "unique", "epic", "legendary"]


func run_tests() -> void:
	MonsterData.forget_sprite_paths()

	_test_every_grade_resolves()
	_test_grades_actually_differ()
	_test_hero_sprites()
	_test_fallback_walks_down()


## Главная проверка: у каждого монстра каждый грейд даёт текстуру.
func _test_every_grade_resolves() -> void:
	print("Спрайт находится для каждого грейда")
	var missing: Array[String] = []

	for monster in Registry.all_monsters():
		for grade in GRADES.size():
			var texture := monster.sprite_for_grade(grade)
			check(texture != null, "%s / %s: спрайт есть"
				% [monster.id, GRADES[grade]])

			# Справочно отмечаем, что нарисовано не всё: это не провал,
			# пока лестница фолбэков держит картинку
			var path := "%s/%s_%s.png" % [MonsterData.SPRITE_DIR, monster.id, GRADES[grade]]
			if not ResourceLoader.exists(path):
				missing.append("%s_%s" % [monster.id, GRADES[grade]])

	if missing.is_empty():
		note("комплект полный: нарисованы все грейды всех видов")
	else:
		note("ещё не нарисованы: %s" % ", ".join(missing))


## Свой спрайт на каждый грейд — обещание из GDD §6.3: легендарный обязан
## отличаться от обычного ещё на карточке поляны, до боя.
func _test_grades_actually_differ() -> void:
	print("Грейды выглядят по-разному")
	for monster in Registry.all_monsters():
		var common := monster.sprite_for_grade(MonsterData.Rarity.COMMON)
		var legendary := monster.sprite_for_grade(MonsterData.Rarity.LEGENDARY)
		if common == null or legendary == null:
			continue
		check(common != legendary,
			"%s: легендарный нарисован иначе, чем обычный" % monster.id)


func _test_hero_sprites() -> void:
	print("Спрайты героя")
	GameState.reset()
	# Без выбора игра всё равно обязана рисоваться: экран выбора сам
	# показывает героев, и до него текстура уже нужна
	check(GameState.hero_sprite() != null, "до выбора есть чем рисовать")

	for gender in GameState.HERO_SPRITES:
		GameState.set_hero_gender(gender)
		check(GameState.hero_sprite() != null, "спрайт есть: %s" % gender)


## Лестница фолбэков: неизвестный вид не роняет игру.
func _test_fallback_walks_down() -> void:
	print("Фолбэк спускается по грейдам")
	var orphan := MonsterData.new()
	orphan.id = "no_such_monster"
	orphan.sprite_path = "res://art/placeholder/hero.png"

	# Ни одного грейдового файла у него нет — остаётся общий путь вида
	check(orphan.sprite_for_grade(MonsterData.Rarity.LEGENDARY) != null,
		"монстр без грейдовых спрайтов всё равно рисуется")
