class_name Judge
extends RefCounted

## Оценка тайминга. Чистая логика без узлов и состояния сцены —
## именно поэтому её можно прогнать headless и не гадать, честен ли бой.
##
## Окна и множители — в data/battle.json (judge), читаются через Balance:
## это баланс, и он правится без программиста. Знак дельты:
## положительная — игрок опоздал.

enum Grade { PERFECT, GOOD, EARLY_LATE, MISS }

## Ключи оценок в таблице battle.json → judge.effects.
const GRADE_KEYS := {
	Grade.PERFECT: "perfect",
	Grade.GOOD: "good",
	Grade.EARLY_LATE: "early_late",
	Grade.MISS: "miss",
}

const GRADE_NAMES := {
	Grade.PERFECT: "PERFECT",
	Grade.GOOD: "GOOD",
	Grade.EARLY_LATE: "EARLY/LATE",
	Grade.MISS: "MISS",
}


static func perfect_window() -> float:
	return Balance.judge_perfect_window()


static func good_window() -> float:
	return Balance.judge_good_window()


static func late_window() -> float:
	return Balance.judge_late_window()


## Оценить попадание. window_scale расширяет окна снаряжением (обувь).
static func grade(delta_seconds: float, window_scale: float = 1.0) -> Grade:
	var d := absf(delta_seconds)
	if d <= Balance.judge_perfect_window() * window_scale:
		return Grade.PERFECT
	if d <= Balance.judge_good_window() * window_scale:
		return Grade.GOOD
	if d <= Balance.judge_late_window() * window_scale:
		return Grade.EARLY_LATE
	return Grade.MISS


## Попадает ли нота вообще в зону оценки.
static func in_range(delta_seconds: float, window_scale: float = 1.0) -> bool:
	return absf(delta_seconds) <= Balance.judge_late_window() * window_scale


static func grade_name(g: Grade) -> String:
	return GRADE_NAMES.get(g, "?")


static func effect(g: Grade) -> float:
	return Balance.judge_effect(GRADE_KEYS.get(g, ""))


## Множитель комбо (battle.json → judge.combo_steps). Взрослый выбивает
## монстра быстрее, но и ребёнок доходит до конца — просто медленнее.
static func combo_multiplier(combo: int) -> float:
	return Balance.combo_multiplier(combo)
