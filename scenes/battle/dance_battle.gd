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

## Слой для вылетающих цифр урона: выше HUD, иначе удары по герою
## рисуются под шкалами и не видны вовсе.
var _damage_layer: CanvasLayer = null


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


	_pool.release_all()
	_active.clear()
	_next_index = 0
	_next_pattern_index = 0

	Conductor.play(chart)



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
		if not note.is_judged and t - chart.beat_to_time(note.beat) > Judge.late_window() * state.effective_window_scale(Conductor.song_beat):
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
			_popup_damage(state.take_strike(false), _hero.position, false)
			_shake_screen()
		ChartData.NoteType.HEAVY:
			# Крит: вчетверо больнее обычного удара
			_popup_damage(state.take_strike(true), _hero.position, false, true)
			_shake_screen()
			_shake_screen()
		ChartData.NoteType.ATTACK:
			state.register_attack(Judge.Grade.MISS)
		ChartData.NoteType.SKILL:
			# Промах по скиллу бьёт вдвое больнее обычного: особая нота
			# требует особого внимания
			_popup_damage(absi(state.use_skill(Judge.Grade.MISS)),
				_hero.position, false)
		_:
			# Обычный промах тоже стоит здоровья, и цифра над героем
			# показывает сколько именно
			_popup_damage(absi(state.register_hit(Judge.Grade.MISS)),
				_hero.position, false)
	note_judged.emit(Judge.Grade.MISS, Judge.late_window())


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
		# Тап мимо рвёт серию, а начиная с четвёртого подряд ещё и стоит
		# здоровья: рваной серии оказалось мало — она отнимала у игрока
		# его собственный урон, но не мешала долбить кнопку и брать каждый
		# бит даром. Цифра над героем показывает, что это уже не бесплатно
		var stray := state.register_stray_tap()
		if stray != 0:
			_popup_damage(absi(stray), _hero.position, false)
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
		ChartData.NoteType.HEAVY:
			# Тяжёлая атака монстра. Блокируется той же особой кнопкой,
			# что и обычная, но пропущенная бьёт вчетверо больнее
			# (CRIT_MULTIPLIER) — раньше на этом месте стояла нота-зелье,
			# и зелий в игре больше нет
			state.block_strike()
			_hero.nod()
			_guardian_dancer.nod()
		ChartData.NoteType.ATTACK:
			var dealt := state.register_attack(grade)
			_flash_attack(dealt > 0)
			_popup_damage(dealt, _monster_sprite.position, true)
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


## Вылетающая цифра урона.
##
## До неё бой был честным, но немым: шкала Настроя ползла, а насколько именно
## помог конкретный удар, игрок не знал. Число, вылетевшее из монстра, связывает
## нажатие с результатом мгновенно — и по нему же видно, что тяжёлая атака
## монстра бьёт вчетверо больнее обычной.
##
## Цвета разные и не случайные: свой урон читается в цвете попадания,
## чужой — в цвете тревоги, том же, которым мигает замах (§11.1.1).
## Вылетающая цифра урона.
##
## Живёт на СВОЁМ слое поверх HUD. Пока цифры были обычными узлами сцены,
## удары по герою рисовались под шкалами и подсказками дорожек — то есть
## не рисовались вовсе: HUD лежит на слое выше и накрывал их целиком.
##
## Размеры крупные намеренно: прошлые 56 пунктов терялись на пёстром лесу,
## и цифру приходилось искать. Крит вдвое больше обычного и красный —
## вчетверо больший урон обязан и выглядеть вчетверо страшнее.
func _popup_damage(amount: int, at: Vector2, to_monster: bool, crit := false) -> void:
	if amount <= 0:
		return
	if _damage_layer == null:
		_damage_layer = CanvasLayer.new()
		# Выше HUD (10), ниже угощения (50)
		_damage_layer.layer = 20
		add_child(_damage_layer)

	var label := Label.new()
	label.text = "-%d" % amount
	var size := 150 if crit else (100 if to_monster else 88)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color",
		Color("FF3B5C") if crit else (Color("FFD24D") if to_monster else Color("FF8A9E")))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(500, 180)
	# Слегка вразброс: два числа подряд в одной точке слипаются в кашу
	label.position = at + Vector2(-250.0 + randf_range(-50.0, 50.0), -120.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_layer.add_child(label)

	# Подпись матчапа стихий (GDD §5): цифра обязана объяснять, ПОЧЕМУ она
	# больше или меньше обычной, иначе ×2 по уязвимому герою читается как
	# случайность. Отдельный узел, а не вторая строка: у Label один размер
	# шрифта, а подпись должна быть заметно мельче числа
	var relation: MonsterData.Matchup = state.outgoing_matchup() if to_monster \
		else state.incoming_matchup()
	if relation != MonsterData.Matchup.NEUTRAL:
		var tag := Label.new()
		tag.text = "уязвимость" if relation == MonsterData.Matchup.VULNERABLE \
			else "сопротивление"
		tag.add_theme_font_size_override("font_size", 40)
		tag.add_theme_color_override("font_color", label.get_theme_color("font_color"))
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		tag.add_theme_constant_override("outline_size", 8)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.size = Vector2(500, 60)
		tag.position = Vector2(label.position.x, label.position.y + size * 1.05)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_damage_layer.add_child(tag)
		var tag_tween := create_tween()
		tag_tween.tween_property(tag, "position:y", tag.position.y - 190.0, 0.85)
		tag_tween.parallel().tween_property(tag, "modulate:a", 0.0, 0.85)
		tag_tween.tween_callback(tag.queue_free)

	# Крит ещё и вспыхивает: рывок вверх заметнее плавного всплытия
	if crit:
		label.scale = Vector2(0.6, 0.6)
		label.pivot_offset = label.size * 0.5
		var pop := create_tween()
		pop.tween_property(label, "scale", Vector2(1.25, 1.25), 0.12)
		pop.tween_property(label, "scale", Vector2.ONE, 0.1)

	var tween := create_tween()
	tween.tween_property(label, "position:y", label.position.y - 190.0, 0.85)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.85)
	tween.tween_callback(label.queue_free)
