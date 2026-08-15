class_name UIUtil
extends RefCounted

## Мелкие помощники интерфейса.


## Убрать всех детей ПРЯМО СЕЙЧАС, а не в конце кадра.
##
## `queue_free()` отложен: узел остаётся в дереве до конца кадра. В контейнере
## это означает, что старые элементы продолжают занимать место и ловить ввод,
## пока новые уезжают вниз — список выглядит удвоенным, а клики попадают
## не туда. Перед удалением узел надо вынуть из дерева.
##
## Использовать во ВСЕХ местах, где список перестраивается на лету.
static func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Фон странички места: нарисованный экран усадьбы под интерфейсом.
##
## Каждое место усадьбы (огород, дом защитников, амбар) рисуется своим фоном,
## и вход туда должен ощущаться переходом В МЕСТО, а не сменой списка.
## Пока фон не нарисован, остаётся плоская заливка — это ожидаемо,
## а не поломка: арт добавляется по мере отрисовки, без правок кода.
##
## Фон приглушается: поверх него лежит текст, и полноцветная картинка
## спорит с ним за внимание ровно так же, как фон боя спорил бы с нотами
## (GDD §11.1.1).
static func set_screen_background(sprite: Sprite2D, art_path: String,
		dim: float = 0.55) -> bool:
	if sprite == null or not ResourceLoader.exists(art_path):
		return false

	var texture := load(art_path) as Texture2D
	if texture == null:
		return false

	sprite.texture = texture
	sprite.modulate = Color(dim, dim, dim, 1.0)
	sprite.visible = true
	cover_screen(sprite)
	return true


## Растянуть спрайт так, чтобы он ЗАКРЫЛ экран целиком.
##
## Фоны рисуются размером 328×480 — это исходник пиксель-арта, а экран
## 1080×1920. Без масштабирования картинка висит маркой посреди пустоты,
## что и случилось на первом живом прогоне усадьбы.
##
## Берём БОЛЬШИЙ из двух коэффициентов: меньший оставил бы поля по краям,
## а поле в фоне читается как обрыв мира. Лишнее уходит за край — это
## обычный «cover», и композиция фона рисуется с запасом именно под него.
static func cover_screen(sprite: Sprite2D, screen: Vector2 = Vector2(1080, 1920)) -> void:
	if sprite == null or sprite.texture == null:
		return
	var size := sprite.texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var factor := maxf(screen.x / size.x, screen.y / size.y)
	sprite.scale = Vector2(factor, factor)
	sprite.position = screen * 0.5


## Прямоугольник-подложка на весь экран для модальных панелей.
##
## Без неё панель висит поверх живого экрана: кнопки под ней видно, но они
## не нажимаются, и это читается как поломка.
static func make_backdrop(colour: Color = Color(0.05, 0.09, 0.06, 0.96)) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(1080, 1920)
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect
