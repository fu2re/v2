class_name CosmeticData
extends Resource

## Косметика — единственное, что продаётся за реальные деньги.
##
## У неё НЕТ ни одного поля, влияющего на геймплей, и это сделано намеренно
## на уровне структуры данных, а не соглашения. Полей просто нет — значит
## pay-to-win невозможен даже по ошибке.
##
## Микробафы героя из GDD §9.2 живут на GearData и покупаются за Семечки:
## смешивать «купил за деньги» и «даёт преимущество» в игре для детей нельзя
## даже на пять процентов.

enum Slot { OUTFIT, HAT, TOOL, PLOT_SKIN, NOTE_FX, EMOTE }

const SLOT_NAMES := {
	Slot.OUTFIT: "Наряд",
	Slot.HAT: "Головной убор",
	Slot.TOOL: "Инструмент",
	Slot.PLOT_SKIN: "Вид грядки",
	Slot.NOTE_FX: "Эффект нот",
	Slot.EMOTE: "Танцевальное движение",
}

@export var id: String = ""
@export var display_name: String = ""
@export var slot: Slot = Slot.OUTFIT
@export var rarity: MonsterData.Rarity = MonsterData.Rarity.COMMON

## Цена прямой покупки в Аккордах.
##
## ОБЯЗАТЕЛЬНА и всегда больше нуля, даже для предметов из сундуков.
## Это регуляторное требование (GDD §12.3): в Бельгии и Нидерландах лутбоксы
## запрещены, и там весь их состав обязан продаваться напрямую. Предмет
## без прямой цены сделал бы игру непубликуемой в этих странах.
@export var price_chords: int = 100

## Появляется ли в сундуках. На доступность прямой покупки не влияет.
@export var in_crates: bool = true

@export var sprite_path: String = ""


static func slot_name(s: Slot) -> String:
	return SLOT_NAMES.get(s, "?")
