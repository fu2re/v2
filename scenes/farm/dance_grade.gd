class_name DanceGrade
extends RefCounted

## Оценка танца растению.
##
## Провала здесь НЕТ по устройству: минимальный результат попытки — уровень 1,
## который всё равно ускоряет рост. Ноль возможен только если игрок вообще
## не стал танцевать (GDD §7.2). Ребёнок танцует, потому что приятно;
## взрослый выжимает качество фрукта.

enum Level { SKIPPED, WEAK, GOOD, PERFECT }

const LEVEL_NAMES := {
	Level.SKIPPED: "Не танцевал",
	Level.WEAK: "Неплохо",
	Level.GOOD: "Здорово!",
	Level.PERFECT: "Идеально!",
}

## Доли от максимума, начиная с которых даётся уровень.
const PERFECT_RATIO := 0.85
const GOOD_RATIO := 0.55


## Очки: идеальное попадание — 2, приблизительное — 1.
static func score(perfect_hits: int, good_hits: int) -> int:
	return perfect_hits * 2 + good_hits


static func max_score(note_count: int) -> int:
	return note_count * 2


## Уровень за станцованную фразу. Даже при нуле попаданий — WEAK,
## а не SKIPPED: попытка обязана что-то дать.
static func level_for(perfect_hits: int, good_hits: int, note_count: int) -> Level:
	if note_count <= 0:
		return Level.SKIPPED
	var ratio := float(score(perfect_hits, good_hits)) / float(max_score(note_count))
	if ratio >= PERFECT_RATIO:
		return Level.PERFECT
	if ratio >= GOOD_RATIO:
		return Level.GOOD
	return Level.WEAK


static func level_name(level: Level) -> String:
	return LEVEL_NAMES.get(level, "?")
