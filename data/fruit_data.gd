class_name FruitData
extends Resource

## Фрукт с грядки. Валюта приручения: правильный фрукт сокращает путь
## к монстру с десяти встреч до трёх (GDD §6).

enum Quality { PLAIN, JUICY, PERFECT }

## Качество как множитель прибавки дружбы. Это награда за танец растению —
## ребёнок танцует, потому что приятно, взрослый выжимает качество.
const QUALITY_MULTIPLIER := {
	Quality.PLAIN: 1.0,
	Quality.JUICY: 1.3,
	Quality.PERFECT: 1.6,
}

## Время роста в секундах по тиру семени (GDD §7.1).
const GROW_TIME := {
	0: 600,     # обычное, 10 мин
	1: 2700,    # необычное, 45 мин
	2: 10800,   # редкое, 3 ч
	3: 28800,   # эпическое, 8 ч
}

@export var id: String = ""
@export var display_name: String = ""
@export var tier: int = 0
@export var sprite_path: String = ""

var _sprite: Texture2D = null


static func quality_multiplier(q: Quality) -> float:
	return QUALITY_MULTIPLIER.get(q, 1.0)


static func quality_name(q: Quality) -> String:
	return ["Обычный", "Сочный", "Идеальный"][q]


func grow_seconds() -> int:
	return GROW_TIME.get(tier, 600)


func sprite() -> Texture2D:
	if _sprite == null and not sprite_path.is_empty():
		_sprite = load(sprite_path) as Texture2D
	return _sprite
