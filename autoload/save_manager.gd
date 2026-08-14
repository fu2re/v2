extends Node

## Сохранение прогресса.
##
## Автосейв между полянами, а не в конце забега: игру на телефоне закрывают
## посреди сессии постоянно, и потерянный час прогресса ребёнок не прощает.

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.backup.json"

var _dirty := false


func _ready() -> void:
	load_game()


func mark_dirty() -> void:
	_dirty = true


func save_game() -> void:
	var payload := JSON.stringify(GameState.to_dict(), "  ")

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
	GameState.from_dict(parsed)
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	for path in [SAVE_PATH, BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameState.reset()


func _notification(what: int) -> void:
	# На телефоне приложение сворачивают, а не закрывают. Этот момент —
	# последняя гарантированная возможность записать прогресс
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_if_dirty()
