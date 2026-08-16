extends Node2D

## Дэнс-баттл: падающие ноты, щиты, шкалы Настроя и Ритма.
##
## Логика исхода живёт в BattleState (чистый класс), здесь — только подача.

signal note_judged(grade: int, delta_seconds: float)
signal battle_finished(won: bool, state: BattleState)

const JUDGE_Y := 1480.0
const SPAWN_Y := 420.0
const LANE_X := 540.0
## Насколько нота съезжает от центра к своей кнопке. Смещение маленькое
## намеренно: обе дорожки остаются одним потоком чтения, но глаз заранее
## видит, какой рукой брать (GDD §4.1).
const LANE_OFFSET := 150.0

## Два нажатия ближе этого времени считаются одним.
##
## На телефоне включена эмуляция мыши из касания, и один палец приходит
## дважды: как касание и как синтетический клик. Без этого порога одна нота
## судилась бы двумя событиями, а комбо скакало бы вдвое. Человек физически
## не жмёт одну кнопку чаще.
const TAP_DEDUP_SECONDS := 0.02
## За сколько долей до попадания нота появляется — «скорость скролла».
const APPROACH_BEATS := 2.0
## Насколько заранее монстр начинает замах (GDD: не меньше 2 долей).
const WINDUP_LEAD := 2.0
## Лечение приходит из предмета, а не из константы боя: сколько вернёт
## глоток, записано в самом зелье (GDD §4.2.3).

## Линия серии. Оба цвета намеренно СВЕТЛЕЕ фона боя: тёмно-серый
## на тёмно-зелёном не читался, и линии как будто не было вовсе.
const SERIES_CLEAN_COLOR := Color("7FF3FF")
const SERIES_BROKEN_COLOR := Color("C9C4B8")
const SERIES_LINE_WIDTH := 16.0

## Пусто — трек подбирается по монстру и грейду (ChartSelect).
## Заполнено — играется именно этот чарт: так делают обучение и отладка сцены.
@export var chart_id: String = ""
@export var difficulty: String = "normal"
@export var monster_id: String = "synth_slime"
## Грейд встреченного экземпляра: он задаёт и статы, и спрайт, и темп трека.
@export var monster_grade: int = MonsterData.Rarity.COMMON
## Ключ экземпляра-гуардиана. Пустая строка — бой без защитника
## (интро, §15.5): игрок танцует один.
@export var guardian_key: String = ""
@export var starting_health: int = 100
@export var starting_shield: int = -1
@export var depth: int = 0
@export var autostart: bool = true

var chart: ChartData = null
var state := BattleState.new()

## Сцена боя лежит в DanceBattle.tscn и правится в инспекторе (GDD §13.2.1).
## Позиции монстра, героя, защитника и линии удара — там, а не здесь.
@onready var _pool: NotePool = $NotePool
@onready var _hud: BattleHUD = $BattleHUD
@onready var _monster_sprite: Sprite2D = $MonsterSprite
@onready var _knocked_out: Node2D = $MonsterSprite/KnockedOut
@onready var _outcome_label: Label = $OutcomeLabel
@onready var _hero: Dancer = $Hero
@onready var _guardian_dancer: Dancer = $GuardianDancer
## Линия, соединяющая ноты одной серии. Без неё непонятно, где связка
## началась и почему звезда в её конце вдруг серая.
@onready var _series_line: Node2D = $SeriesLine

var _active: Array[Note] = []
var _next_index: int = 0
var _next_pattern_index: int = 0

## Защита от двойного суждения одного касания (см. TAP_DEDUP_SECONDS).
var _last_lane: int = -1
var _last_tap_time: float = 0.0

## Тренер обучения, если он включён. Ему нужно знать, какую кнопку
## показывать, а это известно только здесь — по ближайшей ноте.
var _coach: Node = null


func _ready() -> void:
	# Рисование остаётся в коде: узел в сцене задаёт ГДЕ, а _draw — ЧТО.
	# Ноты и линия серии перерисовываются десятки раз в секунду,
	# и отдельные узлы под каждый штрих тут дороже (GDD §13.2.1)
	_series_line.draw.connect(_draw_series_line)
	_knocked_out.draw.connect(_draw_knocked_out)

	Conductor.beat.connect(_on_beat)
	Conductor.finished.connect(_on_track_finished)
	state.victory.connect(_on_victory)
	state.defeat.connect(_on_defeat)

	if autostart:
		start()


