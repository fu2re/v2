class_name GearData
extends Resource

## Снаряжение.
##
## Все боевые статы висят на гуардиане (GDD §9). У героя — только косметика,
## и это не мелочь: всё, что продаётся за реальные деньги, надевается
## на героя и потому физически не может быть pay-to-win.

enum Slot { BELT, CLOAK, HEADWEAR }

const SLOT_NAMES := {
	Slot.BELT: "Пояс",
	Slot.CLOAK: "Плащ",
	Slot.HEADWEAR: "Головной убор",
}

## Насколько слот влияет на бой, для подсказки игроку.
const SLOT_HINTS := {
	Slot.BELT: "Шире окно попадания",
	Slot.CLOAK: "Сильнее удар",
	Slot.HEADWEAR: "Больше здоровья и крепче щит",
}

@export var id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.BELT
@export var rarity: MonsterData.Rarity = MonsterData.Rarity.COMMON

## Числа предмета — из data/gear.json (накатывает Registry). Значения здесь —
## лишь дефолты на случай дырки в таблице; правь JSON, а не .tres.

## Множитель окон тайминга. 1.2 означает окна на 20% шире — прощает промахи.
@export var window_scale: float = 1.0
## Прибавка к урону по Настрою.
@export var power_bonus: float = 0.0
## Прибавка к максимальному здоровью.
@export var health_bonus: int = 0
## Насколько слабее бьёт пропущенная атака. 0.25 — на четверть слабее.
@export var shield_reduction: float = 0.0
## Цена у торговца в серебре. Единственный источник цены снаряжения:
## по ней же реестр сортирует пул для сундуков и третей витрины.
@export var price: int = 40

## Картинка предмета. Ребёнок 7 лет узнаёт вещь по виду быстрее, чем
## прочитает её название, поэтому список без картинок для него —
## сплошная стена букв (GDD §2.3).
@export var sprite_path: String = ""

var _sprite: Texture2D = null


static func slot_name(s: Slot) -> String:
	return SLOT_NAMES.get(s, "?")


## Картинка предмета. Путь по умолчанию собирается из id: девять файлов
## уже лежат в `art/gear/` под своими именами, и прописывать их руками
## в девяти .tres значило бы девять шансов опечататься.
func sprite() -> Texture2D:
	if _sprite != null:
		return _sprite
	var path := sprite_path if not sprite_path.is_empty() \
		else "res://art/gear/%s.png" % id
	if ResourceLoader.exists(path):
		_sprite = load(path) as Texture2D
	return _sprite


static func slot_hint(s: Slot) -> String:
	return SLOT_HINTS.get(s, "")


## Короткое описание эффекта — то, что видит игрок вместо голых чисел.
func effect_text() -> String:
	var parts: Array[String] = []
	if window_scale > 1.0:
		parts.append("окно +%d%%" % int(round((window_scale - 1.0) * 100.0)))
	if power_bonus > 0.0:
		parts.append("удар +%.1f" % power_bonus)
	if health_bonus > 0:
		parts.append("Здоровье +%d" % health_bonus)
	if shield_reduction > 0.0:
		parts.append("защита +%d%%" % int(round(shield_reduction * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "без эффекта"
