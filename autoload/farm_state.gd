extends Node

## Ферма: грядки, семена, рост в реальном времени.
##
## Урожай НИКОГДА не портится и не сгорает (GDD §2). Никаких «вернись через
## 4 часа или потеряешь» — это ровно та манипулятивная механика, которую
## игра для детей не имеет права использовать.

signal plots_changed()
signal seeds_changed()
signal plot_ready(index: int)

const STARTING_PLOTS := 4
const MAX_PLOTS := 16
## Цена следующей грядки растёт, чтобы расширение оставалось решением
const PLOT_BASE_COST := 60
const PLOT_COST_STEP := 45

## Сокращение времени роста за танец (GDD §7.2). Провала нет: худший
## исход — обычный рост, а не потерянное растение.
const DANCE_REDUCTION := {
	0: 0.0,    # не танцевал
	1: 0.15,   # слабо
	2: 0.30,   # хорошо
	3: 0.40,   # идеально
}

## Сколько реального времени засчитывается за один запуск игры.
## Защита от перевода системных часов вперёд (открытый вопрос GDD §15.4).
## Щедро для честного игрока, конечно для нечестного.
const MAX_OFFLINE_CREDIT := 86400.0 * 2.0

## Грядки. Каждая — Dictionary: seed_id, grown, needed, dance_level, dance_used.
var plots: Array = []
## Семена в амбаре: fruit_id -> количество.
var seed_bag: Dictionary = {}
## Виды, которые игрок вообще открыл. Пустой список означает,
## что сажать нечего — так стартует новая игра.
var known_seeds: Array[String] = []

var _last_seen_unix: float = 0.0


func _ready() -> void:
	if plots.is_empty():
		_init_plots(STARTING_PLOTS)
	_last_seen_unix = Time.get_unix_time_from_system()


func _init_plots(count: int) -> void:
	plots.clear()
	for i in count:
		plots.append(_empty_plot())


func _empty_plot() -> Dictionary:
	return {
		"seed_id": "",
		"grown": 0.0,
		"needed": 0.0,
		"dance_level": 0,
		"dance_used": false,
	}


# --- время -------------------------------------------------------------------

## Начислить прошедшее время всем растущим грядкам.
##
## Копим ВЫРОСШЕЕ время, а не сравниваем метки посадки с текущим часом.
## Сравнение меток ломается от смены часового пояса, перевода часов
## и обычного перелёта — а накопление устойчиво ко всему этому.
func tick() -> void:
	var now := Time.get_unix_time_from_system()
	var delta := now - _last_seen_unix
	_last_seen_unix = now

	# Часы ушли назад: перевод времени или смена пояса. Роста не начисляем,
	# но и не наказываем — просто ждём, пока время снова пойдёт вперёд
	if delta <= 0.0:
		return
	delta = minf(delta, MAX_OFFLINE_CREDIT)

	var changed := false
	for i in plots.size():
		var plot: Dictionary = plots[i]
		if plot.seed_id.is_empty() or plot.grown >= plot.needed:
			continue
		plot.grown = minf(plot.grown + delta, plot.needed)
		changed = true
		if plot.grown >= plot.needed:
			plot_ready.emit(i)

	if changed:
		plots_changed.emit()


# --- посадка и сбор ----------------------------------------------------------

func plot_count() -> int:
	return plots.size()


func is_empty_plot(index: int) -> bool:
	return _valid(index) and plots[index].seed_id.is_empty()


func is_ready(index: int) -> bool:
	if not _valid(index) or plots[index].seed_id.is_empty():
		return false
	return plots[index].grown >= plots[index].needed


## Доля роста от 0 до 1 — для отрисовки грядки.
func growth_ratio(index: int) -> float:
	if not _valid(index) or plots[index].seed_id.is_empty():
		return 0.0
	var plot: Dictionary = plots[index]
	return clampf(plot.grown / maxf(plot.needed, 1.0), 0.0, 1.0)


func seconds_left(index: int) -> float:
	if not _valid(index) or plots[index].seed_id.is_empty():
		return 0.0
	var plot: Dictionary = plots[index]
	return maxf(plot.needed - plot.grown, 0.0)


func plant(index: int, fruit_id: String) -> bool:
	if not is_empty_plot(index):
		return false
	if seed_count(fruit_id) <= 0:
		return false
	var fruit := Registry.fruit(fruit_id)
	if fruit == null:
		push_error("Неизвестное семя: %s" % fruit_id)
		return false

	_take_seed(fruit_id)
	var plot: Dictionary = plots[index]
	plot.seed_id = fruit_id
	plot.grown = 0.0
	plot.needed = float(fruit.grow_seconds())
	plot.dance_level = 0
	plot.dance_used = false

	plots_changed.emit()
	SaveManager.mark_dirty()
	return true


