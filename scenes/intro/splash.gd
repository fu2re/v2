extends Node2D

## Заставка на время разогрева.
##
## Раньше это был один кадр ожидания в `boot.gd`: автозагрузчики читали сейв,
## реестр сканировал каталоги, и всё это происходило за чёрным экраном.
## Держать игрока перед пустотой нельзя, а разогрев тем временем стал длиннее:
## теперь читаются ещё и балансовые таблицы, и индекс из трёхсот чартов.

## Сколько заставка висит минимум. Разогрев быстрее, но моргнувший
## на два кадра логотип выглядит как сбой, а не как заставка.
const MIN_SECONDS := 1.2

@onready var _status: Label = $Status
@onready var _art: Sprite2D = $Art


func _ready() -> void:
	_status.text = "Настраиваем инструменты…"
	# Игра начинается с ноты. Джингл цитирует главный мотив, поэтому заставка
	# звучит той же музыкой, что и всё остальное
	Jukebox.play_cue("boot")

	# Заставка обязана закрыть экран целиком. Раньше она висела в своём
	# исходном размере, и снизу оставалась полоса заливки — первое, что
	# видит игрок, выглядело как незагрузившийся экран
	UIUtil.cover_screen(_art)
	var base := _art.scale

	# Заставка «дышит»: неподвижная картинка на секунду читается как зависшая.
	# Дышит ОТ покрывающего масштаба, а не от единицы, иначе вдох снова
	# оголил бы край
	var tween := create_tween().set_loops()
	tween.tween_property(_art, "scale", base * 1.03, 0.6)
	tween.tween_property(_art, "scale", base, 0.6)

	_warm_up()


func _warm_up() -> void:
	var started := Time.get_ticks_msec()

	# Разогрев по одному шагу за кадр: так заставка успевает нарисоваться,
	# а не застывает вместе с загрузкой
	await get_tree().process_frame
	Registry.ensure_loaded()

	await get_tree().process_frame
	Balance.ensure_loaded()

	await get_tree().process_frame
	ChartSelect.ensure_scanned()

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	if elapsed < MIN_SECONDS:
		await get_tree().create_timer(MIN_SECONDS - elapsed).timeout

	get_tree().change_scene_to_file(OnboardingState.entry_scene())
