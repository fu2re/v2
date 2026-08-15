extends Node2D

## Дэнс-баттл: падающие ноты, щиты, шкалы Настроя и Ритма.
##
## Логика исхода живёт в BattleState (чистый класс), здесь — только подача.

signal note_judged(grade: int, delta_seconds: float)
signal battle_finished(won: bool, state: BattleState)

const JUDGE_Y := 1480.0
const SPAWN_Y := 420.0
const LANE_X := 540.0
## За сколько долей до попадания нота появляется — «скорость скролла».
const APPROACH_BEATS := 2.0
## Насколько заранее монстр начинает замах (GDD: не меньше 2 долей).
const WINDUP_LEAD := 2.0
const SNACK_RESTORE := 15

@export var chart_id: String = "demo_disco"
@export var difficulty: String = "normal"
@export var monster_id: String = "synth_slime"
@export var guardian_id: String = "disco_sprout"
@export var starting_health: int = 100
@export var starting_shield: int = -1
@export var depth: int = 0
@export var autostart: bool = true

var chart: ChartData = null
var state := BattleState.new()

var _pool: NotePool = null
var _hud: BattleHUD = null
var _active: Array[Note] = []
var _next_index: int = 0
var _next_pattern_index: int = 0
var _monster_sprite: Sprite2D = null
var _knocked_out: Node2D = null
var _outcome_label: Label = null
var _hero: Dancer = null
var _guardian_dancer: Dancer = null


func _ready() -> void:
	_pool = NotePool.new()
	add_child(_pool)
	_hud = BattleHUD.new()
	add_child(_hud)
	_build_stage()

	Conductor.beat.connect(_on_beat)
	Conductor.finished.connect(_on_track_finished)
	state.victory.connect(_on_victory)
	state.defeat.connect(_on_defeat)

	if autostart:
		start()


func start() -> void:
	var loaded := ChartLoader.load_by_id(chart_id, difficulty)
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

	var monster := Registry.monster(monster_id)
	var guardian := Registry.monster(guardian_id)
	if monster == null or guardian == null:
		push_error("Не найден монстр '%s' или гуардиан '%s'" % [monster_id, guardian_id])
		return

	state.setup(monster, guardian, starting_health, depth, starting_shield)
	# Обучение занижает Настрой, чтобы первый бой заведомо кончился победой
	if vibe_override > 0:
		state.max_vibe = vibe_override
		state.vibe = vibe_override
	_hud.bind(state)
	if _monster_sprite != null:
		_monster_sprite.texture = monster.sprite()
	_hero.setup(load("res://art/placeholder/hero.png") as Texture2D)
	_guardian_dancer.setup(guardian.sprite(), GameState.equipped.get(guardian.id, {}))

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
			note.position = Vector2(LANE_X, SPAWN_Y)
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


func _expire_missed() -> void:
	var t := Conductor.song_position
	var i := 0
	while i < _active.size():
		var note: Note = _active[i]
		if not note.is_judged and t - chart.beat_to_time(note.beat) > Judge.LATE_WINDOW * state.window_scale:
			_miss(note)
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


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("tap"):
		return
	if not Conductor.is_playing or chart == null or state.is_over:
		return
	_judge_tap()


func _judge_tap() -> void:
	# Свежее время: кэш Conductor отстаёт на кадр, это треть окна Perfect
	var t := Conductor.now()

	var best: Note = null
	var best_delta := 0.0
	for note in _active:
		if note.is_judged:
			continue
		var delta := t - chart.beat_to_time(note.beat)
		if not Judge.in_range(delta, state.window_scale):
			continue
		if best == null or absf(delta) < absf(best_delta):
			best = note
			best_delta = delta

	if best == null:
		return  # тап в пустоту не наказывается: игра для детей

	best.is_judged = true
	var grade := Judge.grade(best_delta, state.window_scale)

	match best.type:
		ChartData.NoteType.SHIELD:
			state.block_strike()
		ChartData.NoteType.SNACK:
			state.register_hit(grade)
			state.restore_health(SNACK_RESTORE)
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
func _build_knocked_out() -> void:
	_knocked_out = Node2D.new()
	_knocked_out.visible = false
	_knocked_out.z_index = 5
	_knocked_out.position = Vector2(LANE_X, 300)
	_knocked_out.draw.connect(func():
		for side in [-1.0, 1.0]:
			var c := Vector2(side * 34.0, -18.0)
			var r := 18.0
			_knocked_out.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), Color.BLACK, 7.0)
			_knocked_out.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), Color.BLACK, 7.0))
	add_child(_knocked_out)


func _build_stage() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(1080, 1920)
	# Фон боя притемнён, иначе земляная палитра спорит с нотами (GDD §11.1.1)
	bg.color = Color("33512A").darkened(0.30)
	bg.z_index = -10
	add_child(bg)

	var line := Line2D.new()
	line.add_point(Vector2(60, JUDGE_Y))
	line.add_point(Vector2(1020, JUDGE_Y))
	line.width = 6.0
	line.default_color = Color("1ED8FF")
	add_child(line)

	_monster_sprite = Sprite2D.new()
	_monster_sprite.scale = Vector2(4, 4)
	_monster_sprite.position = Vector2(LANE_X, 300)
	add_child(_monster_sprite)
	# Герой и защитник внизу: игрок видит, что танцует не один,
	# и что снаряжение на защитнике действительно надето
	_hero = Dancer.new()
	_hero.position = Vector2(LANE_X - 250.0, 1560.0)
	add_child(_hero)

	_guardian_dancer = Dancer.new()
	_guardian_dancer.position = Vector2(LANE_X + 250.0, 1560.0)
	add_child(_guardian_dancer)

	_build_knocked_out()

	_outcome_label = Label.new()
	_outcome_label.position = Vector2(60, 560)
	_outcome_label.size = Vector2(960, 120)
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outcome_label.add_theme_font_size_override("font_size", 72)
	_outcome_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_outcome_label.add_theme_constant_override("outline_size", 12)
	_outcome_label.visible = false
	add_child(_outcome_label)
