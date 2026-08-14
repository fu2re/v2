class_name Judge
extends RefCounted

## Оценка тайминга. Чистая логика без узлов и состояния сцены —
## именно поэтому её можно прогнать headless и не гадать, честен ли бой.
##
## Окна из GDD §4.3. Знак дельты: положительная — игрок опоздал.

enum Grade { PERFECT, GOOD, EARLY_LATE, MISS }

const PERFECT_WINDOW := 0.050
const GOOD_WINDOW := 0.110
const LATE_WINDOW := 0.180

## Множитель эффекта по оценке. Промах не отнимает у игрока ничего —
## по GDD наказывает только пропущенный щит, обычная нота лишь замедляет.
const EFFECT := {
	Grade.PERFECT: 1.0,
	Grade.GOOD: 0.6,
	Grade.EARLY_LATE: 0.3,
	Grade.MISS: 0.0,
}

const GRADE_NAMES := {
	Grade.PERFECT: "PERFECT",
	Grade.GOOD: "GOOD",
	Grade.EARLY_LATE: "EARLY/LATE",
	Grade.MISS: "MISS",
}


## Оценить попадание. window_scale расширяет окна снаряжением (обувь).
static func grade(delta_seconds: float, window_scale: float = 1.0) -> Grade:
	var d := absf(delta_seconds)
	if d <= PERFECT_WINDOW * window_scale:
		return Grade.PERFECT
	if d <= GOOD_WINDOW * window_scale:
		return Grade.GOOD
	if d <= LATE_WINDOW * window_scale:
		return Grade.EARLY_LATE
	return Grade.MISS


## Попадает ли нота вообще в зону оценки.
static func in_range(delta_seconds: float, window_scale: float = 1.0) -> bool:
	return absf(delta_seconds) <= LATE_WINDOW * window_scale


static func grade_name(g: Grade) -> String:
	return GRADE_NAMES.get(g, "?")


static func effect(g: Grade) -> float:
	return EFFECT.get(g, 0.0)


## Множитель комбо по GDD §4.3. Взрослый выбивает монстра быстрее,
## но и ребёнок доходит до конца — просто медленнее.
static func combo_multiplier(combo: int) -> float:
	if combo >= 50:
		return 3.0
	if combo >= 25:
		return 2.0
	if combo >= 10:
		return 1.5
	return 1.0
