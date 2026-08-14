extends Node

## Пройдено ли обучение.
##
## Отдельный автозагрузчик, а не поле в GameState, потому что обучение
## должно оставаться пройденным даже если игрок сбросит прогресс: заставлять
## взрослого проходить урок заново — раздражение без пользы.

const PATH := "user://onboarding.json"

var is_done: bool = false


func _ready() -> void:
	_load()


func mark_done() -> void:
	if is_done:
		return
	is_done = true
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось записать отметку обучения")
		return
	file.store_string(JSON.stringify({"done": true}))


func reset() -> void:
	is_done = false
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Куда идти при запуске игры.
func entry_scene() -> String:
	return "res://scenes/farm/Farm.tscn" if is_done \
		else "res://scenes/onboarding/Onboarding.tscn"


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	is_done = bool((parsed as Dictionary).get("done", false))
