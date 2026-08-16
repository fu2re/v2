class_name FruitData
extends Resource

## Фрукт с грядки. Валюта приручения: правильный фрукт сокращает путь
## к монстру с десяти встреч до трёх (GDD §6).

enum Quality { PLAIN, JUICY, PERFECT }

## Всё, что фрукт даёт игре, задано ТИРОМ семечка и живёт в data/fruits.json.
##
## В коде не осталось ни одного числа: время роста, дружба, лечение и бафы
## правятся дизайнером в таблице, а не программистом в константах. Так уже
## пришлось чинить один раз — числа в коде и в таблице разъехались молча.


static func tier_friendship_scale(tier: int) -> float:
	return Balance.fruit_friendship_scale(tier)

@export var id: String = ""
@export var display_name: String = ""
@export var tier: int = 0
@export var sprite_path: String = ""

var _sprite: Texture2D = null


static func quality_name(q: Quality) -> String:
	return ["Обычный", "Сочный", "Идеальный"][q]


func grow_seconds() -> int:
	return Balance.fruit_grow_seconds(tier)


func heal() -> int:
	return Balance.fruit_heal(tier)


func buff() -> Dictionary:
	return Balance.fruit_buff(tier)


func sprite() -> Texture2D:
	if _sprite == null and not sprite_path.is_empty():
		_sprite = load(sprite_path) as Texture2D
	return _sprite
