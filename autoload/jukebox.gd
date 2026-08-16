extends Node

## Неигровая музыка: экраны усадьбы, поляны, джинглы событий.
##
## Отдельно от `Conductor` намеренно. Conductor — это ЧАСЫ боя: его позиция
## задаёт время нот, и трогать его ради фоновой музыки нельзя. Здесь всё
## наоборот: точность не нужна, зато нужны петля, плавная смена и то,
## чтобы фон замолкал, когда начинается бой.
##
## Файлы лежат с суффиксом темпа в имени (`ui_lobby_96.ogg`), поэтому пути
## не собираются строкой, а один раз сканируются в индекс — как чарты
## в `ChartSelect`.

const UI_DIR := "res://music/ui"
const CUE_DIR := "res://music/cue"
const GLADE_DIR := "res://music/glade"

## Сколько длится перекрёстное затухание при смене экрана.
##
## Обрыв на полуноте слышен и читается как сбой, поэтому мелодия уходит
## плавно. Короткое: игрок не должен ждать музыку, переходя между экранами.
const FADE_SECONDS := 0.45

## Насколько тише фон обычного трека. Под эту музыку не играют — она
## не должна перебивать ни речь на экране, ни собственные мысли игрока.
const AMBIENT_DB := -8.0
const STINGER_DB := -4.0

## Индексы: короткое имя -> путь. Заполняются один раз при старте.
var _screens: Dictionary = {}
var _cues: Dictionary = {}
## Тип поляны -> массив путей. По пять мелодий на каждый.
var _glades: Dictionary = {}

var _music: AudioStreamPlayer = null
var _stinger: AudioStreamPlayer = null
## Что играет сейчас — чтобы не перезапускать ту же петлю при возврате
## на экран, с которого уходили.
var _current: String = ""

var _rng := RandomNumberGenerator.new()

## Мешки мелодий по типу поляны и последняя сыгранная в каждом.
var _bags: Dictionary = {}
var _last_glade: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_scan()

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = AMBIENT_DB
	add_child(_music)

	# Джингл звучит ПОВЕРХ фона, а не вместо: победа не должна обрывать
	# музыку поляны на полуслове
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "SFX"
	_stinger.volume_db = STINGER_DB
	add_child(_stinger)


## Разобрать каталоги в индексы.
##
## Имена несут темп (`ui_lobby_96.ogg`), а обращаемся мы по смыслу («lobby»),
## поэтому ключом становится середина имени. Сканируем один раз: обращение
## к файловой системе на каждую смену экрана обошлось бы в кадры.
func _scan() -> void:
	for path: String in _files_in(UI_DIR):
		var name := path.get_file().get_basename()
		# ui_lobby_96 -> lobby
		var parts := name.split("_")
		if parts.size() >= 3:
			_screens["_".join(parts.slice(1, parts.size() - 1))] = path

	for path: String in _files_in(CUE_DIR):
		var parts := path.get_file().get_basename().split("_")
		if parts.size() >= 3:
			_cues[parts[1]] = path

	for path: String in _files_in(GLADE_DIR):
		# glade_wild_bush_3_104 -> wild_bush
		var parts := path.get_file().get_basename().split("_")
		if parts.size() < 4:
			continue
		var key: String = "_".join(parts.slice(1, parts.size() - 2))
		if not _glades.has(key):
			_glades[key] = PackedStringArray()
		var list: PackedStringArray = _glades[key]
		list.append(path)
		list.sort()
		_glades[key] = list


