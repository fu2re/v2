extends TestHarness

## Поляна отдаёт своё ровно один раз.
##
## Найдено на живом прогоне: один и тот же куст можно было трясти сто раз
## подряд, набивая сумку бесконечно. Тот же изъян был у костра (лечение
## без предела), у дикого куста, у бабушки и у события — все они срабатывали
## на каждый тап, потому что разрешение поляны нигде не запоминалось.
##
## Проверяется наблюдаемый результат: сколько добра прибавилось после
## ВТОРОГО нажатия. Проверять флаг бессмысленно — он и был бы верным.

const COMMON := MonsterData.Rarity.COMMON


func run_tests() -> void:
	await _test_glade_is_empty_after_battle()
	await _test_hint_never_promises_a_missing_button()
	await _test_wild_bush_gives_once()
	await _test_loot_bush_gives_once()
	await _test_campfire_heals_once()
	await _test_granny_asks_once()
	await _test_merchant_can_be_reopened()
	await _test_next_glade_resets_it()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _feed_with(glade: Glade) -> Node:
	GameState.reset()
	FarmState.reset()
	RunManager.set_seed(2024)
	GameState.tame("disco_sprout", COMMON)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(2)

	RunManager.current_glade = glade
	feed._glade_cleared = false
	feed._glade_used = false
	feed._show_glade(glade)
	await _frames(1)
	return feed


## После боя поляна пуста: монстра нет, шкалы нет, награды не обещают.
##
## Живой отчёт со скриншотом: «этого экрана быть вообще не должно». Карточка
## возвращалась в том же виде, в каком звала в бой — со спрайтом убежавшего
## монстра, «Дружба 0/100» и «Победа: +10 серебра · сундук». Монстр к тому
## моменту либо приручён, либо убежал, и обещать за него награду экран права
## не имеет: игрок читает это как «сюда можно ещё раз».
func _test_glade_is_empty_after_battle() -> void:
	print("После боя поляна пуста")
	var glade := _make(Glade.Type.BATTLE)
	glade.grade = COMMON
	var feed := await _feed_with(glade)

	# До боя монстр на месте — иначе проверка ниже ничего не значит
	check(feed._glade_art.texture != null, "до боя монстр показан")
	check(feed._reward_label.visible, "до боя обещана награда")

	feed._pending_result = "Проверка"
	feed._awaiting_result_swipe = true
	feed._dismiss_battle()
	await _frames(2)

	check(feed._glade_art.texture == null, "монстра на поляне больше нет")
	check(not feed._reward_label.visible, "награду за него не обещают")
	check(not feed._friendship_track.visible, "шкалы дружбы нет")
	check(not feed._tame_banner.visible, "и пометки «можно подружиться» тоже")
	check(feed._subline.text.is_empty(), "подпись про жанр и любимый фрукт убрана")
	check(not feed._headline.text.contains(Registry.monster("synth_slime").display_name),
		"в заголовке больше не имя монстра: [%s]" % feed._headline.text)
	# Но уйти отсюда можно — иначе игрок заперт на пустой поляне
	check(feed._next_button.visible, "кнопка «Дальше» на месте")
	check(feed._next_button.pressed.get_connections().size() > 0,
		"и у неё есть обработчик")

	# Итог боя делает подсказку многострочной, и на живом прогоне она
	# наезжала на полоску здоровья. Меряем ШРИФТОМ: `get_combined_minimum_size`
	# у подписи с переносом возвращает размер ДО переноса и молча
	# отчитывается, что всё помещается
	feed._hint.text = "Вьюн убежал, но танец не пропал.\nЗащитник стал опытнее.\n%s" \
		% RunFeed.HINT_NEXT
	await _frames(2)
	var font: Font = feed._hint.get_theme_font("font")
	var size: int = feed._hint.get_theme_font_size("font_size")
	var needed: Vector2 = font.get_multiline_string_size(feed._hint.text,
		HORIZONTAL_ALIGNMENT_CENTER, feed._hint.size.x, size)
	check(needed.y <= feed._hint.size.y + 1.0,
		"итог боя помещается в подсказку (нужно %.0f, есть %.0f)"
			% [needed.y, feed._hint.size.y])
	check(feed._hint.position.y + needed.y <= feed._health_fill.position.y,
		"и не наезжает на полоску здоровья")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Подсказка не зовёт к кнопке, которой на экране нет.
##
## Текст подсказки ставится при показе поляны и дальше живёт сам по себе,
## а кнопка действия исчезает по состоянию. Получался экран, зовущий нажать
## «Танцевать», которой на нём нет: ребёнок ищет несуществующую кнопку
## и решает, что игра сломалась.
func _test_hint_never_promises_a_missing_button() -> void:
	print("Подсказка не зовёт к отсутствующей кнопке")
	var glade := _make(Glade.Type.BATTLE)
	glade.grade = COMMON
	var feed := await _feed_with(glade)

	# До боя всё честно: и кнопка, и обещание
	check(feed._action_button.visible, "кнопка «Танцевать» на месте")
	check(feed._hint.text.contains("Танцевать"),
		"и подсказка её обещает: [%s]" % feed._hint.text)

	# Бой прошёл, приручение закончилось — итога в подсказке нет, и она
	# осталась бы прежней. Именно этот случай и обнажал расхождение
	feed._glade_cleared = true
	feed._pending_result = ""
	feed._refresh_buttons()
	await _frames(2)

	check(not feed._action_button.visible, "после боя кнопки действия нет")
	check(not feed._hint.text.contains("Танцевать"),
		"и подсказка её больше не обещает: [%s]" % feed._hint.text)

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _make(type: Glade.Type, encounter := Glade.Encounter.MERCHANT) -> Glade:
	var glade := Glade.new()
	glade.type = type
	glade.encounter = encounter
	glade.depth = 4
	glade.monster_id = "synth_slime"
	glade.fruit_id = "drum_berry"
	glade.silver_reward = 12
	return glade


