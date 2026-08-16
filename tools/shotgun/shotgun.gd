extends Node

## Снимки всех экранов игры.
##
## Вёрстку и читаемость нельзя проверить чтением кода: наложение подписей,
## текст, утонувший в пёстром фоне, кнопка, уехавшая за край, — всё это видно
## только глазами. Каждая из этих поломок уже случалась в живой игре и ни разу
## не была поймана ни компиляцией, ни подъёмом сцены.
##
## Сцены поднимаются в SubViewport размером ровно с холст (1080×1920), а не
## в окне: снимок обязан быть одинаковым независимо от того, какой монитор
## у запускающего. Запускать НЕ headless — headless не рисует вовсе:
##
##   godot --path E:/v2 tools/shotgun/Shotgun.tscn
##
## Снимки ложатся в `art/review/screens/`. Каталог под .gitignore: это
## расходный материал ревью, а не ассет.

const OUT_DIR := "res://art/review/screens"
const CANVAS := Vector2i(1080, 1920)

## Сколько кадров ждать после подъёма сцены. Хватает и на _ready, и на tween'ы
## наведения, и на первый _process, в котором дозаполняются подписи.
const SETTLE_FRAMES := 12

const COMMON := 0

## Что снимаем. `setup` — состояние игры перед подъёмом сцены: экран,
## показанный в пустом состоянии, врёт про вёрстку (пустые списки не налезают
## друг на друга).
var _targets: Array[Dictionary] = []

var _viewport: SubViewport = null


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = CANVAS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_targets()

	for target in _targets:
		await _shoot(target)

	print("Готово: %d снимков в %s" % [_targets.size(), OUT_DIR])
	get_tree().quit()


func _build_targets() -> void:
	_targets = [
		{"name": "01_splash", "scene": "res://scenes/intro/Splash.tscn",
			"setup": _fresh_save},
		{"name": "02_character_select", "scene": "res://scenes/intro/CharacterSelect.tscn",
			"setup": _fresh_save},
		{"name": "03_intro", "scene": "res://scenes/intro/Intro.tscn",
			"setup": _fresh_save},
		{"name": "04_lobby", "scene": "res://scenes/lobby/Lobby.tscn",
			"setup": _played_a_while},
		{"name": "05_farm", "scene": "res://scenes/farm/Farm.tscn",
			"setup": _farm_in_progress},
		{"name": "06_collection", "scene": "res://scenes/collection/Collection.tscn",
			"setup": _rich_collection},
		{"name": "07_inventory", "scene": "res://scenes/inventory/Inventory.tscn",
			"setup": _full_bags},
		{"name": "08_merchant", "scene": "res://scenes/merchant/Merchant.tscn",
			"setup": _played_a_while},
		{"name": "09_shop", "scene": "res://scenes/shop/Shop.tscn",
			"setup": _played_a_while},
		{"name": "10_run_feed", "scene": "res://scenes/run/RunFeed.tscn",
			"setup": _played_a_while},
		{"name": "11_battle", "scene": "res://scenes/battle/DanceBattle.tscn",
			"setup": _ready_for_battle, "after": _spawn_every_note},
	]


# --- состояния --------------------------------------------------------------

func _fresh_save() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()
	FarmState.reset()
	ShopState.reset()
	OnboardingState.reset()


func _played_a_while() -> void:
	_fresh_save()
	OnboardingState.mark_done()
	GameState.tame("disco_sprout", COMMON)
	GameState.set_guardian("disco_sprout:0")
	GameState.add_silver(340)
	ShopState.add_gold(120)


func _farm_in_progress() -> void:
	_played_a_while()
	# Грядки в РАЗНЫХ состояниях: пустая, растущая и поспевшая занимают
	# разное место, и налезание видно только на смеси
	FarmState.add_seed("drum_berry", 4)
	FarmState.add_seed("chord_apple", 2)
	FarmState.plant(0, "drum_berry")
	FarmState.plant(1, "chord_apple")
	FarmState.tick()


func _rich_collection() -> void:
	_played_a_while()
	# Несколько экземпляров разных грейдов: одна карточка ничего не скажет
	# про то, как список ведёт себя, когда его много
	GameState.tame("disco_sprout", COMMON)
	GameState.tame("disco_sprout", COMMON + 1)
	GameState.tame("beat_serpent", COMMON)
	GameState.add_gear("acorn_charm")


func _full_bags() -> void:
	_played_a_while()
	FarmState.add_seed("drum_berry", 7)
	FarmState.add_seed("bass_plum", 3)
	GameState.add_gear("acorn_charm")
	GameState.add_potion("health_potion", 2)


# --- съёмка ------------------------------------------------------------------

func _shoot(target: Dictionary) -> void:
	var setup: Callable = target["setup"]
	setup.call()

	var packed: PackedScene = load(target["scene"])
	if packed == null:
		push_error("Не грузится сцена: %s" % target["scene"])
		return
	var instance := packed.instantiate()
	_viewport.add_child(instance)

	for i in SETTLE_FRAMES:
		await get_tree().process_frame

	# Иногда снимку нужно, чтобы на экране что-то происходило: пустой бой
	# не покажет ни одной ноты
	if target.has("after"):
		var after: Callable = target["after"]
		after.call(instance)
		for i in 2:
			await get_tree().process_frame

	# Ждём именно кадр отрисовки: до него текстура вьюпорта пуста
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, target["name"]]
	var err := image.save_png(path)
	if err != OK:
		push_error("Не сохранился снимок %s: %d" % [path, err])
	else:
		print("  %s" % path)

	_viewport.remove_child(instance)
	instance.queue_free()
	await get_tree().process_frame


## Бой с зельями в сумке: снимок нужен, чтобы увидеть форму ноты-бутылочки
## и счётчик глотков. Обе вещи проверяются только глазом.
func _ready_for_battle() -> void:
	_played_a_while()
	GameState.add_potion("health_potion", GameState.MAX_POTIONS)


## Выложить на дорожку по одной ноте каждого типа.
##
## Формы нот — единственное, что игрок читает боковым зрением, и проверить
## их можно только глядя. Расставляем сверху вниз с шагом, чтобы силуэты
## не наложились друг на друга.
func _spawn_every_note(battle: Node) -> void:
	var types := [
		ChartData.NoteType.BEAT, ChartData.NoteType.ATTACK,
		ChartData.NoteType.SKILL, ChartData.NoteType.SHIELD,
		ChartData.NoteType.SNACK,
	]
	var pool = battle.get("_pool")
	var active: Array = battle.get("_active")
	if pool == null:
		return
	# Бой сам расставляет ноты по долям, поэтому сначала глушим его _process,
	# иначе все пять слипнутся в одну точку у линии суда
	battle.set_process(false)
	for i in types.size():
		var note = pool.acquire(0.0, types[i])
		note.position = Vector2(540.0, 300.0 + i * 190.0)
		active.append(note)