func start() -> void:
	# Трек выбирается по стихии, мотиву и грейду встреченного монстра
	# (GDD §10.1.1). Явно заданный chart_id перекрывает выбор — это нужно
	# обучению и отладке сцены, где трек фиксирован намеренно
	var loaded: ChartData = null
	if chart_id.is_empty():
		loaded = ChartSelect.load_for(Registry.monster(monster_id), monster_grade)
	else:
		loaded = ChartLoader.load_by_id(chart_id, difficulty)

	if loaded == null:
		push_error("Не удалось загрузить чарт %s [%s]" % [chart_id, difficulty])
		return
	begin(loaded)


## Запуск с готовым чартом. Нужен там, где чарт строится в коде —
## например в обучении. Публичный вход вместо правки полей снаружи:
## иначе часть подготовки (спрайт монстра, привязка HUD) молча пропускается.
func begin(prepared: ChartData, vibe_override: int = 0) -> void:
	chart = prepared
	if chart == null:
		return

	if Registry.monster(monster_id) == null:
		push_error("Не найден монстр '%s'" % monster_id)
		return

	# Противник — экземпляр встречи: грейд роллится на поляне, а не берётся
	# у вида. Гуардиана может не быть вовсе — в интро игрок танцует один
	var monster := MonsterInstance.create(monster_id, monster_grade)
	var guardian := GameState.instance(guardian_key)

	state.setup(monster, guardian, starting_health, depth, starting_shield)
	# Обучение занижает Настрой, чтобы первый бой заведомо кончился победой
	if vibe_override > 0:
		state.max_vibe = vibe_override
		state.vibe = vibe_override
	_hud.bind(state)
	_hud.set_monster(monster)
	if _monster_sprite != null:
		_monster_sprite.texture = monster.sprite()
	# Герой того пола, который выбрал игрок (GDD §15.5)
	_hero.setup(GameState.hero_sprite())

	# Без гуардиана рядом с героем никого нет: скрываем, а не рисуем пустоту
	if guardian == null:
		_guardian_dancer.visible = false
	else:
		_guardian_dancer.visible = true
		_guardian_dancer.setup(guardian.sprite(), GameState.equipped_slots(guardian.key()))

	_gate_potion_notes()

	_pool.release_all()
	_active.clear()
	_next_index = 0
	_next_pattern_index = 0

	Conductor.play(chart)


## Нота-зелье ставится в бой только если зелье есть в сумке (GDD §4.2.3).
##
## Пустые ноты не ВЫБРАСЫВАЮТСЯ, а становятся обычными битами: выброс
## изменил бы плотность и разорвал бы серии там, где чарт их задумывал,
## а тап должен остаться. Правится копия массива, чтобы не портить чарт
## в кеше — его же увидит следующий бой.
func _gate_potion_notes() -> void:
	if GameState.has_any_potion():
		return

	var patched := chart.note_types.duplicate()
	var changed := false
	for i in patched.size():
		if patched[i] == ChartData.NoteType.SNACK:
			patched[i] = ChartData.NoteType.BEAT
			changed = true
	if not changed:
		return

	# Копия чарта: исходный лежит в кеше загрузчика и переиспользуется
	var gated := ChartData.new()
	gated.id = chart.id
	gated.genre = chart.genre
	gated.difficulty = chart.difficulty
	gated.bpm = chart.bpm
	gated.offset = chart.offset
	gated.duration = chart.duration
	gated.beats_per_bar = chart.beats_per_bar
	gated.audio_path = chart.audio_path
	gated.note_beats = chart.note_beats
	gated.note_types = patched
	gated.pattern_beats = chart.pattern_beats
	gated.pattern_actions = chart.pattern_actions
	chart = gated


func _process(_delta: float) -> void:
	if not Conductor.is_playing or chart == null or state.is_over:
		return
	_spawn_due_notes()
	_run_monster_pattern()
	_update_positions()
	_expire_missed()


func _spawn_due_notes() -> void:
	var horizon := Conductor.song_beat + APPROACH_BEATS
	while _next_index < chart.note_count() and chart.note_beats[_next_index] <= horizon:
		var note := _pool.acquire(chart.note_beats[_next_index], chart.note_types[_next_index])
		if note != null:
			# Нота съезжает к своей кнопке: особые левее центра, обычные правее
			var shift := LANE_OFFSET if note.lane == NoteRules.Lane.NORMAL else -LANE_OFFSET
			note.position = Vector2(LANE_X + shift, SPAWN_Y)
			_active.append(note)
		_next_index += 1


## Замах монстра. Телеграф обязателен: ребёнок должен увидеть «монстр
## готовится» раньше, чем появится нота-щит (GDD §4.2).
func _run_monster_pattern() -> void:
	while _next_pattern_index < chart.pattern_beats.size() \
			and chart.pattern_beats[_next_pattern_index] <= Conductor.song_beat:
		var action := chart.pattern_actions[_next_pattern_index]
		if action == "windup":
			_hud.flash_windup(WINDUP_LEAD * chart.sec_per_beat())
			_telegraph_monster()
		_next_pattern_index += 1


