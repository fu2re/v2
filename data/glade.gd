class_name Glade
extends RefCounted

## Одна поляна в ленте леса.

enum Type { BATTLE, WILD_BUSH, CAMPFIRE, ENCOUNTER }

## Что именно попалось на поляне-встрече (GDD §8.2.1).
## Загадка описана в дизайне, но не спроектирована — её доля пока нулевая.
enum Encounter { MERCHANT, LOOT_BUSH, GRANNY, RIDDLE }

## Ключи в таблице `drop_tables.json`. Веса читаются оттуда, а не отсюда:
## доли полян — настройка дизайнера, а не константа кода.
const TYPE_KEYS := {
	Type.BATTLE: "battle",
	Type.WILD_BUSH: "wild_bush",
	Type.CAMPFIRE: "campfire",
	Type.ENCOUNTER: "encounter",
}

const ENCOUNTER_KEYS := {
	Encounter.MERCHANT: "merchant",
	Encounter.LOOT_BUSH: "loot_bush",
	Encounter.GRANNY: "granny",
	Encounter.RIDDLE: "riddle",
}

const TYPE_NAMES := {
	Type.BATTLE: "Бой",
	Type.WILD_BUSH: "Дикий куст",
	Type.CAMPFIRE: "Костёр",
	Type.ENCOUNTER: "Встреча",
}

const ENCOUNTER_NAMES := {
	Encounter.MERCHANT: "Бродячий торговец",
	Encounter.LOOT_BUSH: "Куст с гостинцами",
	Encounter.GRANNY: "Бабушка у тропинки",
	Encounter.RIDDLE: "Загадка",
}

var type: Type = Type.BATTLE
var depth: int = 0
## Для боя: кого встретили.
var monster_id: String = ""
## Грейд встреченного экземпляра. Роллится на поляне, а не берётся у вида
## (GDD §6.3): один и тот же Ростик бывает и обычным, и легендарным.
var grade: int = MonsterData.Rarity.COMMON
## Для куста: какое семя можно унести.
var fruit_id: String = ""
var silver_reward: int = 0
## Для встречи: кто попался.
var encounter: int = Encounter.MERCHANT


func type_name() -> String:
	if type == Type.ENCOUNTER:
		return ENCOUNTER_NAMES.get(encounter, "Встреча")
	return TYPE_NAMES.get(type, "?")


## Что показать на карточке до свайпа. Любимый фрукт монстра виден заранее —
## игрок решает, стоит ли останавливаться (GDD §6.2).
func headline() -> String:
	match type:
		Type.BATTLE:
			var m := Registry.monster(monster_id)
			return m.display_name if m != null else "Неизвестный монстр"
		Type.WILD_BUSH:
			var f := Registry.fruit(fruit_id)
			return "Дикий куст: %s" % (f.display_name if f != null else fruit_id)
		_:
			return type_name()
