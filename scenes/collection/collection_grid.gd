class_name CollectionGrid
extends RefCounted

## Правила витрины коллекции (GDD §7.5).
##
## Отдельно от экрана намеренно: «каким показать монстра» — это правило игры,
## а не рисование, и его надо уметь проверить без поднятия сцены. Экран
## спрашивает состояние клетки и раскрашивает, а решает — здесь.

enum Cell {
	## Не встречался: чёрный силуэт. Видно, что кто-то есть, но не видно кто.
	HIDDEN,
	## Встречен на поляне, но не побеждён: силуэт светлеет.
	##
	## Ступень между «не знаю о нём» и «победил». Без неё встреча с редким
	## экземпляром не меняла в коллекции ровно ничего, и игрок, прошедший
	## мимо уникального, видел ту же черноту, что и до забега.
	MET,
	## Побеждён, но не приручён: скин открыт, рамки нет.
	REVEALED,
	## Приручён: скин открыт и обведён рамкой.
	TAMED,
}

## Цвет рамки приручённого. Один на все грейды: рамка отвечает на вопрос
## «мой или нет», а грейд и без неё виден по колонке и по цвету подписи.
const TAMED_FRAME := Color("FFD24D")

## Насколько тускнеет открытый, но не приручённый. Не в ноль: он уже
## заслужен победой, и гасить его до силуэта значит отнимать сделанное.
const REVEALED_DIM := 0.72


static func state_for(species_id: String, grade: int) -> Cell:
	if GameState.has_instance(species_id, grade):
		return Cell.TAMED
	if GameState.is_revealed(species_id, grade):
		return Cell.REVEALED
	if GameState.is_met(species_id, grade):
		return Cell.MET
	return Cell.HIDDEN


## Как красить спрайт в клетке.
##
## Силуэт — это `modulate` в чёрный, а не отдельная картинка: рисовать
## по силуэту на каждого монстра × каждый грейд значило бы тридцать лишних
## файлов, которые всё равно повторяют форму основного.
static func tint_for(state: Cell) -> Color:
	match state:
		Cell.HIDDEN:
			return Color(0, 0, 0, 0.85)
		Cell.MET:
			# Силуэт уже не чёрный, но и не скин: «видел, но не победил»
			return Color(0.32, 0.28, 0.24, 0.95)
		Cell.REVEALED:
			return Color(REVEALED_DIM, REVEALED_DIM, REVEALED_DIM, 1.0)
		_:
			return Color.WHITE


## Что писать под клеткой. У закрытого имени нет — иначе коллекция
## рассказывала бы содержание вперёд игрока.
static func caption_for(species_id: String, grade: int) -> String:
	var state := state_for(species_id, grade)
	if state == Cell.HIDDEN:
		return "?"
	if state == Cell.MET:
		return "%s · встречен" % MonsterData.rarity_name(grade)
	return MonsterData.rarity_name(grade)


## Открывается ли карточка по нажатию. По закрытой клетке смотреть нечего,
## и молчаливое нажатие честнее пустой карточки.
static func opens_card(species_id: String, grade: int) -> bool:
	return state_for(species_id, grade) != Cell.HIDDEN