func _update_positions() -> void:
	var travel := JUDGE_Y - SPAWN_Y
	for note in _active:
		var beats_left := note.beat - Conductor.song_beat
		note.position.y = SPAWN_Y + (1.0 - beats_left / APPROACH_BEATS) * travel

	# Серая звезда сразу сообщает, что удар уже не сработает
	for note in _active:
		if note.type == ChartData.NoteType.ATTACK:
			var dull := not state.series_clean
			if note.is_dulled != dull:
				note.is_dulled = dull
				note.queue_redraw()

	_series_line.queue_redraw()
	_point_coach_at_next_note()


## Тренер показывает ту кнопку, по которой идёт ближайшая нота.
func _point_coach_at_next_note() -> void:
	if _coach == null:
		return
	var nearest: Note = null
	for note in _active:
		if note.is_judged:
			continue
		if nearest == null or note.beat < nearest.beat:
			nearest = note
	if nearest != null:
		_coach.demo_lane = nearest.lane


func _expire_missed() -> void:
	var t := Conductor.song_position
	var i := 0
	while i < _active.size():
		var note: Note = _active[i]
		if not note.is_judged and t - chart.beat_to_time(note.beat) > Judge.LATE_WINDOW * state.effective_window_scale(Conductor.song_beat):
			_miss(note)
			# Пропуск может закончить бой, а _end_battle очищает список нот.
			# Без этой проверки цикл продолжал работать с индексом в уже
			# пустом массиве и падал — это и был краш при проигрыше
			if state.is_over or _active.is_empty():
				return
			_retire(i)
		elif note.is_judged:
			_retire(i)
		else:
			i += 1


func _miss(note: Note) -> void:
	match note.type:
		ChartData.NoteType.SHIELD:
			state.take_strike()
			_shake_screen()
		ChartData.NoteType.ATTACK:
			state.register_attack(Judge.Grade.MISS)
		ChartData.NoteType.SKILL:
			# Промах по скиллу бьёт вдвое больнее обычного: особая нота
			# требует особого внимания
			state.use_skill(Judge.Grade.MISS)
		_:
			state.register_hit(Judge.Grade.MISS)
	note_judged.emit(Judge.Grade.MISS, Judge.LATE_WINDOW)


## Показать, сработала атака или прошла вхолостую.
##
## Разница обязана читаться мгновенно: игрок должен связать «вёл серию чисто»
## с «монстру прилетело», иначе правило серии останется невидимым.
func _flash_attack(landed: bool) -> void:
	if _monster_sprite == null:
		return
	if landed:
		_hud.flash_hit()
		_shake_screen()

	var tween := create_tween()
	if landed:
		_monster_sprite.modulate = Color("FF6BDE")
		tween.tween_property(_monster_sprite, "scale", Vector2(3.2, 3.2), 0.08)
		tween.tween_property(_monster_sprite, "scale", Vector2(4.0, 4.0), 0.22)
		tween.parallel().tween_property(_monster_sprite, "modulate", Color.WHITE, 0.22)
	else:
		# Холостая атака: монстр даже не дрогнул
		tween.tween_property(_monster_sprite, "modulate", Color(0.6, 0.6, 0.6), 0.1)
		tween.tween_property(_monster_sprite, "modulate", Color.WHITE, 0.2)


func _retire(index: int) -> void:
	_pool.release(_active[index])
	_active.remove_at(index)


## Ввод ловим в _unhandled_input, а НЕ в _input: до боя ввод обязан пройти
## через интерфейс, иначе тап по кнопке дублируется игровым действием.
func _unhandled_input(event: InputEvent) -> void:
	if not Conductor.is_playing or chart == null or state.is_over:
		return

	var lane := -1
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			lane = _lane_at(touch.position.x)
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			lane = _lane_at(click.position.x)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			match key.keycode:
				# Пробел оставлен синонимом правой кнопки: без него ломается
				# привычка десктопной проверки игры
				KEY_RIGHT, KEY_SPACE:
					lane = NoteRules.Lane.NORMAL
				KEY_LEFT:
					lane = NoteRules.Lane.SPECIAL

	if lane < 0:
		return

	# Одно касание приходит и тачем, и синтетическим кликом — судим один раз
	var now := Time.get_ticks_msec() / 1000.0
	if lane == _last_lane and now - _last_tap_time < TAP_DEDUP_SECONDS:
		return
	_last_lane = lane
	_last_tap_time = now

	get_viewport().set_input_as_handled()
	_judge_tap(lane)


