class_name Glade
extends RefCounted

## Одна поляна в ленте леса.

enum Type { BATTLE, WILD_BUSH, MERCHANT, CAMPFIRE, EVENT }

## Доли типов полян (GDD §8.2). Бой доминирует: лента должна ощущаться
## как поток боёв, а не как меню с редкими стычками.
const WEIGHTS := {
	Type.BATTLE: 65,
	Type.WILD_BUSH: 12,
	Type.MERCHANT: 10,
	Type.CAMPFIRE: 8,
	Type.EVENT: 5,
}

const TYPE_NAMES := {
	Type.BATTLE: "Бой",
	Type.WILD_BUSH: "Дикий куст",
	Type.MERCHANT: "Бродячий торговец",
	Type.CAMPFIRE: "Костёр",
	Type.EVENT: "Событие",
}

var type: Type = Type.BATTLE
var depth: int = 0
## Для боя: кого встретили.
var monster_id: String = ""
## Для куста: какое семя можно унести.
var fruit_id: String = ""
var silver_reward: int = 0


func type_name() -> String:
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
