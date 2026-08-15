class_name ForestScenery
extends RefCounted

## Фоны леса и порядок их показа.
##
## Лента по замыслу бесконечна, и пока фон был один на тип поляны, лес
## выглядел одним и тем же местом, мимо которого игрок ходит кругами.
## Двадцать картинок это чинят — но только при честной ротации: случайный
## выбор из двадцати выдаёт повтор подряд примерно каждый двадцатый раз,
## а повтор подряд читается не как случайность, а как «фон не сменился».
##
## Поэтому мешок, а не бросок кубика: все двадцать показываются по разу
## в перемешанном порядке, и лишь потом мешок набирается заново. Плюс
## запрет на стык — первая картинка нового мешка не повторяет последнюю
## из старого.
##
## Статический класс, а не автозагрузчик: так ротацию видно из headless-теста
## без поднятия сцены (тот же приём, что у `Registry` и `ChartSelect`).

const DIR := "res://art/forest"

## Отсортированный список найденных фонов. Сортировка не косметика:
## порядок обхода каталога не гарантирован, а тест обязан быть повторяемым.
static var _paths: PackedStringArray = PackedStringArray()
static var _scanned := false

## Что осталось в мешке. Пустеет по мере показа.
static var _bag: PackedStringArray = PackedStringArray()
static var _last: String = ""

static var _rng: RandomNumberGenerator = null


static func ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true

	var dir := DirAccess.open(DIR)
	if dir == null:
		push_warning("Каталог фонов леса не найден: %s" % DIR)
		return

	# Рядом с каждым png лежит его .import, и оба приходят из get_files();
	# без отсева каждый фон попадает в мешок дважды
	var seen: Dictionary = {}
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
		if not clean.ends_with(".png") or seen.has(clean):
			continue
		seen[clean] = true
		_paths.append("%s/%s" % [DIR, clean])
	_paths.sort()


## Следующий фон. Пустая строка — фонов нет вовсе, зовущий решает сам,
## что показать вместо.
static func next_path() -> String:
	ensure_scanned()
	if _paths.is_empty():
		return ""
	if _paths.size() == 1:
		return _paths[0]

	if _bag.is_empty():
		_refill()

	var path := _bag[_bag.size() - 1]
	_bag.resize(_bag.size() - 1)
	_last = path
	return path


static func _refill() -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()

	_bag = _paths.duplicate()
	# Тасование Фишера — Йетса: PackedStringArray не умеет shuffle()
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = tmp

	# Берём с конца, поэтому «следующей» станет последняя. Если она же
	# показывалась только что, меняем её с началом — иначе на стыке мешков
	# один фон встал бы дважды подряд
	if _bag.size() > 1 and _bag[_bag.size() - 1] == _last:
		var tmp := _bag[0]
		_bag[0] = _bag[_bag.size() - 1]
		_bag[_bag.size() - 1] = tmp


## Сколько всего фонов нашлось.
static func count() -> int:
	ensure_scanned()
	return _paths.size()


static func all_paths() -> PackedStringArray:
	ensure_scanned()
	return _paths.duplicate()


## Начать ротацию заново. Нужно тестам: иначе порядок зависит от того,
## что успели показать раньше в том же процессе.
static func reset() -> void:
	_bag = PackedStringArray()
	_last = ""
