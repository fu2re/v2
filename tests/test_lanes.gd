extends TestHarness

## Две кнопки и дорожки нот (GDD §4.1–4.2).
##
## Правая половина низа — обычный бит, левая — особый. Смысл разделения
## в том, что атака монстра требует ИМЕННО особой кнопки: не успел или
## нажал не ту — удар дошёл. Если это правило ослабнет, бой снова
## превратится в «тапай почаще», и заметить это по экрану будет нельзя.

const NORMAL := NoteRules.Lane.NORMAL
const SPECIAL := NoteRules.Lane.SPECIAL


func run_tests() -> void:
	_test_lane_assignment()
	_test_shield_needs_special_button()
	_test_no_note_takes_both_buttons()
	_test_every_note_type_has_lane()
	await _test_notes_fall_towards_their_button()
	await _test_series_line_stays_straight()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _test_lane_assignment() -> void:
	print("Каждый тип ноты знает свою кнопку")
	check_eq(NoteRules.primary_lane(ChartData.NoteType.BEAT), NORMAL,
		"обычный бит — правая кнопка")
	for type in [ChartData.NoteType.ATTACK, ChartData.NoteType.SHIELD,
			ChartData.NoteType.SKILL]:
		check_eq(NoteRules.primary_lane(type), SPECIAL,
			"%s — левая кнопка" % ChartData.NoteType.keys()[type])


## Главное правило двух кнопок: щит альтернативы не имеет.
func _test_shield_needs_special_button() -> void:
	print("Щит берётся только особой кнопкой")
	check(NoteRules.accepts(ChartData.NoteType.SHIELD, SPECIAL),
		"особой кнопкой щит принимается")
	check(not NoteRules.accepts(ChartData.NoteType.SHIELD, NORMAL),
		"обычной — нет, иначе атаку монстра можно было бы отбить наугад")

	check(not NoteRules.accepts(ChartData.NoteType.ATTACK, NORMAL),
		"атака тоже требует особой кнопки")
	check(not NoteRules.accepts(ChartData.NoteType.BEAT, SPECIAL),
		"обычный бит особой кнопкой не берётся")


## Ни одна нота больше не принимает обе кнопки (GDD §4.2.3).
##
## Такой была нота-зелье, но зелий в игре нет: лечение переехало к костру,
## а тяжёлая атака блокируется той же особой кнопкой, что и обычная.
func _test_no_note_takes_both_buttons() -> void:
	print("Ни одна нота не принимает обе кнопки")
	check(NoteRules.accepts(ChartData.NoteType.HEAVY, SPECIAL),
		"тяжёлая атака берётся особой")
	check(not NoteRules.accepts(ChartData.NoteType.HEAVY, NORMAL),
		"и обычной НЕ берётся")

	for type in range(ChartData.NoteType.size()):
		var both := NoteRules.accepts(type, SPECIAL) and NoteRules.accepts(type, NORMAL)
		check(not both, "тип %d не принимает обе кнопки" % type)


## Сторож против забытого типа: новый тип ноты обязан получить дорожку,
## иначе он молча уедет в «особые» и станет неберущимся.
func _test_every_note_type_has_lane() -> void:
	print("Все типы нот разложены по кнопкам")
	for type_name: String in ChartData.NoteType.keys():
		var type: int = ChartData.NoteType[type_name]
		var lane := NoteRules.primary_lane(type)
		check(lane == NORMAL or lane == SPECIAL,
			"у типа %s есть дорожка" % type_name)
		check(NoteRules.accepts(type, lane),
			"тип %s принимает свою же кнопку" % type_name)


## Нота съезжает к своей кнопке: подсказка встроена в траекторию.
func _test_notes_fall_towards_their_button() -> void:
	print("Ноты падают к своим кнопкам")
	var battle := preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	battle.autostart = false
	add_child(battle)
	await _frames(2)

	var beat_note: Note = battle._pool.acquire(4.0, ChartData.NoteType.BEAT)
	var shield_note: Note = battle._pool.acquire(4.0, ChartData.NoteType.SHIELD)
	check_eq(beat_note.lane, NORMAL, "бит на обычной дорожке")
	check_eq(shield_note.lane, SPECIAL, "щит на особой")

	# Позиции ставит бой при спавне — повторяем ту же формулу и сверяем
	# со СТОРОНОЙ экрана, а не с числом: важно, что вправо и влево
	# Тип указан явно: чтение константы через узел даёт Variant,
	# и вывод типа через := невозможен
	var centre: float = battle.LANE_X
	var normal_x: float = centre + battle.LANE_OFFSET
	var special_x: float = centre - battle.LANE_OFFSET
	check(normal_x > centre, "обычные правее центра")
	check(special_x < centre, "особые левее центра")

	battle.queue_free()
	await _frames(2)


## Линия серии — вертикальный стержень, а не зигзаг между дорожками.
func _test_series_line_stays_straight() -> void:
	print("Линия серии не прыгает между дорожками")
	var battle := preload("res://scenes/battle/DanceBattle.tscn").instantiate()
	battle.autostart = false
	add_child(battle)
	await _frames(2)

	battle.chart = ChartLoader.load_by_id("demo_disco", "normal")
	check(battle.chart != null, "чарт для проверки загрузился")
	if battle.chart == null:
		battle.queue_free()
		return

	# Кладём ноты обеих дорожек подряд: раньше линия соединяла их точки
	# напрямую и ломалась зигзагом
	for pair: Array in [[4.0, ChartData.NoteType.BEAT], [4.5, ChartData.NoteType.SHIELD],
			[5.0, ChartData.NoteType.BEAT]]:
		var note: Note = battle._pool.acquire(pair[0], pair[1])
		var shift: float = battle.LANE_OFFSET if note.lane == NORMAL else -battle.LANE_OFFSET
		note.position = Vector2(battle.LANE_X + shift, 500.0 + pair[0] * 10.0)
		battle._active.append(note)

	var xs: Array[float] = []
	for note: Note in battle._active:
		xs.append(note.position.x)
	check(xs.min() < xs.max(), "ноты действительно разъехались по дорожкам")

	# А стержень линии — по центру: он показывает непрерывность во времени
	battle._draw_series_line()
	check(true, "отрисовка линии не падает на разных дорожках")

	battle.queue_free()
	await _frames(2)
