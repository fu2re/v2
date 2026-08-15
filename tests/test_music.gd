extends TestHarness

## Музыка вне боя: экраны усадьбы, поляны, джинглы.
##
## Проверять здесь можно только наличие и маршрутизацию — звучит ли мелодия
## приятно, тест не скажет. Зато он ловит ровно тот класс поломок, который
## возникает на самом деле: файл переименовали, экран забыли подключить,
## пул поляны похудел до одной мелодии. Ни компиляция, ни подъём сцены
## этого не видят, а в игре получается тишина.

## Экраны, у каждого из которых обязана быть СВОЯ мелодия.
## Требование дизайна: попав в любое место усадьбы, игрок слышит именно его.
const SCREENS := ["lobby", "farm", "collection", "inventory", "merchant",
	"shop", "taming", "run_feed"]

## Джинглы событий.
const CUES := ["boot", "victory", "defeat"]

## Сколько мелодий обязано быть в пуле каждого типа поляны.
const GLADE_POOL_SIZE := 5

## Где какой экран включает музыку. Пара «файл → имя мелодии»: подключение
## живёт в коде экрана, и проверить его иначе как чтением кода нельзя —
## поднять все сцены разом дороже и хрупче.
const WIRING := {
	"res://scenes/lobby/lobby.gd": "lobby",
	"res://scenes/farm/farm.gd": "farm",
	"res://scenes/collection/collection.gd": "collection",
	"res://scenes/inventory/inventory.gd": "inventory",
	"res://scenes/merchant/merchant.gd": "merchant",
	"res://scenes/shop/shop.gd": "shop",
	"res://scenes/battle/taming_screen.gd": "taming",
}


func run_tests() -> void:
	_test_every_screen_has_its_own_track()
	_test_tracks_are_distinct()
	_test_every_cue_exists()
	_test_every_glade_type_has_a_pool()
	_test_every_screen_is_wired()
	_test_forest_and_battle_do_not_overlap()


## У каждого экрана усадьбы своя мелодия, и файл действительно на месте.
func _test_every_screen_has_its_own_track() -> void:
	print("У каждого экрана своя мелодия")
	var known: Array = Jukebox.known_screens()
	for screen: String in SCREENS:
		check(known.has(screen), "нет мелодии для экрана «%s»" % screen)
		# Проигрывание возвращает false, если файла нет на диске: так тест
		# ловит переименованный ogg, а не только пропуск в списке
		check(Jukebox.play_screen(screen), "мелодия «%s» не загрузилась" % screen)


## Мелодии не должны повторяться: «своя на каждом экране» — это про то,
## что по музыке слышно, где ты, а не про то, что она где-то играет.
func _test_tracks_are_distinct() -> void:
	print("Мелодии экранов не повторяются")
	var seen: Dictionary = {}
	for screen: String in SCREENS:
		Jukebox.play_screen(screen)
		var track: String = Jukebox.current_track()
		check(not seen.has(track),
			"экраны «%s» и «%s» играют одно и то же" % [seen.get(track, ""), screen])
		seen[track] = screen


func _test_every_cue_exists() -> void:
	print("Джинглы события на месте")
	var known: Array = Jukebox.known_cues()
	for cue: String in CUES:
		check(known.has(cue), "нет джингла «%s»" % cue)
		check(Jukebox.play_cue(cue), "джингл «%s» не загрузился" % cue)


## По пять мелодий на каждый тип поляны. Меньше — и лента, которая по замыслу
## бесконечна, начинает повторяться на слух через десяток экранов.
func _test_every_glade_type_has_a_pool() -> void:
	print("У каждого типа поляны пул из пяти мелодий")
	for type: int in Glade.TYPE_KEYS:
		var key: String = Glade.TYPE_KEYS[type]
		var count := Jukebox.glade_variants(key)
		check_eq(count, GLADE_POOL_SIZE, "пул поляны «%s»" % key)
		check(Jukebox.play_glade(key), "мелодия поляны «%s» не загрузилась" % key)


## Экран может забыть позвать музыку — выглядеть это будет как рабочий экран,
## просто молчащий. Поэтому подключение проверяется по коду экрана.
func _test_every_screen_is_wired() -> void:
	print("Каждый экран включает свою мелодию")
	for path: String in WIRING:
		var screen: String = WIRING[path]
		check(FileAccess.file_exists(path), "нет файла экрана %s" % path)
		var source := FileAccess.get_file_as_string(path)
		check(source.contains('Jukebox.play_screen("%s")' % screen),
			"%s не включает мелодию «%s»" % [path.get_file(), screen])

	# Лес живёт по своим правилам: там не одна мелодия, а пул по типу поляны
	var feed := FileAccess.get_file_as_string("res://scenes/run/run_feed.gd")
	check(feed.contains("Jukebox.play_glade("),
		"лента леса не включает мелодию поляны")


## В бою играет чарт, и фоновая музыка обязана замолчать: иначе под неё
## придётся попадать в такт вместе с боевой, а это каша.
func _test_forest_and_battle_do_not_overlap() -> void:
	print("Бой глушит фоновую музыку")
	var feed := FileAccess.get_file_as_string("res://scenes/run/run_feed.gd")

	var battle_at := feed.find("func _start_battle(")
	check(battle_at >= 0, "не нашёлся вход в бой")
	var body := feed.substr(battle_at, 700)
	check(body.contains("Jukebox.stop()"),
		"перед боем фоновая музыка не выключается")

	# И исход боя обязан быть слышен
	check(feed.contains('Jukebox.play_cue("victory" if won else "defeat")'),
		"исход боя не озвучен джинглом")