func _files_in(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Каталог музыки не найден: %s" % dir_path)
		return out
	# Рядом с каждым ogg лежит его .import, и оба приходят из get_files().
	# Без отсева пул поляны удваивается — а тест на «пять мелодий» видит
	# десять и не понимает, откуда
	var seen: Dictionary = {}
	for file_name in dir.get_files():
		# В экспортированной сборке ogg лежат как .import/.remap
		var clean := file_name.trim_suffix(".remap").trim_suffix(".import")
		if not clean.ends_with(".ogg") or seen.has(clean):
			continue
		seen[clean] = true
		out.append("%s/%s" % [dir_path, clean])
	return out


# --- фоновая музыка -----------------------------------------------------------

## Включить петлю экрана. Повторный вызов с тем же именем ничего не делает:
## переходя туда-обратно, игрок должен слышать непрерывную музыку, а не
## её начало заново.
func play_screen(screen: String) -> bool:
	return _play_loop(screen, _screens.get(screen, ""))


## Мелодия поляны. Тип задаёт пул, а порядок — МЕШОК: все мелодии звучат
## по разу в перемешанном порядке, и лишь потом набираются заново.
##
## Не бросок кубика: случайный выбор из десяти выдаёт повтор подряд примерно
## каждый десятый раз, а повтор подряд игрок читает не как совпадение,
## а как «музыка не сменилась» — ровно та же причина, по которой мешком
## вращаются и фоны леса (§11.1.0).
func play_glade(kind: String) -> bool:
	if not _glades.has(kind):
		return false
	var pool: PackedStringArray = _glades[kind]
	if pool.is_empty():
		return false
	var path := _draw_from_bag(kind, pool)
	return _play_loop(path, path)


## Достать следующую мелодию из мешка этого типа, набрав его при нужде.
func _draw_from_bag(kind: String, pool: PackedStringArray) -> String:
	if pool.size() == 1:
		return pool[0]

	var bag: PackedStringArray = _bags.get(kind, PackedStringArray())
	if bag.is_empty():
		bag = pool.duplicate()
		# Тасование Фишера — Йетса: PackedStringArray не умеет shuffle()
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp := bag[i]
			bag[i] = bag[j]
			bag[j] = tmp
		# На стыке мешков повтор подряд запрещён отдельно
		var last: String = _last_glade.get(kind, "")
		if bag.size() > 1 and bag[bag.size() - 1] == last:
			var swap := bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = swap

	var path := bag[bag.size() - 1]
	bag.resize(bag.size() - 1)
	_bags[kind] = bag
	_last_glade[kind] = path
	return path


func _play_loop(key: String, path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	if key == _current and _music.playing:
		return true

	var stream := load(path) as AudioStream
	if stream == null:
		return false

	# Петля задаётся здесь, а не в импорте: .import-файлы генерируются
	# движком, и правку в них легко потерять при переимпорте
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	_current = key
	_fade_to(stream)
	return true


func _fade_to(stream: AudioStream) -> void:
	if not _music.playing:
		_music.stream = stream
		_music.volume_db = AMBIENT_DB
		_music.play()
		return

	# Уводим старую петлю в тишину, подменяем поток, возвращаем громкость
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -40.0, FADE_SECONDS * 0.5)
	tween.tween_callback(func():
		_music.stream = stream
		_music.play())
	tween.tween_property(_music, "volume_db", AMBIENT_DB, FADE_SECONDS * 0.5)


## Замолчать. Нужно бою: там своя музыка и свои часы (Conductor),
## и две дорожки разом превратились бы в кашу.
func stop() -> void:
	_current = ""
	if _music == null:
		return
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -40.0, FADE_SECONDS)
	tween.tween_callback(_music.stop)


# --- джинглы ------------------------------------------------------------------

## Короткое событие: вход в игру, победа, поражение.
##
## Звучит поверх фона и на своей шине: это не музыка, а знак, и глушить
## ради него петлю экрана незачем.
func play_cue(cue: String) -> bool:
	var path: String = _cues.get(cue, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var stream := load(path) as AudioStream
	if stream == null:
		return false
	# Джингл не зацикливается никогда: он обязан кончиться сам
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_stinger.stream = stream
	_stinger.play()
	return true


# --- справки для тестов и отладки ---------------------------------------------

func known_screens() -> Array:
	var out: Array = _screens.keys()
	out.sort()
	return out


func known_cues() -> Array:
	var out: Array = _cues.keys()
	out.sort()
	return out


func glade_variants(kind: String) -> int:
	if not _glades.has(kind):
		return 0
	var pool: PackedStringArray = _glades[kind]
	return pool.size()


func current_track() -> String:
	return _current
