extends TestHarness

## Сцены правятся в инспекторе, а не в коде (GDD §13.2.1).
##
## Правило легко нарушить незаметно: написать `Label.new()` быстрее, чем
## открыть редактор, и сцена молча превращается в пустой узел, у которого
## художнику нечего подвинуть. Компиляция довольна, игра работает, а fine
## tuning становится невозможен.
##
## Тест — храповик: список сцен, которым сборка кодом ещё позволена, задан
## явно и не должен расти. Новая сцена с раскладкой в коде провалит проверку;
## чтобы её добавить, придётся осознанно вписать её в список — а это уже
## разговор, а не случайность.

## Кому сборка кодом остаётся позволена — и почему.
##
## Оба случая прямо названы исключениями в §13.2.1. Держим их поимённо,
## чтобы список не расползался «по аналогии».
const CODE_BUILT_ALLOWED := {
	# Слой-подсказка поверх боя: рисует кольцо и палец в такт музыке,
	# позиции считаются от JudgeLine и меняются каждый кадр
	"res://scenes/onboarding/CoachOverlay.tscn": "кольцо и палец рисуются по времени",
	# Замер задержки: два узла, живёт вне игрового контура
	"res://scenes/calibration/Calibration.tscn": "служебный экран калибровки",
	# Мини-игра танца растению: разметка нот рисуется, а не расставляется
	"res://scenes/farm/PlantDance.tscn": "ноты фразы рисуются по чарту",
	# Логика запуска без единого видимого узла
	"res://scenes/Boot.tscn": "нет интерфейса вообще",
}

## Инструменты — не игра: их правят программисты, и редактируемость
## художником им не нужна.
const TOOL_PREFIX := "res://tools/"

## Сколько узлов считаем признаком собранной сцены. Один узел — это корень
## со скриптом и ничего больше, то есть раскладки в сцене нет.
const MIN_NODES := 2


func run_tests() -> void:
	_test_scenes_have_their_layout_in_the_scene()
	_test_allowlist_has_no_stale_entries()
	_test_baked_screens_do_not_build_ui_in_code()


func _scene_paths() -> PackedStringArray:
	var out := PackedStringArray()
	_collect("res://scenes", out)
	return out


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tscn"):
			out.append("%s/%s" % [dir_path, clean])
	for sub in dir.get_directories():
		_collect("%s/%s" % [dir_path, sub], out)


## Число узлов в .tscn. Читаем текстом: поднимать сцену ради подсчёта дорого,
## а у сцены боя ещё и запускается логика.
func _node_count(path: String) -> int:
	var source := FileAccess.get_file_as_string(path)
	var count := 0
	for line in source.split("\n"):
		if line.begins_with("[node "):
			count += 1
	return count


func _test_scenes_have_their_layout_in_the_scene() -> void:
	print("Раскладка лежит в сценах, а не в коде")
	var paths := _scene_paths()
	check(paths.size() >= 10, "сцены нашлись (%d)" % paths.size())

	for path: String in paths:
		if path.begins_with(TOOL_PREFIX) or CODE_BUILT_ALLOWED.has(path):
			continue
		check(_node_count(path) >= MIN_NODES,
			"%s собрана кодом: в сцене %d узел, в инспекторе править нечего" % [
				path.replace("res://", ""), _node_count(path)])


## Список исключений не должен переживать свои причины: сцена, которую уже
## перевели в редактор, обязана из него уйти — иначе он однажды разрешит
## то, что давно запрещено.
func _test_allowlist_has_no_stale_entries() -> void:
	print("Список исключений не устарел")
	for path: String in CODE_BUILT_ALLOWED:
		check(ResourceLoader.exists(path),
			"в списке исключений несуществующая сцена %s" % path)
		if not ResourceLoader.exists(path):
			continue
		check(_node_count(path) < MIN_NODES,
			"%s уже собрана в редакторе — убери её из списка исключений" % [
				path.replace("res://", "")])


## У переведённых экранов не должно остаться сборщика: оставленный `_build_ui`
## строит вторую копию поверх настоящей, и на экране двоится текст.
func _test_baked_screens_do_not_build_ui_in_code() -> void:
	print("У переведённых экранов не осталось сборщика")
	var scripts := {
		"res://scenes/farm/farm.gd": "_build_ui",
		"res://scenes/run/run_feed.gd": "_build_ui",
		"res://scenes/collection/collection.gd": "_build_ui",
		"res://scenes/shop/shop.gd": "_build_ui",
		"res://scenes/inventory/inventory.gd": "_build_ui",
		"res://scenes/battle/dance_battle.gd": "_build_stage",
		"res://scenes/battle/taming_screen.gd": "_build",
	}
	for path: String in scripts:
		var builder: String = scripts[path]
		check(FileAccess.file_exists(path), "нет скрипта %s" % path)
		if not FileAccess.file_exists(path):
			continue
		var source := FileAccess.get_file_as_string(path)
		check(not source.contains("func %s(" % builder),
			"%s всё ещё собирает интерфейс в %s()" % [path.get_file(), builder])