## Какая половина экрана нажата.
##
## Считаем в координатах ВЬЮПОРТА, а не сцены: `_shake_screen` двигает корень
## Node2D, и граница, посчитанная в локальных координатах, уезжала бы вместе
## с тряской — попадания начали бы уходить не в ту дорожку ровно в тот момент,
## когда экран трясётся.
func _lane_at(screen_x: float) -> int:
	var middle := get_viewport().get_visible_rect().size.x * 0.5
	return NoteRules.Lane.NORMAL if screen_x >= middle else NoteRules.Lane.SPECIAL


func _judge_tap(lane: int) -> void:
	# Свежее время: кэш Conductor отстаёт на кадр, это треть окна Perfect
	var t := Conductor.now()
	# Окна с учётом порыва Ветра, если он сейчас действует (GDD §4.2.4)
	var window := state.effective_window_scale(Conductor.song_beat)

	var best: Note = null
	var best_delta := 0.0
	for note in _active:
		if note.is_judged:
			continue
		# Нота отзывается только на свою кнопку: щит нельзя взять обычным
		# битом, и это главное, ради чего кнопки две
		if not NoteRules.accepts(note.type, lane):
			continue
		var delta := t - chart.beat_to_time(note.beat)
		if not Judge.in_range(delta, window):
			continue
		if best == null or absf(delta) < absf(best_delta):
			best = note
			best_delta = delta

	if best == null:
		# Тап мимо не отнимает здоровье, но рвёт серию: иначе можно долбить
		# обе кнопки подряд и попадать по всему бесплатно
		state.register_stray_tap()
		return

	best.is_judged = true
	var grade := Judge.grade(best_delta, window)

	match best.type:
		ChartData.NoteType.SHIELD:
			state.block_strike()
		ChartData.NoteType.SKILL:
			# Доля передаётся снаружи: порыв Ветра живёт четыре такта,
			# а BattleState о музыкальном времени ничего не знает
			state.use_skill(grade, Conductor.song_beat, chart.beats_per_bar)
			_hero.nod()
			_guardian_dancer.nod()
		ChartData.NoteType.SNACK:
			# Единственная нота с выбором: особой кнопкой зелье выпивают,
			# обычной — засчитывают как простой бит и берегут на потом
			state.register_hit(grade)
			if NoteRules.consumes_potion(best.type, lane):
				var restored := GameState.consume_potion()
				if restored > 0:
					state.restore_health(restored)
					_flash_potion()
			_hero.nod()
			_guardian_dancer.nod()
		ChartData.NoteType.ATTACK:
			var dealt := state.register_attack(grade)
			_flash_attack(dealt > 0)
			_hero.attack(dealt > 0)
			_guardian_dancer.attack(dealt > 0)
		_:
			state.register_hit(grade)
			_hero.nod()
			_guardian_dancer.nod()

	note_judged.emit(grade, best_delta)


func _on_beat(index: int) -> void:
	if _monster_sprite == null or state.is_over:
		return
	# Покачивание в такт. В Фазе 4 сменится скелетной анимацией
	var dir := 1.0 if index % 2 == 0 else -1.0
	var tween := create_tween()
	tween.tween_property(_monster_sprite, "rotation", dir * 0.06, 0.12)
	tween.tween_property(_monster_sprite, "rotation", 0.0, 0.12)
	_hero.step()
	_guardian_dancer.step()


func _telegraph_monster() -> void:
	if _monster_sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(_monster_sprite, "scale", Vector2(4.6, 4.6), 0.25)
	tween.tween_property(_monster_sprite, "scale", Vector2(4.0, 4.0), 0.25)


## Зелье выпито: короткая тёплая вспышка. Без неё трата предмета
## неотличима от обычного попадания, и игрок не понимает, что потратил.
func _flash_potion() -> void:
	if _hero == null:
		return
	var tween := create_tween()
	_hero.modulate = Color("9BE86A")
	tween.tween_property(_hero, "modulate", Color.WHITE, 0.4)


func _shake_screen() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:x", 18.0, 0.05)
	tween.tween_property(self, "position:x", -18.0, 0.05)
	tween.tween_property(self, "position:x", 0.0, 0.05)


## Трек кончился, а Настрой не сбит: монстр устоял. Это не поражение —
## Здоровье цело, забег продолжается.
func _on_track_finished() -> void:
	if state.is_over:
		return
	state.finish_by_timeout()


func _on_victory() -> void:
	_end_battle(true)


func _on_defeat() -> void:
	_end_battle(false)


