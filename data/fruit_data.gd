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
	1: 1800,    # необычное, 30 мин
	2: 7200,    # редкое, 2 ч
	3: 28800,   # эпическое, 8 ч
}

## Во сколько раз плод тира щедрее самого простого (GDD §7.2).
##
## Считается от ТИРА, а не от качества, и это исправление настоящей поломки:
## качеств три, а тиров четыре, поэтому редкий инжир и необычная сливка
## давали ОДИНАКОВУЮ дружбу — при том что инжир рос вчетверо дольше и стоил
## вдвое дороже. Тир 2 был предметом, который незачем сажать никогда.
##
## Разброс ×4 против разброса времени ×48 — так и задумано. Ожидание в ферме
## покупается не эффективностью за час, а размером одного урожая: за ночь
## никто не соберёт десятиминутную грядку сорок восемь раз. Верхний плод
## закрывает обычную шкалу дружбы В ОДИНОЧКУ — «посадил перед сном, проснулся
## с новым другом» и есть то, ради чего вообще ждут.
const TIER_FRIENDSHIP := {
	0: 1.0,
	1: 1.7,
	2: 2.7,
	3: 4.0,
}


static func tier_friendship_scale(tier: int) -> float:
	return TIER_FRIENDSHIP.get(clampi(tier, 0, 3), 1.0)

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
