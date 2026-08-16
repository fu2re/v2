extends Node

## Сохранение прогресса.
##
## Автосейв между полянами, а не в конце забега: игру на телефоне закрывают
## посреди сессии постоянно, и потерянный час прогресса ребёнок не прощает.

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.backup.json"

var _dirty := false

## Запрет записи. Тесты гоняют настоящие RunManager и FarmState, и без этого
## флага прогон тестов затирал бы сохранение игрока.
var writes_disabled := false


## Стартовый набор новой игры.
##
## Только семена: без них ферма — пустой экран. Гуардиана здесь нет
## намеренно, первого игрок добывает сам в интро (GDD §15.5).
const STARTER_SEEDS := {"drum_berry": 3, "echo_pear": 2}


func _ready() -> void:
	if not load_game():
		_grant_new_game()


func _grant_new_game() -> void:
	for fruit_id: String in STARTER_SEEDS:
		FarmState.add_seed(fruit_id, STARTER_SEEDS[fruit_id])


## Перевести подсистему в тестовый режим: ничего не читать и не писать.
func enter_test_mode() -> void:
	writes_disabled = true


func mark_dirty() -> void:
	_dirty = true


## Сейв собирается из всех подсистем в один файл: частичные сейвы
## рассинхронизируются между собой при обрыве записи.
func _collect() -> Dictionary:
	var data := GameState.to_dict()
	data["farm"] = FarmState.to_dict()
	data["shop"] = ShopState.to_dict()
	return data


func save_game() -> void:
	if writes_disabled:
		_dirty = false
		return

	var payload := JSON.stringify(_collect(), "  ")

	# Старый сейв уводим в резерв ДО записи нового: если запись оборвётся
	# на середине, у игрока останется рабочий предыдущий
	if FileAccess.file_exists(SAVE_PATH):
		var previous := FileAccess.get_file_as_string(SAVE_PATH)
		if not previous.is_empty():
			var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
			if backup != null:
				backup.store_string(previous)

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось сохранить: %s" % SAVE_PATH)
		return
	file.store_string(payload)
	_dirty = false


func save_if_dirty() -> void:
	if _dirty:
		save_game()


func load_game() -> bool:
	if _load_from(SAVE_PATH):
		return true
	if FileAccess.file_exists(BACKUP_PATH):
		push_warning("Основной сейв не прочитался, беру резервный")
		return _load_from(BACKUP_PATH)
	return false


func _load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Сейв повреждён: %s" % path)
		return false
	var data: Dictionary = parsed

	# Версия сверяется ДО применения: несовместимый сейв не должен доехать
	# до подсистем даже частично, иначе половина состояния окажется новой,
	# а половина — старой, и разобраться в этом будет уже нельзя.
	#
	# Миграция не пишется намеренно: игра в разработке, живых игроков нет,
	# а поддержка мостов между схемами стоит дороже, чем новый старт.
	var version := int(data.get("version", 0))
	if version != GameState.SAVE_VERSION:
		# Файл не удаляем: `_ready` автозагрузчика отрабатывает раньше, чем
		# тест успевает включить запрет записи, и удаление здесь стирало бы
		# сейв разработчика при каждом прогоне тестов. Старый файл просто
		# не читается и будет перезаписан первым же сохранением.
		push_warning("Сейв версии %d несовместим с текущей %d — начинаем заново"
			% [version, GameState.SAVE_VERSION])
		return false

	GameState.from_dict(data)
	if data.has("farm"):
		FarmState.from_dict(data["farm"])
	if data.has("shop"):
		ShopState.from_dict(data["shop"])
	return true


func _notification(what: int) -> void:
	# На телефоне приложение сворачивают, а не закрывают. Этот момент —
	# последняя гарантированная возможность записать прогресс
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_if_dirty()
