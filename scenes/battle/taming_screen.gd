extends CanvasLayer

## Экран угощения после победы.
##
## Здесь живёт главное обещание игры детям (GDD §6.1): исход НИКОГДА не бывает
## отрицательным. Нет фруктов — победа всё равно зачтена. Фрукт нелюбимый —
## прибавка меньше, но она есть. Слова «не получилось» на этом экране
## не может быть в принципе.

signal finished()

const PANEL_COLOR := Color("24391F")
const TEXT_COLOR := Color("DCC7A4")
const PROGRESS_COLOR := Color("FF57C4")
const TAMED_COLOR := Color("FFD24D")

var _monster: MonsterData = null
var _perfect_run := false
var _gained := 0

var _title: Label = null
var _detail: Label = null
var _bar_fill: ColorRect = null
var _bar_width := 0.0
var _buttons: VBoxContainer = null
var _done := false


func _ready() -> void:
	layer = 50
	_build()


## Показать экран. perfect_run — S-ранг, ни промаха, ни пропущенной атаки.
func show_for(monster: MonsterData, perfect_run: bool) -> void:
	_monster = monster
	_perfect_run = perfect_run
	_done = false

	# Победа засчитывается СРАЗУ, до всякого угощения. Даже если игрок
	# уйдёт с экрана ни с чем, встреча продвинула его вперёд
	var win_bonus := GameState.FRIENDSHIP_PERFECT_WIN if perfect_run \
		else GameState.FRIENDSHIP_WIN
	_gained = win_bonus
	var tamed := GameState.add_friendship(monster.id, win_bonus)

	_title.text = "%s заслушался!" % monster.display_name
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
			% [_monster.display_name, _gained]
		_add_button("Дальше", _finish)
		return

	_detail.text = "%s любит: %s\n\nЧем угостишь?" % [
		_monster.display_name,
		_fruit_name(_monster.favorite_fruit_id),
	]

	for offer: Array in offers:
		var fruit_id: String = offer[0]
		var quality: FruitData.Quality = offer[1]
		var count: int = offer[2]
		var bonus := GameState.friendship_from_fruit(_monster.id, fruit_id, quality)
		var favorite := "  ★" if fruit_id == _monster.favorite_fruit_id else ""
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
		return GameState.friendship_from_fruit(_monster.id, a[0], a[1]) \
			> GameState.friendship_from_fruit(_monster.id, b[0], b[1]))
	return out


func _feed(fruit_id: String, quality: FruitData.Quality) -> void:
	if _done:
		return
	if not GameState.consume_fruit(fruit_id, quality):
		return

	var bonus := GameState.friendship_from_fruit(_monster.id, fruit_id, quality)
	_gained += bonus
	var tamed := GameState.add_friendship(_monster.id, bonus)
	SaveManager.mark_dirty()

	_refresh_bar()
	if tamed:
		_celebrate()
	else:
		_detail.text = "%s распробовал!\n+%d к дружбе" % [_monster.display_name, bonus]
		_build_fruit_buttons()


func _refresh_bar() -> void:
	var value := GameState.get_friendship(_monster.id)
	var threshold := _monster.friendship_threshold()
	var ratio := clampf(float(value) / maxf(threshold, 1.0), 0.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_bar_fill, "size:x", _bar_width * ratio, 0.35)


func _celebrate() -> void:
	_done = true
	_title.text = "%s теперь с тобой!" % _monster.display_name
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


func _build() -> void:
	visible = false

	var panel := ColorRect.new()
	panel.size = Vector2(1080, 1920)
	panel.color = Color(PANEL_COLOR.r, PANEL_COLOR.g, PANEL_COLOR.b, 0.96)
	add_child(panel)

	_title = Label.new()
	_title.position = Vector2(60, 220)
	_title.size = Vector2(960, 140)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 68)
	_title.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(_title)

	_bar_width = 900.0
	var track := ColorRect.new()
	track.position = Vector2(90, 430)
	track.size = Vector2(_bar_width, 44)
	track.color = Color(0, 0, 0, 0.45)
	add_child(track)

	_bar_fill = ColorRect.new()
	_bar_fill.position = track.position
	_bar_fill.size = Vector2(0, 44)
	_bar_fill.color = PROGRESS_COLOR
	add_child(_bar_fill)

	_detail = Label.new()
	_detail.position = Vector2(90, 520)
	_detail.size = Vector2(900, 300)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 42)
	_detail.add_theme_color_override("font_color", TEXT_COLOR)
	add_child(_detail)

	_buttons = VBoxContainer.new()
	_buttons.position = Vector2(90, 880)
	_buttons.custom_minimum_size = Vector2(900, 0)
	_buttons.size = Vector2(900, 800)
	_buttons.add_theme_constant_override("separation", 24)
	add_child(_buttons)