func _end_battle(won: bool) -> void:
	Conductor.stop()
	_pool.release_all()
	_active.clear()
	_show_outcome(won)
	battle_finished.emit(won, state)


## Итог боя показывается ЗДЕСЬ ЖЕ, а не отдельным экраном.
##
## Победа: монстр падает, вместо глаз крестики. Не победа: он убегает.
## Разница обязана читаться без слов — от неё зависит, поймёт ли ребёнок,
## почему приручение доступно в одном случае и недоступно в другом.
func _show_outcome(won: bool) -> void:
	if _monster_sprite == null:
		return

	var tween := create_tween()
	if won:
		tween.tween_property(_monster_sprite, "rotation", PI * 0.5, 0.45)
		tween.parallel().tween_property(_monster_sprite, "position:y",
			_monster_sprite.position.y + 120.0, 0.45)
		tween.tween_callback(func(): _knocked_out.visible = true)
		_outcome_label.text = "Наплясался!"
		_outcome_label.add_theme_color_override("font_color", Color("FFD24D"))
	else:
		# Убегает вбок и растворяется
		tween.tween_property(_monster_sprite, "position:x", -300.0, 0.7)
		tween.parallel().tween_property(_monster_sprite, "modulate:a", 0.0, 0.7)
		_outcome_label.text = "Убежал…"
		_outcome_label.add_theme_color_override("font_color", Color("ADA99F"))
	_outcome_label.visible = true


## Крестики вместо глаз. Рисуются поверх спрайта, потому что плейсхолдеры
## одинаковых глаз не имеют, а знак «монстр наплясался» нужен уже сейчас.
##
## Узел — РЕБЁНОК спрайта, а не сосед. Пока он был соседом с собственной
## позицией, монстр падал и поворачивался, а крестики оставались висеть
## в воздухе на прежнем месте — ровно то, что видно на живом экране.
## Координаты поэтому локальные и мелкие: спрайт масштабирован вчетверо.
func _draw_knocked_out() -> void:
	for side in [-1.0, 1.0]:
		var c := Vector2(side * 8.5, -4.5)
		var r := 4.5
		_knocked_out.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color.BLACK, 1.8)
		_knocked_out.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), Color.BLACK, 1.8)



## Соединить ноты текущей серии линией.
##
## Игрок должен видеть связку как единое целое: без этого правило «серия
## без промахов» остаётся невидимым, а серая звезда выглядит случайностью.
func _draw_series_line() -> void:
	if chart == null or _active.size() < 2:
		return

	var points := PackedVector2Array()
	for note in _active:
		if note.is_judged:
			continue
		# Щит ВХОДИТ в серию: block_strike наращивает её длину, значит
		# и линия обязана его соединять. Раньше он пропускался, и картинка
		# расходилась с логикой — связка на экране рвалась там, где в игре
		# продолжалась.
		#
		# Точки берём по центру дорожек, а не по самим нотам: иначе линия
		# скакала бы влево-вправо между обычными и особыми. Связка — это
		# непрерывность ВО ВРЕМЕНИ, и стержень показывает именно её
		points.append(Vector2(LANE_X, note.position.y))
		# Атака завершает серию — дальше идёт уже другая связка
		if note.type == ChartData.NoteType.ATTACK:
			break

	if points.size() < 2:
		return

	# Оба цвета СВЕТЛЕЕ фона.
	#
	# Серый #6B6862 на тёмно-зелёном фоне боя не читался вовсе, и игрок
	# трижды сообщал, что линии нет. «Серия испорчена» — это информация,
	# а не украшение: она обязана оставаться видимой.
	var colour := SERIES_CLEAN_COLOR if state.series_clean else SERIES_BROKEN_COLOR
	_series_line.draw_polyline(points, colour, SERIES_LINE_WIDTH, true)


## Включить наглядного тренера поверх боя.
##
## Обучение — это ТОТ ЖЕ бой, просто с дополнительным слоем. Отдельная сцена
## для урока означала бы, что игрок учится на одном, а играет в другое,
## и любое расхождение между ними всплывало бы у него на экране.
func enable_coach() -> Node:
	var coach := preload("res://scenes/onboarding/CoachOverlay.tscn").instantiate()
	coach.judge_y = JUDGE_Y
	coach.lane_x = LANE_X
	coach.lane_offset = LANE_OFFSET
	add_child(coach)
	_coach = coach
	note_judged.connect(func(grade: int, _d: float):
		if grade != Judge.Grade.MISS:
			coach.note_hit())
	battle_finished.connect(func(_won: bool, _s: BattleState): coach.finish())
	return coach