## Записать результат танца. Танцевать можно один раз за цикл роста:
## это маленький ритуал, а не кнопка гринда.
func apply_dance(index: int, level: int) -> bool:
	if not _valid(index):
		return false
	var plot: Dictionary = plots[index]
	if plot.seed_id.is_empty() or plot.dance_used or plot.grown >= plot.needed:
		return false

	plot.dance_used = true
	plot.dance_level = clampi(level, 0, 3)
	var reduction: float = DANCE_REDUCTION.get(plot.dance_level, 0.0)
	plot.needed = maxf(plot.needed * (1.0 - reduction), 1.0)

	plots_changed.emit()
	SaveManager.mark_dirty()
	return true


func can_dance(index: int) -> bool:
	if not _valid(index):
		return false
	var plot: Dictionary = plots[index]
	return not plot.seed_id.is_empty() and not plot.dance_used and plot.grown < plot.needed


## Качество урожая по тому, как станцевали (GDD §7.2).
static func quality_for_dance(level: int) -> FruitData.Quality:
	if level >= 3:
		return FruitData.Quality.PERFECT
	if level >= 2:
		return FruitData.Quality.JUICY
	return FruitData.Quality.PLAIN


## Собрать урожай. Возвращает пустую строку, если собирать нечего.
func harvest(index: int) -> String:
	if not is_ready(index):
		return ""
	var plot: Dictionary = plots[index]
	var fruit_id: String = plot.seed_id
	var quality := quality_for_dance(plot.dance_level)

	GameState.add_fruit(fruit_id, quality, 1)
	plots[index] = _empty_plot()

	plots_changed.emit()
	SaveManager.mark_dirty()
	return fruit_id


func next_plot_cost() -> int:
	return PLOT_BASE_COST + PLOT_COST_STEP * (plots.size() - STARTING_PLOTS)


func buy_plot() -> bool:
	if plots.size() >= MAX_PLOTS:
		return false
	var cost := next_plot_cost()
	if GameState.seeds < cost:
		return false
	GameState.add_seeds(-cost)
	plots.append(_empty_plot())
	plots_changed.emit()
	SaveManager.mark_dirty()
	return true


# --- семена ------------------------------------------------------------------

func seed_count(fruit_id: String) -> int:
	return seed_bag.get(fruit_id, 0)


func add_seed(fruit_id: String, count: int = 1) -> void:
	if Registry.fruit(fruit_id) == null:
		push_error("Неизвестное семя: %s" % fruit_id)
		return
	seed_bag[fruit_id] = seed_count(fruit_id) + count
	if not known_seeds.has(fruit_id):
		known_seeds.append(fruit_id)
	seeds_changed.emit()
	SaveManager.mark_dirty()


func _take_seed(fruit_id: String) -> void:
	var have := seed_count(fruit_id)
	if have <= 1:
		seed_bag.erase(fruit_id)
	else:
		seed_bag[fruit_id] = have - 1
	seeds_changed.emit()


func available_seeds() -> Array[String]:
	var out: Array[String] = []
	for fruit_id: String in seed_bag:
		if seed_bag[fruit_id] > 0:
			out.append(fruit_id)
	out.sort()
	return out


# --- сериализация ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"plots": plots.duplicate(true),
		"seed_bag": seed_bag.duplicate(),
		"known_seeds": known_seeds.duplicate(),
		"last_seen": _last_seen_unix,
	}


func from_dict(d: Dictionary) -> void:
	plots = d.get("plots", [])
	if plots.is_empty():
		_init_plots(STARTING_PLOTS)
	seed_bag = d.get("seed_bag", {})

	known_seeds.clear()
	for id: Variant in d.get("known_seeds", []):
		known_seeds.append(String(id))

	# Время последнего визита берём из сейва: разница до «сейчас» и есть
	# оффлайн-рост. tick() применит её с ограничением сверху
	_last_seen_unix = float(d.get("last_seen", Time.get_unix_time_from_system()))
	tick()


func reset() -> void:
	_init_plots(STARTING_PLOTS)
	seed_bag.clear()
	known_seeds.clear()
	_last_seen_unix = Time.get_unix_time_from_system()


## Только для тестов: сдвинуть точку отсчёта назад, имитируя оффлайн.
func debug_rewind(seconds: float) -> void:
	_last_seen_unix -= seconds


func _valid(index: int) -> bool:
	return index >= 0 and index < plots.size()
