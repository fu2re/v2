class_name GearData
extends Resource

## Снаряжение.
##
## Все боевые статы висят на гуардиане (GDD §9). У героя — только косметика
## и микробафы, и это не мелочь: всё, что продаётся за реальные деньги,
## надевается на героя и потому физически не может быть pay-to-win.

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

## Множитель окон тайминга. 1.2 означает окна на 20% шире — прощает промахи.
@export var window_scale: float = 1.0
## Прибавка к урону по Настрою.
@export var power_bonus: float = 0.0
## Прибавка к максимальному здоровью.
@export var health_bonus: int = 0
## Насколько слабее бьёт пропущенная атака. 0.25 — на четверть слабее.
@export var shield_reduction: float = 0.0
## Цена у торговца в семечках.
@export var price: int = 40


static func slot_name(s: Slot) -> String:
	return SLOT_NAMES.get(s, "?")


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