## Сколько всего добра у игрока: любое изменение здесь после второго
## нажатия и есть баг.
func _wealth() -> int:
	var total := RunManager.run_silver
	for count: int in RunManager.run_seed_bag.values():
		total += count
	for count: int in RunManager.run_fruits.values():
		total += count
	total += GameState.owned_gear_ids().size()
	return total


func _test_wild_bush_gives_once() -> void:
	print("Дикий куст обирается один раз")
	var feed: Node = await _feed_with(_make(Glade.Type.WILD_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()
	check(after_first > 0, "первый сбор что-то дал (%d)" % after_first)

	for i in 5:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), after_first, "пять повторных тапов не дали ничего")
	check(not feed._action_button.visible, "кнопка сбора убрана")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _test_loot_bush_gives_once() -> void:
	print("Куст с гостинцами трясётся один раз")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.LOOT_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()
	check(after_first > 0, "первое потряхивание что-то дало (%d)" % after_first)

	# Ровно то, что нашлось в игре: сто раз подряд по одному кусту
	for i in 20:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), after_first, "двадцать повторов не дали ничего")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Костёр лечит РОВНО СТОЛЬКО, сколько съедено.
##
## Сам по себе он не лечит вовсе (GDD §8.2.3): здоровье возвращают фрукты,
## и каждый съеденный уходит из сумки. Открыть панель десять раз можно —
## лечиться будет нечем.
func _test_campfire_heals_once() -> void:
	print("Костёр лечит ровно на съеденное")
	var feed: Node = await _feed_with(_make(Glade.Type.CAMPFIRE))
	RunManager.set_health(10)
	GameState.add_fruit("drum_berry", FruitData.Quality.PLAIN, 1)

	# Пустой привал не лечит: открытие панели — не награда
	feed._resolve_glade()
	await _frames(1)
	check_eq(RunManager.health, 10, "открытая панель сама по себе не лечит")

	var berry := Registry.fruit("drum_berry")
	feed._eat_at_campfire("drum_berry", FruitData.Quality.PLAIN)
	await _frames(1)
	var after_first := RunManager.health
	check_eq(after_first, 10 + berry.heal(), "съеденный фрукт вылечил")
	check_eq(GameState.fruit_count("drum_berry", FruitData.Quality.PLAIN), 0,
		"и ушёл из сумки")

	# Есть нечего — здоровье стоит на месте
	for i in 10:
		feed._eat_at_campfire("drum_berry", FruitData.Quality.PLAIN)
		await _frames(1)
	check_eq(RunManager.health, after_first, "без фруктов лечить нечем")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


func _test_granny_asks_once() -> void:
	print("Бабушка просит один раз")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.GRANNY))
	RunManager.add_loot_silver(200)

	feed._resolve_glade()
	await _frames(1)
	var wealth_after_first := _wealth()

	for i in 10:
		feed._resolve_glade()
		await _frames(1)
	check_eq(_wealth(), wealth_after_first, "повторные подходы ничего не меняют")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## Торговец — исключение: к прилавку можно вернуться, он ничего не раздаёт
## даром, а запирать игрока на одном заходе значило бы наказывать
## за случайное закрытие панели.
func _test_merchant_can_be_reopened() -> void:
	print("К торговцу можно вернуться")
	var feed: Node = await _feed_with(
		_make(Glade.Type.ENCOUNTER, Glade.Encounter.MERCHANT))

	feed._resolve_glade()
	await _frames(1)
	check(feed._panel_box.visible, "прилавок открылся")

	feed._close_panel()
	await _frames(1)
	check(feed._action_button.visible, "кнопка «Товар» осталась")

	feed._resolve_glade()
	await _frames(1)
	check(feed._panel_box.visible, "прилавок открылся снова")
	check_eq(_wealth(), 0, "но сам по себе он ничего не выдал")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)


## На следующей поляне всё начинается заново — иначе игрок обошёл бы
## лес, собрав ровно одну поляну.
func _test_next_glade_resets_it() -> void:
	print("Следующая поляна снова щедра")
	var feed: Node = await _feed_with(_make(Glade.Type.WILD_BUSH))

	feed._resolve_glade()
	await _frames(1)
	var after_first := _wealth()

	# Идём дальше и собираем всё, что дают, пока не попадётся дающая поляна
	var gained := false
	for i in 30:
		feed._next_glade()
		await _frames(1)
		var glade := RunManager.current_glade
		if glade == null or glade.type == Glade.Type.BATTLE:
			continue
		if glade.type == Glade.Type.ENCOUNTER \
				and glade.encounter == Glade.Encounter.MERCHANT:
			continue
		var before := _wealth()
		feed._resolve_glade()
		await _frames(1)
		if _wealth() > before:
			gained = true
			break

	check(gained, "на новой поляне добыча снова доступна")
	check(_wealth() > after_first, "и она прибавилась к прежней")

	RunManager.go_home()
	feed.queue_free()
	await _frames(2)
