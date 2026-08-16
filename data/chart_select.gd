class_name ChartSelect
extends RefCounted

## Какой трек звучит в бою.
##
## Трек определяется тремя вещами: стихией монстра (аранжировка), его мотивом
## (мелодия) и грейдом встреченного экземпляра (темп). Чем реже монстр, тем
## быстрее ремикс — сложность боя это НЕ подкрученные числа, а другая музыка
## (GDD §10.1.1).
##
## Имена файлов несут ещё и BPM (`disco_iskra_common_120.json`), потому что
## темп у каждой стихии свой. Угадывать его в коде значило бы держать третью
## копию таблицы темпов, поэтому каталог сканируется один раз и превращается
## в индекс.

const CHARTS_DIR := "res://charts"

## Ключи стихий в именах файлов. Порядок совпадает с MonsterData.Genre.
const GENRE_KEYS := ["rock", "disco", "folk", "electro", "latin"]

## Запасной чарт: играется, если для монстра трека почему-то нет.
## Молча падать в бою нельзя — игрок останется перед пустым экраном.
const FALLBACK_ID := "demo_disco"
const FALLBACK_DIFFICULTY := "normal"

## "<жанр>_<мотив>_<грейд>" -> имя файла без расширения.
static var _index: Dictionary = {}
static var _scanned := false


static func ensure_scanned() -> void:
	if _scanned:
		return
	_index.clear()

	var dir := DirAccess.open(CHARTS_DIR)
	if dir == null:
		push_error("Каталог чартов не найден: %s" % CHARTS_DIR)
		_scanned = true
		return

	for file_name in dir.get_files():
		# В экспортированной сборке ресурсы лежат как .remap
		var clean := file_name.trim_suffix(".remap")
		if not clean.ends_with(".json"):
			continue
		var stem := clean.trim_suffix(".json")
		var parts := stem.split("_")
		# <жанр>_<мотив>_<грейд>_<bpm>: легаси-чарты короче и в индекс не идут
		if parts.size() != 4:
			continue
		var key := "%s_%s_%s" % [parts[0], parts[1], parts[2]]
		_index[key] = stem
	_scanned = true


static func forget() -> void:
	_scanned = false
	_index.clear()


static func genre_key(genre: int) -> String:
	return GENRE_KEYS[clampi(genre, 0, GENRE_KEYS.size() - 1)]


## Имя файла чарта без расширения, или пустая строка.
static func chart_stem(species: MonsterData, grade: int) -> String:
	if species == null or species.motif_id.is_empty():
		return ""
	ensure_scanned()

	var base := "%s_%s" % [genre_key(species.genre), species.motif_id]

	# Точное совпадение по грейду
	var exact: String = _index.get("%s_%s" % [base, Balance.grade_key(grade)], "")
	if not exact.is_empty():
		return exact

	# Нет трека нужного темпа — берём ближайший снизу. Бой останется играбельным,
	# просто окажется спокойнее, чем задумано
	for lower in range(grade - 1, -1, -1):
		var found: String = _index.get("%s_%s" % [base, Balance.grade_key(lower)], "")
		if not found.is_empty():
			return found
	return ""


## Загрузить чарт для встречи. Никогда не возвращает null, если существует
## хотя бы запасной трек: бой без музыки — это сломанный бой.
static func load_for(species: MonsterData, grade: int) -> ChartData:
	var stem := chart_stem(species, grade)
	if stem.is_empty():
		push_warning("Нет чарта для %s (грейд %s), беру запасной"
			% [species.id if species != null else "?", Balance.grade_key(grade)])
		return ChartLoader.load_by_id(FALLBACK_ID, FALLBACK_DIFFICULTY)

	var chart := ChartLoader.load_chart("%s/%s.json" % [CHARTS_DIR, stem])
	if chart == null:
		return ChartLoader.load_by_id(FALLBACK_ID, FALLBACK_DIFFICULTY)
	return chart
