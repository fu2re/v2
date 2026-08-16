extends CanvasLayer

## Экран угощения после победы.
##
## Здесь живёт главное обещание игры детям (GDD §6.1): исход НИКОГДА не бывает
## отрицательным. Нет фруктов — победа всё равно зачтена. Фрукт нелюбимый —
## прибавка меньше, но она есть. Слова «не получилось» на этом экране
## не может быть в принципе.

signal finished()

const TEXT_COLOR := Color("DCC7A4")
const TAMED_COLOR := Color("FFD24D")

## Побеждённый ЭКЗЕМПЛЯР: дружба копится отдельно на каждый грейд (GDD §6.1),
## поэтому экрану мало знать вид.
var _monster: MonsterInstance = null
var _gained := 0

## Раскладка живёт в TamingScreen.tscn и правится в инспекторе (GDD §13.2.1).
## Раньше эти шесть узлов создавались в `_build()`, и в редакторе экран,
## который игрок видит после КАЖДОЙ победы, выглядел пустым узлом.
@onready var _title: Label = $Title
@onready var _detail: Label = $Detail
@onready var _bar_fill: ColorRect = $BarFill
@onready var _track: ColorRect = $Track
@onready var _buttons: VBoxContainer = $Buttons

## Ширина шкалы берётся у дорожки, а не задаётся числом: подвинул дорожку
## в инспекторе — заполнение поехало следом, без правки кода.
var _bar_width := 0.0
var _done := false


func _ready() -> void:
	_bar_width = _track.size.x


## Показать экран. perfect_run — S-ранг, ни промаха, ни пропущенной атаки.
func show_for(monster: MonsterInstance, perfect_run: bool) -> void:
	# Приручение — свой момент и своя музыка: бой уже кончился, а до поляны
	# ещё не вернулись
	Jukebox.play_screen("taming")
	_monster = monster
	_done = false

	# Победа засчитывается СРАЗУ, до всякого угощения. Даже если игрок
	# уйдёт с экрана ни с чем, встреча продвинула его вперёд
	var win_bonus := GameState.friendship_perfect_win() if perfect_run \
		else GameState.friendship_win()
	_gained = win_bonus
	var tamed := GameState.add_friendship(monster.species_id, monster.grade, win_bonus)

	_title.text = "%s заслушался!" % monster.display_name()
	_refresh_bar()
	_build_fruit_buttons()

	if tamed:
		_celebrate()
	visible = true


func _build_fruit_buttons() -> void:
	UIUtil.clear_children(_buttons)

	var offers := _available_fruits()
	if offers.is_empty():
		_detail.text = "Угостить нечем — но %s запомнил ваш танец.\n+%d к дружбе" \
			% [_monster.display_name(), _gained]
		_add_button("Дальше", _finish)
		return

	var species := _monster.data()
	var favorite_id := species.favorite_fruit_id if species != null else ""
	_detail.text = "%s любит: %s\n\nЧем угостишь?" % [
		_monster.display_name(),
		_fruit_name(favorite_id),
	]

	for offer: Array in offers:
		var fruit_id: String = offer[0]
		var quality: FruitData.Quality = offer[1]
		var count: int = offer[2]
		var bonus := GameState.friendship_from_fruit(_monster.species_id, fruit_id, quality)
		var favorite := "  ★" if fruit_id == favorite_id else ""
		var label := "%s (%s) x%d   +%d%s" % [
			_fruit_name(fruit_id), FruitData.quality_name(quality), count, bonus, favorite,
		]
		_add_button(label, _feed.bind(fruit_id, quality))

	_add_button("Не угощать", _finish)


## Что есть в сумке. Отсортировано по прибавке: самое полезное сверху,
## чтобы ребёнку не пришлось сравнивать числа.
func _available_fruits() -> Array:
	var out: Array = []
	for fruit in Registry.all_fruits():
		for quality in [FruitData.Quality.PERFECT, FruitData.Quality.JUICY,
				FruitData.Quality.PLAIN]:
			var count := GameState.fruit_count(fruit.id, quality)
			if count > 0:
				out.append([fruit.id, quality, count])
	out.sort_custom(func(a, b):
		return GameState.friendship_from_fruit(_monster.species_id, a[0], a[1]) \
			> GameState.friendship_from_fruit(_monster.species_id, b[0], b[1]))
	return out


func _feed(fruit_id: String, quality: FruitData.Quality) -> void:
	if _done:
		return
	if not GameState.consume_fruit(fruit_id, quality):
		return

	var bonus := GameState.friendship_from_fruit(_monster.species_id, fruit_id, quality)
	_gained += bonus
	var tamed := GameState.add_friendship(_monster.species_id, _monster.grade, bonus)
	SaveManager.mark_dirty()

	_refresh_bar()
	if tamed:
		_celebrate()
	else:
		_detail.text = "%s распробовал!\n+%d к дружбе" % [_monster.display_name(), bonus]
		_build_fruit_buttons()


func _refresh_bar() -> void:
	var value := GameState.get_friendship(_monster.species_id, _monster.grade)
	var threshold := GameState.friendship_threshold(_monster.grade)
	var ratio := clampf(float(value) / maxf(threshold, 1.0), 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_bar_fill, "size:x", _bar_width * ratio, 0.35)

	# Полная шкала без объяснения выглядит как поломка: игрок видит, что
	# полоска до края, а друг не появился. Говорим, чего не хватает
	if ratio >= 1.0 and not GameState.can_tame(_monster.species_id, _monster.grade):
		var step := GameState.missing_step(_monster.species_id, _monster.grade)
		_detail.text = "%s готов дружить, но сначала подружись с ним попроще:\n%s" % [
			_monster.display_name(), MonsterData.rarity_name(step),
		]


func _celebrate() -> void:
	_done = true
	# Та же фраза, что в интро (GDD §15.5): момент обретения защитника
	# обязан читаться одинаково и в первый раз, и в сотый
	_title.text = "Теперь %s ваш защитник" % _monster.display_name()
	_title.add_theme_color_override("font_color", TAMED_COLOR)
	_detail.text = "Шкала дружбы заполнена.\nТеперь его можно брать в забег."
	_bar_fill.color = TAMED_COLOR

	UIUtil.clear_children(_buttons)
	_add_button("Отлично!", _finish)


func _finish() -> void:
	visible = false
	SaveManager.save_if_dirty()
	finished.emit()


func _fruit_name(fruit_id: String) -> String:
	var data := Registry.fruit(fruit_id)
	return data.display_name if data != null else fruit_id


func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 110)
	button.add_theme_font_size_override("font_size", 40)
	button.pressed.connect(callback)
	_buttons.add_child(button)
