extends TestHarness

## Ротация фонов леса.
##
## Проверять красоту картинки тест не умеет, но всю механику вокруг неё —
## умеет, и именно она ломается молча: каталог переименовали, мешок отдаёт
## один и тот же фон, костёр потерял свой огонь. На экране это выглядит как
## «фон не сменился», и заметить это в отладке трудно — кажется, что показалось.

## Сколько фонов обязано быть в лесу. Число зашито намеренно: пропажу
## половины каталога тест должен назвать провалом, а не молча смириться.
const EXPECTED := 20

## Поляны, у которых фон сам является содержанием, — они из ротации исключены.
const FIXED_ART := {
	Glade.Type.CAMPFIRE: "res://art/glade/glade_campfire.png",
	Glade.Type.ENCOUNTER: "res://art/glade/glade_encounter.png",
}


func run_tests() -> void:
	_test_catalogue_is_complete()
	_test_every_background_loads()
	_test_bag_shows_all_before_repeating()
	_test_never_repeats_twice_in_a_row()
	_test_fixed_glades_keep_their_art()
	_test_feed_uses_rotation()


func _test_catalogue_is_complete() -> void:
	print("Фоны леса на месте")
	check_eq(ForestScenery.count(), EXPECTED, "число фонов леса")


## Каждый путь обязан вести к настоящей картинке. `ResourceLoader.exists`,
## а не `FileAccess`: в собранной игре png лежат как .import/.remap.
func _test_every_background_loads() -> void:
	print("Каждый фон загружается")
	for path: String in ForestScenery.all_paths():
		check(ResourceLoader.exists(path), "нет фона %s" % path)
		var texture := load(path) as Texture2D
		check(texture != null, "не грузится фон %s" % path)


## Ровно то, ради чего мешок и заведён: за двадцать показов игрок видит
## все двадцать мест, а не десять дважды.
func _test_bag_shows_all_before_repeating() -> void:
	print("Мешок показывает все фоны до повтора")
	ForestScenery.reset()

	var seen: Dictionary = {}
	for i in ForestScenery.count():
		var path := ForestScenery.next_path()
		check(not seen.has(path), "фон %s повторился на %d-м показе" % [path, i + 1])
		seen[path] = true
	check_eq(seen.size(), EXPECTED, "разных фонов за круг")


## Стык мешков — единственное место, где повтор подряд возможен по построению.
## Прогоняем несколько кругов подряд: одного круга мало, стык проверяется
## только вторым.
func _test_never_repeats_twice_in_a_row() -> void:
	print("Фон не повторяется дважды подряд")
	ForestScenery.reset()

	var previous := ""
	for i in ForestScenery.count() * 5:
		var path := ForestScenery.next_path()
		check(path != previous,
			"фон %s показан дважды подряд на %d-м показе" % [path, i + 1])
		previous = path


## Костёр и торговец из ротации исключены: на их фоне нарисовано то,
## ради чего игрок остановился.
func _test_fixed_glades_keep_their_art() -> void:
	print("У костра и встречи фон остаётся своим")
	var rotation := ForestScenery.all_paths()
	for type: int in FIXED_ART:
		var path: String = FIXED_ART[type]
		check(ResourceLoader.exists(path), "нет фона %s" % path)
		check(not rotation.has(path), "фон %s попал в ротацию" % path)

	var feed := FileAccess.get_file_as_string("res://scenes/run/run_feed.gd")
	for type: int in FIXED_ART:
		check(feed.contains(FIXED_ART[type]),
			"лента не показывает %s" % FIXED_ART[type])


## Лента обязана брать фон из ротации, а не из зашитого пути. Проверяется
## по коду: сцена, показывающая один и тот же фон, поднимается как рабочая.
func _test_feed_uses_rotation() -> void:
	print("Лента берёт фон из ротации")
	var feed := FileAccess.get_file_as_string("res://scenes/run/run_feed.gd")
	check(feed.contains("ForestScenery.next_path()"),
		"лента не вращает фоны леса")

	var intro := FileAccess.get_file_as_string("res://scenes/intro/intro.gd")
	check(intro.contains("ForestScenery.next_path()"),
		"интро не вращает фон леса")
