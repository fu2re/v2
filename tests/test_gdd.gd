extends TestHarness

## GDD не расходится с игрой.
##
## Документ, разошедшийся с кодом, хуже отсутствующего: по нему принимают
## решения, и каждое устаревшее место однажды стоит чьего-то дня. Расхождение
## накапливается молча — никто не забывает специально, просто дописывают код
## и не дописывают документ.
##
## Сторожится не весь текст (это невозможно и не нужно), а те места, где
## GDD ПЕРЕЧИСЛЯЕТ состав игры: автозагрузчики, каталоги сцен, валюты,
## типы полян, типы нот. Именно перечисления устаревают первыми.

const GDD := "res://GDD.md"

## Каталоги сцен, которых в документе быть не обязано: служебные,
## в сборку не идут.
const SKIP_DIRS: Array[String] = []


func run_tests() -> void:
	_test_every_autoload_is_documented()
	_test_no_phantom_autoloads()
	_test_every_scene_folder_is_documented()
	_test_note_types_match()
	_test_glade_types_match()
	_test_rarities_match()
	_test_collection_opens_in_steps()


func _gdd_text() -> String:
	return FileAccess.get_file_as_string(GDD)


func _autoload_names() -> PackedStringArray:
	var out := PackedStringArray()
	var source := FileAccess.get_file_as_string("res://project.godot")
	var inside := false
	for raw in source.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("["):
			inside = line == "[autoload]"
			continue
		if not inside or not line.contains("="):
			continue
		out.append(line.split("=")[0])
	return out


## Каждый автозагрузчик обязан быть в таблице §13.1. Незадокументированный
## синглтон — это состояние, о котором не знает тот, кто читает документ,
## и который поэтому заведёт себе второе такое же.
func _test_every_autoload_is_documented() -> void:
	print("Каждый автозагрузчик описан в GDD")
	var text := _gdd_text()
	var names := _autoload_names()
	check(names.size() >= 5, "автозагрузчики нашлись (%d)" % names.size())
	for name: String in names:
		check(text.contains("`%s`" % name),
			"автозагрузчик %s не описан в GDD §13.1" % name)


## И наоборот: таблица не должна обещать того, чего нет. Строка про
## несуществующий синглтон посылает читателя искать несуществующий файл.
func _test_no_phantom_autoloads() -> void:
	print("GDD не обещает несуществующих автозагрузчиков")
	var names := _autoload_names()
	var known := {}
	for name: String in names:
		known[name] = true

	# Читаем ровно строки таблицы §13.1: «| `Имя` | ... |»
	var text := _gdd_text()
	var start := text.find("### 13.1")
	var finish := text.find("### 13.2")
	check(start >= 0 and finish > start, "раздел 13.1 нашёлся")
	if start < 0 or finish <= start:
		return

	for raw in text.substr(start, finish - start).split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("| `"):
			continue
		var name := line.substr(3, line.find("`", 3) - 3)
		check(known.has(name),
			"GDD описывает автозагрузчик %s, которого нет в project.godot" % name)


func _test_every_scene_folder_is_documented() -> void:
	print("Каждый каталог сцен описан в GDD")
	var text := _gdd_text()
	var dir := DirAccess.open("res://scenes")
	check(dir != null, "каталог scenes открылся")
	if dir == null:
		return

	for folder in dir.get_directories():
		if SKIP_DIRS.has(folder):
			continue
		check(text.contains("%s/" % folder),
			"каталог scenes/%s не описан в GDD §13.2" % folder)


## Типы нот, полян и грейдов перечислены и в коде, и в документе. Разошлись —
## значит кто-то добавил механику и не сказал остальным.
func _test_note_types_match() -> void:
	print("Типы нот совпадают с документом")
	var text := _gdd_text()
	for type: String in ["beat", "attack", "skill", "shield", "heavy"]:
		check(text.contains("`%s`" % type), "тип ноты %s не описан в GDD" % type)


func _test_glade_types_match() -> void:
	print("Типы полян совпадают с документом")
	var text := _gdd_text()
	for key: int in Glade.TYPE_KEYS:
		var title: String = Glade.TYPE_NAMES[key]
		check(text.contains(title.to_lower()) or text.contains(title),
			"тип поляны «%s» не описан в GDD" % title)


func _test_rarities_match() -> void:
	print("Грейды совпадают с документом")
	var text := _gdd_text()
	for grade in range(MonsterData.Rarity.size()):
		var title := MonsterData.rarity_name(grade)
		check(text.contains(title),
			"грейд «%s» не описан в GDD" % title)


## Коллекция открывается ступенями: встретил → победил → приручил.
##
## Проверка появилась по живому отчёту: игрок встретил в забеге уникальных
## монстров, а в коллекции они остались чёрными — встреча не отмечалась вовсе,
## и единственным событием была победа.
func _test_collection_opens_in_steps() -> void:
	print("Коллекция открывается ступенями")
	SaveManager.enter_test_mode()
	GameState.reset()

	var id := "beat_serpent"
	var grade := MonsterData.Rarity.UNIQUE

	check_eq(CollectionGrid.state_for(id, grade), CollectionGrid.Cell.HIDDEN,
		"незнакомый — силуэт")

	GameState.mark_met(id, grade)
	check_eq(CollectionGrid.state_for(id, grade), CollectionGrid.Cell.MET,
		"встреченный — уже не силуэт")
	check(CollectionGrid.opens_card(id, grade), "по встреченному карточка открывается")

	GameState.mark_defeated(id, grade)
	check_eq(CollectionGrid.state_for(id, grade), CollectionGrid.Cell.REVEALED,
		"побеждённый — открытый скин")

	GameState.tame(id, MonsterData.Rarity.COMMON)
	GameState.tame(id, MonsterData.Rarity.UNCOMMON)
	GameState.tame(id, MonsterData.Rarity.RARE)
	GameState.tame(id, grade)
	check_eq(CollectionGrid.state_for(id, grade), CollectionGrid.Cell.TAMED,
		"приручённый — в рамке")

	# Ступени обязаны пережить сейв: коллекция собирается неделями
	var saved: Variant = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(saved)
	check_eq(CollectionGrid.state_for(id, grade), CollectionGrid.Cell.TAMED,
		"после сейва состояние клетки то же")
