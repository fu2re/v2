extends Node

## Звук и персональная калибровка задержки.
##
## Калибровка обязательна (GDD §10.4): разброс аудиозадержки на Android огромен,
## и без поправки игра кажется сломанной на половине устройств.

const SETTINGS_PATH := "user://settings.json"

## Персональная поправка в секундах. Положительная означает, что игрок слышит
## звук позже, чем игра считает, и время нужно сдвинуть назад.
var calibration_offset: float = 0.0
var is_calibrated: bool = false

var music_volume: float = 1.0
var sfx_volume: float = 1.0


func _ready() -> void:
	_ensure_buses()
	load_settings()


## Шины создаём кодом, чтобы проект собирался без бинарного default_bus_layout.
func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var index := AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func set_calibration(offset_seconds: float) -> void:
	calibration_offset = offset_seconds
	is_calibrated = true
	save_settings()


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось записать настройки: %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"calibration_offset": calibration_offset,
		"is_calibrated": is_calibrated,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
	}, "  "))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Настройки повреждены, используются значения по умолчанию")
		return
	var d: Dictionary = parsed
	calibration_offset = float(d.get("calibration_offset", 0.0))
	is_calibrated = bool(d.get("is_calibrated", false))
	music_volume = float(d.get("music_volume", 1.0))
	sfx_volume = float(d.get("sfx_volume", 1.0))
