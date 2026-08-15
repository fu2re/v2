extends Node2D

## Выбор персонажа перед началом игры.
##
## Ни одного слова: две крупные фигуры и палец. Это первый экран, который
## видит ребёнок, и он обязан читаться без чтения (GDD §2.3). Спрайты
## сами говорят, из чего выбирают.
##
## Спрашивается ровно один раз: дальше выбор живёт в сейве.

const BOY := "boy"
const GIRL := "girl"

@onready var _boy_button: Button = $BoyButton
@onready var _girl_button: Button = $GirlButton
@onready var _boy_art: Sprite2D = $BoyArt
@onready var _girl_art: Sprite2D = $GirlArt


func _ready() -> void:
	# Кнопки прозрачные: нажимается сам персонаж, а не прямоугольник рядом
	for button in [_boy_button, _girl_button]:
		button.flat = true
		button.text = ""

	_boy_art.texture = _sprite_for(BOY)
	_girl_art.texture = _sprite_for(GIRL)

	_boy_button.pressed.connect(_choose.bind(BOY))
	_girl_button.pressed.connect(_choose.bind(GIRL))

	_breathe(_boy_art, 0.0)
	_breathe(_girl_art, 0.35)


func _sprite_for(gender: String) -> Texture2D:
	var path: String = GameState.HERO_SPRITES.get(gender, GameState.HERO_FALLBACK)
	if not ResourceLoader.exists(path):
		path = GameState.HERO_FALLBACK
	return load(path) as Texture2D


## Оба покачиваются в разной фазе: живое привлекает внимание, а разная
## фаза не даёт им слиться в одну мигающую пару.
func _breathe(sprite: Sprite2D, delay: float) -> void:
	var tween := create_tween().set_loops()
	tween.tween_interval(delay)
	tween.tween_property(sprite, "scale", Vector2(4.2, 4.2), 0.7)
	tween.tween_property(sprite, "scale", Vector2(4.0, 4.0), 0.7)


func _choose(gender: String) -> void:
	GameState.set_hero_gender(gender)
	SaveManager.save_if_dirty()
	get_tree().change_scene_to_file("res://scenes/intro/Intro.tscn")
