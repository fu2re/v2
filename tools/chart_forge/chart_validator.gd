class_name ChartValidator
extends RefCounted

## Правила разметки чартов на стороне Godot.
##
## Те же семь правил, что в tools/chartgen/beatroot_chartgen/chart.py.
## Дублирование намеренное: генератор проверяет чарт при создании, редактор —
## при каждой правке. Живая проверка в редакторе важнее отсутствия дубля,
## потому что нечестный чарт дешевле не выпустить, чем найти на плейтесте.
##
## Правила описаны в .claude/skills/chart/SKILL.md. При изменении править
## ОБА места и сверять по тому документу.

## Сложность боевого трека = грейд монстра. Ключи и числа обязаны совпадать
## с MAX_DENSITY в chart.py — расхождение означает, что редактор выпустит
## чарт, который генератор забракует, или наоборот.
##
## Потолок не растёт вместе с темпом: легендарный трек играет вдвое быстрее,
## но руки у игрока те же. Верхняя ступень — четыре ноты в секунду, потому
## что сложность больше не выбирают, её навязывает грейд встреченного
## монстра, а победа над ним обязательна для приручения (GDD §6.3).
const MAX_DENSITY := {
	"common": 2.0,
	"uncommon": 2.5,
	"rare": 3.0,
	"unique": 3.5,
	"epic": 4.0,
	"legendary": 4.5,
	# Легаси: обучение и танец растению живут на demo_disco и farm_folk
	"easy": 2.0,
	"normal": 4.0,
	"hard": 8.0,
}

const MIN_SHIELD_GAP := 2.0
const WINDUP_LEAD := 2.0
const MIN_CONTRAST_EPS := 0.0001

## Серия — связка нот без длинной паузы. Атака её завершает.
const SERIES_GAP := 2.0
const MIN_SERIES_NOTES := 3


class Problem:
	var beat: float
	var text: String

	func _init(at: float, message: String) -> void:
		beat = at
		text = message

	func describe() -> String:
		return "доля %.2f: %s" % [beat, text]


## Проверить чарт. Пустой массив — чарт годен к выпуску.
static func validate(chart: ChartData) -> Array[Problem]:
	var problems: Array[Problem] = []
	if chart == null or chart.note_count() == 0:
		return problems

	var bpb := float(chart.beats_per_bar)
	var beats_per_second := chart.bpm / 60.0

	_check_shields_telegraphed(chart, problems)
	_check_shield_gap(chart, problems)
	_check_density(chart, beats_per_second, problems)
	_check_gentle_intro(chart, bpb, problems)
	_check_not_too_early(chart, bpb, problems)
	_check_shield_collisions(chart, problems)
	_check_attacks(chart, problems)

	problems.sort_custom(func(a, b): return a.beat < b.beat)
	return problems


## 7. Перед атакой обязана быть серия минимум из MIN_SERIES_NOTES нот.
##
## Серия считается от предыдущей атаки или от паузы — ровно так же, как её
## считает бой. Атака сразу после паузы бессмысленна: серии перед ней нет,
## и правило «чистая серия» проверять не на чем.
static func _check_attacks(chart: ChartData, out: Array[Problem]) -> void:
	var since := 0
	for i in chart.note_count():
		var beat := chart.note_beats[i]
		var gap := beat - chart.note_beats[i - 1] if i > 0 else 1e9
		since = 1 if gap > SERIES_GAP else since + 1

		if chart.note_types[i] != ChartData.NoteType.ATTACK:
			continue

		if i == 0 or gap > SERIES_GAP:
			out.append(Problem.new(beat, "атака в начале связки — серии перед ней нет"))
		elif since - 1 < MIN_SERIES_NOTES:
			out.append(Problem.new(beat,
				"связка перед атакой всего %d нот, нужно %d" % [since - 1, MIN_SERIES_NOTES]))
		since = 0


