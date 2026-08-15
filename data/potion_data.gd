class_name PotionData
extends Resource

## Зелье: лечение в бою (GDD §4.2.3).
##
## Морсы и отвары, никакой алхимии — игра для детей 7+. Выпить его можно
## ТОЛЬКО через ноту-зелье, а не из меню: лечение тоже происходит в ритме,
## и пауза посреди боя не спасает от промахов.

@export var id: String = ""
@export var display_name: String = ""
## Показывается игроку вместо голых чисел.
@export var description: String = ""
@export var rarity: MonsterData.Rarity = MonsterData.Rarity.COMMON

## Сколько здоровья возвращает глоток.
@export var restore_health: int = 15
## Цена у торговца в серебре. Зелья — часть игрового контура, за реальные
## деньги не продаются никогда (GDD §12).
@export var price: int = 30

@export var sprite_path: String = ""

var _sprite: Texture2D = null


func sprite() -> Texture2D:
	if _sprite == null and not sprite_path.is_empty():
		_sprite = load(sprite_path) as Texture2D
	return _sprite


## Короткое описание эффекта — то, что видит игрок в лавке и в сумке.
func effect_text() -> String:
	return "+%d здоровья" % restore_health
