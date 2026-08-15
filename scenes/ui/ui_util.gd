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