## 1. Каждому щиту предшествует видимый замах монстра.
static func _check_shields_telegraphed(chart: ChartData, out: Array[Problem]) -> void:
	var windups: Array[float] = []
	for i in chart.pattern_beats.size():
		if chart.pattern_actions[i] == "windup":
			windups.append(chart.pattern_beats[i])

	for i in chart.note_count():
		if chart.note_types[i] != ChartData.NoteType.SHIELD:
			continue
		var beat := chart.note_beats[i]
		var telegraphed := false
		for w in windups:
			var lead := beat - w
			if lead >= WINDUP_LEAD - MIN_CONTRAST_EPS and lead <= float(chart.beats_per_bar):
				telegraphed = true
				break
		if not telegraphed:
			out.append(Problem.new(beat,
				"щит без замаха минимум за %.0f доли — игрок не может его увидеть"
					% WINDUP_LEAD))


## 2. Два щита подряд ближе двух долей — ребёнок физически не успеет.
static func _check_shield_gap(chart: ChartData, out: Array[Problem]) -> void:
	var previous := -1000.0
	for i in chart.note_count():
		if chart.note_types[i] != ChartData.NoteType.SHIELD:
			continue
		var beat := chart.note_beats[i]
		if beat - previous < MIN_SHIELD_GAP - MIN_CONTRAST_EPS:
			out.append(Problem.new(beat, "щиты подряд, разрыв меньше %.0f долей" % MIN_SHIELD_GAP))
		previous = beat


## 3. Плотность нот в секунду не выше предела сложности.
static func _check_density(chart: ChartData, beats_per_second: float,
		out: Array[Problem]) -> void:
	var limit: float = MAX_DENSITY.get(chart.difficulty, 4.0)
	for i in chart.note_count():
		var window_end := chart.note_beats[i] + beats_per_second
		var count := 0
		for j in range(i, chart.note_count()):
			if chart.note_beats[j] >= window_end:
				break
			count += 1
		if count > limit:
			out.append(Problem.new(chart.note_beats[i],
				"плотность %d нот/сек выше предела %.0f для сложности '%s'"
					% [count, limit, chart.difficulty]))
			return


## 4. Первые два такта — не плотнее одной ноты на долю.
##
## Плотный старт читается как «игра началась без меня» и это самая частая
## причина, по которой ребёнок бросает ритм-игру на первом же бою.
static func _check_gentle_intro(chart: ChartData, bpb: float, out: Array[Problem]) -> void:
	var previous := -1000.0
	for i in chart.note_count():
		var beat := chart.note_beats[i]
		if beat >= bpb * 2.0:
			break
		if beat - previous < 1.0 - MIN_CONTRAST_EPS:
			out.append(Problem.new(beat, "вход в бой слишком плотный"))
			return
		previous = beat


## 5. Первая нота не раньше конца первого такта.
static func _check_not_too_early(chart: ChartData, bpb: float, out: Array[Problem]) -> void:
	if chart.note_beats[0] < bpb - MIN_CONTRAST_EPS:
		out.append(Problem.new(chart.note_beats[0],
			"первая нота раньше конца первого такта — игрок не успел поймать ритм"))


## 6. Щит не совпадает по времени с нотой другого типа.
static func _check_shield_collisions(chart: ChartData, out: Array[Problem]) -> void:
	for i in range(chart.note_count() - 1):
		if absf(chart.note_beats[i] - chart.note_beats[i + 1]) > MIN_CONTRAST_EPS:
			continue
		if chart.note_types[i] == ChartData.NoteType.SHIELD \
				or chart.note_types[i + 1] == ChartData.NoteType.SHIELD:
			out.append(Problem.new(chart.note_beats[i], "щит совпадает с нотой другого типа"))


static func describe_all(problems: Array[Problem]) -> String:
	if problems.is_empty():
		return "Чарт годен"
	var lines: Array[String] = []
	for p in problems:
		lines.append("• " + p.describe())
	return "\n".join(lines)
