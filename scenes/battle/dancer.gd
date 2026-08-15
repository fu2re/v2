class_name Dancer
extends Node2D

## Танцор на сцене боя: герой или его защитник.
##
## Двигается на каждую долю, отзывается на попадания и играет замах при
## атаке. Это единственное место, где игрок видит, что он тут не один
## и что снаряжение на защитнике не просто строчка в меню.

## Надетое рисуется поверх силуэта простыми фигурами.
##
## Настоящие спрайты появятся, когда будет арт-пайплайн; до тех пор важнее,
## чтобы смена пояса или шляпы БЫЛА ВИДНА — иначе собирать снаряжение
## незачем, оно ничем не отличается от строчки в таблице.
const GEAR_COLORS := {
	GearData.Slot.BELT: Color("BA9A6D"),
	GearData.Slot.CLOAK: Color("2E9BFF"),
	GearData.Slot.HEADWEAR: Color("FFD24D"),
}

var _sprite: Sprite2D = null
var _gear: Node2D = null
var _base_y: float = 0.0
var _worn: Dictionary = {}
var _bob_up := true


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(3, 3)
	add_child(_sprite)

	_gear = Node2D.new()
	_gear.draw.connect(_draw_gear)
	add_child(_gear)
	_base_y = position.y


## Показать существо и то, что на нём надето.
func setup(texture: Texture2D, worn: Dictionary = {}) -> void:
	_sprite.texture = texture
	_worn = worn
	_base_y = position.y
	_gear.queue_redraw()


## Покачивание на долю. Направление чередуется, чтобы читался именно танец,
## а не дрожание на месте.
func step() -> void:
	_bob_up = not _bob_up
	var lift := -22.0 if _bob_up else -8.0
	var tilt := 0.08 if _bob_up else -0.08
	var tween := create_tween()
	tween.tween_property(self, "position:y", _base_y + lift, 0.1)
	tween.parallel().tween_property(self, "rotation", tilt, 0.1)
	tween.tween_property(self, "position:y", _base_y, 0.12)
	tween.parallel().tween_property(self, "rotation", 0.0, 0.12)


## Отклик на обычное попадание — короткий кивок.
func nod() -> void:
	var tween := create_tween()
	tween.tween_property(_sprite, "scale", Vector2(3.3, 2.7), 0.06)
	tween.tween_property(_sprite, "scale", Vector2(3.0, 3.0), 0.12)


## Атака. Рывок вперёд и вспышка — движение обязано отличаться от кивка,
## иначе игрок не свяжет атакующую ноту с уроном.
func attack(landed: bool) -> void:
	var tween := create_tween()
	if landed:
		tween.tween_property(self, "position:x", position.x + 90.0, 0.09)
		tween.parallel().tween_property(_sprite, "modulate", Color("FFD24D"), 0.09)
		tween.tween_property(self, "position:x", position.x, 0.18)
		tween.parallel().tween_property(_sprite, "modulate", Color.WHITE, 0.18)
	else:
		# Замах вхолостую: движение есть, но вялое и без вспышки
		tween.tween_property(self, "position:x", position.x + 25.0, 0.1)
		tween.tween_property(self, "position:x", position.x, 0.2)


func _draw_gear() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var half := _sprite.texture.get_size() * _sprite.scale * 0.5

	for slot: GearData.Slot in GEAR_COLORS:
		if not _worn.has(slot):
			continue
		var colour: Color = GEAR_COLORS[slot]
		match slot:
			GearData.Slot.BELT:
				_gear.draw_rect(Rect2(-half.x * 0.7, half.y * 0.1,
					half.x * 1.4, 14.0), colour)
			GearData.Slot.CLOAK:
				_gear.draw_colored_polygon(PackedVector2Array([
					Vector2(-half.x * 0.8, -half.y * 0.4),
					Vector2(half.x * 0.8, -half.y * 0.4),
					Vector2(half.x * 0.5, half.y * 0.9),
					Vector2(-half.x * 0.5, half.y * 0.9),
				]), Color(colour.r, colour.g, colour.b, 0.55))
			GearData.Slot.HEADWEAR:
				_gear.draw_rect(Rect2(-half.x * 0.55, -half.y - 22.0,
					half.x * 1.1, 20.0), colour)
