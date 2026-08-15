"""Мотив — мелодическое зерно, из которого растут все аранжировки.

Мотив хранится в ступенях мажорной пентатоники, а не в MIDI-номерах и не
в аудио. Это позволяет жанру выбрать свой тембр и регистр, не трогая мелодию.

Мелодии генерируются, а не сочиняются, поэтому грамматика ниже — не украшение,
а несущая конструкция. Случайная ходьба по пентатонике звучит как перебор
клавиш: ноты согласованы между собой, но фразы не запоминаются, а GDD §10.1
называет запоминаемость главным критерием отбора.

**Одной грамматики мало.** Первая версия строила все мотивы по одному
рецепту: те же ритмические ячейки, та же дуга, тот же круг аккордов, тот же
план фраз. Формально мотивы получались разные, а на слух — один и тот же
мотив, слегка переставленный. Поэтому здесь не одна грамматика, а восемь
характеров (`STYLES`), и каждый задаёт свой ритм, свой контур, свою гармонию
и свой план фраз. Разнообразие обязано закладываться в правила, а не
ожидаться от генератора случайных чисел.
"""

from __future__ import annotations

import json
import math
import random
from dataclasses import dataclass
from pathlib import Path

from .song import PROGRESSIONS, Note, degree_to_midi, degrees_on_chord

# Длина фразы в долях. Четыре такта по 4/4 — период, который слух держит
# целиком: короче не успевает сложиться вопрос-ответ, длиннее не запоминается.
PHRASE_BEATS = 16
BEATS_PER_BAR = 4

# Ступени, в которых живёт мелодия. 0 — тоника, 5 — она же октавой выше.
# Потолок 7 держит диапазон в пределах полутора октав: шире голос уже
# не поётся, а мотив, который нельзя напеть, не запомнится.
MIN_DEGREE = 0
MAX_DEGREE = 7

# Ритмические ячейки на такт, сгруппированные по характеру. Шестнадцатых нет
# намеренно: мотив обязан читаться на самой медленной ступени сложности,
# а мелкое дробление — дело аранжировки.
CELLS: dict[str, tuple[tuple[float, ...], ...]] = {
    "spacious": (
        (2.0, 2.0),
        (2.0, 1.0, 1.0),
        (1.0, 1.0, 2.0),
        (3.0, 1.0),
    ),
    "walking": (
        (1.0, 1.0, 1.0, 1.0),
        (1.0, 1.0, 2.0),
        (2.0, 1.0, 1.0),
        (1.0, 0.5, 0.5, 2.0),
    ),
    "driving": (
        (0.5, 0.5, 0.5, 0.5, 1.0, 1.0),
        (0.5, 0.5, 1.0, 0.5, 0.5, 1.0),
        (1.0, 0.5, 0.5, 1.0, 1.0),
        (0.5, 0.5, 0.5, 0.5, 2.0),
    ),
    "dotted": (
        (1.5, 0.5, 1.5, 0.5),
        (1.5, 1.5, 1.0),
        (0.5, 1.5, 2.0),
        (1.5, 0.5, 2.0),
    ),
    "syncopated": (
        (0.5, 1.0, 1.0, 1.0, 0.5),
        (1.5, 0.5, 1.0, 1.0),
        (0.5, 1.5, 1.0, 1.0),
        (1.0, 1.5, 1.5),
    ),
}

# Планы фраз. Мотив звучит четыре периода, и то, в каком порядке они идут,
# слышно не меньше, чем сами ноты.
PHRASE_PLANS: tuple[tuple[str, ...], ...] = (
    ("A", "B", "A", "C"),
    ("A", "A", "B", "C"),
    ("A", "B", "C", "A"),
    ("A", "B", "A", "B"),
    ("A", "C", "B", "A"),
)


@dataclass(frozen=True)
class Style:
    """Характер мотива: чем один мотив отличается от другого.

    Восемь характеров на десять мотивов — намеренно почти поровну.
    Два мотива одного характера ещё различаются гармонией и контуром,
    а третий уже слышался бы как вариация первых двух.
    """

    name: str
    cells: str
    shape: str
    plan: int
    progression: int


STYLES: tuple[Style, ...] = (
    Style("шагающий",   cells="walking",    shape="arc",      plan=0, progression=0),
    Style("просторный", cells="spacious",   shape="descent",  plan=1, progression=1),
    Style("бегущий",    cells="driving",    shape="wave",     plan=2, progression=2),
    Style("пунктирный", cells="dotted",     shape="climb",    plan=0, progression=3),
    Style("качающий",   cells="syncopated", shape="plateau",  plan=3, progression=4),
    Style("вольный",    cells="walking",    shape="wave",     plan=4, progression=5),
    Style("широкий",    cells="spacious",   shape="climb",    plan=2, progression=6),
    Style("вертлявый",  cells="driving",    shape="descent",  plan=1, progression=7),
)


@dataclass(frozen=True)
class Motif:
    """Мотив: три фразы в ступенях, гармония и план их чередования."""

    id: str
    title: str
    phrases: dict[str, list[tuple[float, float, int]]]
    chords: tuple[int, ...]
    plan: tuple[str, ...]
    style: str = ""
    seed: int = 0

    def notes(self, name: str, tonic: int) -> list[Note]:
        """Фраза как список Note в конкретной тональности и регистре."""
        return [
            Note(beat, degree_to_midi(degree, tonic), length)
            for beat, length, degree in self.phrases[name]
        ]

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "style": self.style,
            "seed": self.seed,
            "chords": list(self.chords),
            "plan": list(self.plan),
            "phrases": {
                name: [[b, ln, d] for b, ln, d in notes]
                for name, notes in self.phrases.items()
            },
        }

    @classmethod
    def from_dict(cls, d: dict) -> Motif:
        return cls(
            id=d["id"],
            title=d["title"],
            style=d.get("style", ""),
            seed=int(d.get("seed", 0)),
            chords=tuple(d["chords"]),
            plan=tuple(d.get("plan", ("A", "B", "A", "C"))),
            phrases={
                name: [(float(n[0]), float(n[1]), int(n[2])) for n in notes]
                for name, notes in d["phrases"].items()
            },
        )


# --- грамматика ---------------------------------------------------------------


def _rhythm(rng: random.Random, cells: str) -> list[tuple[float, float]]:
    """Ритмическая сетка фразы: список пар (доля, длина) на 16 долей.

    Четвёртый такт всегда получает длинную ноту: фраза обязана отдышаться
    перед повтором, иначе четыре периода подряд сливаются в один поток.
    """
    pool = CELLS[cells]
    out: list[tuple[float, float]] = []
    for bar in range(PHRASE_BEATS // BEATS_PER_BAR):
        cell = (2.0, 2.0) if bar == 3 else rng.choice(pool)
        beat = float(bar * BEATS_PER_BAR)
        for length in cell:
            if beat - bar * BEATS_PER_BAR + length > BEATS_PER_BAR + 1e-9:
                break
            out.append((beat, length))
            beat += length
    return out


def _arc(shape: str, i: int, count: int) -> float:
    """Целевая ступень в точке i по форме контура.

    Форма — то, что слух запоминает вместо отдельных нот. Пять форм дают
    пять разных мелодических жестов; без них все мотивы получались одной
    и той же дугой «вверх и обратно».
    """
    t = i / max(count - 1, 1)
    if shape == "arc":
        # Подъём к вершине и возвращение домой
        return 1.0 + 5.0 * (1.0 - abs(2.0 * t - 0.9)) if t < 0.95 else 0.0
    if shape == "descent":
        # Начинается сверху и оседает: жест выдоха
        return 6.0 - 5.5 * t
    if shape == "wave":
        # Две небольшие волны вместо одной большой
        return 3.0 + 2.5 * math.sin(2.0 * math.pi * t - math.pi / 2.0)
    if shape == "climb":
        # Всё время вверх: фраза-вопрос, ответ даёт следующая
        return 0.5 + 6.0 * t
    if shape == "plateau":
        # Прыжок вверх, площадка, спуск в конце
        if t < 0.15:
            return 1.0 + 30.0 * t
        return 5.5 if t < 0.75 else 5.5 - 18.0 * (t - 0.75)
    raise ValueError(f"неизвестная форма контура: {shape}")


def _contour(rng: random.Random, count: int, shape: str) -> list[int]:
    """Ступени фразы по заданной форме.

    Контур строится по форме, а не случайным блужданием, и это принципиально.
    Блуждание с перевесом в одну сторону даёт формально верную мелодию,
    у которой нет жеста: за четыре такта она уходит от тоники на две-три
    ступени и топчется там.

    Поверх формы работают два правила голосоведения:

    * **преобладает поступенное движение** — форма меняется примерно
      на полступени за ноту, поэтому соседние ноты почти всегда отличаются
      на одну; сплошные скачки слух не связывает в линию;
    * **скачок требует возврата** — ровно один выразительный прыжок,
      и следующая нота идёт обратно. Прыжок без возврата читается
      как ошибка, а не как жест.
    """
    if count <= 0:
        return []

    leap_at = rng.randrange(1, max(count - 2, 2))
    degrees: list[int] = []
    pending_return = 0

    for i in range(count):
        target = _arc(shape, i, count)
        if pending_return:
            value = degrees[-1] - pending_return
            pending_return = 0
        elif i == leap_at:
            pending_return = 2
            value = round(target) + 2
        elif 0 < i < count - 1:
            # Отклонение от формы: без него мелодия звучит как глиссандо.
            # Ноль весит втрое — форма должна оставаться слышимой сквозь шум.
            value = round(target) + rng.choice((-1, 0, 0, 0, 1))
        else:
            value = round(target)
        degrees.append(max(MIN_DEGREE, min(MAX_DEGREE, value)))

    return degrees


def _land_on_chord(degrees: list[int], chords: tuple[int, ...]) -> list[int]:
    """Подвинуть последнюю ноту каждого такта на аккордовый тон.

    Сдвиг всегда минимальный — на соседнюю ступень. Мелодия от этого
    не ломается, но каждый такт получает точку опоры, а фраза — гармонию,
    которую слышно, а не только предполагают.
    """
    out = list(degrees)
    per_bar = max(len(degrees) // (PHRASE_BEATS // BEATS_PER_BAR), 1)
    for bar, chord in enumerate(chords):
        idx = min((bar + 1) * per_bar - 1, len(out) - 1)
        candidates = [
            d + 5 * o for d in degrees_on_chord(chord) for o in range(0, 2)
        ]
        allowed = [c for c in candidates if MIN_DEGREE <= c <= MAX_DEGREE]
        if allowed:
            out[idx] = min(allowed, key=lambda c: abs(c - out[idx]))
    return out


def _phrase(rng: random.Random, style: Style,
            chords: tuple[int, ...]) -> list[tuple[float, float, int]]:
    rhythm = _rhythm(rng, style.cells)
    degrees = _land_on_chord(_contour(rng, len(rhythm), style.shape), chords)
    return [(beat, length, degree) for (beat, length), degree in zip(rhythm, degrees)]


def _answer(phrase: list[tuple[float, float, int]],
            chords: tuple[int, ...]) -> list[tuple[float, float, int]]:
    """Фраза B: тот же ритм, контур сдвинут вверх и посажен на гармонию.

    Секвенция, а не новая мелодия. Слушатель узнаёт фразу A и слышит,
    что она поднялась, — это ощущение развития при нулевой цене.
    """
    lifted = [min(d + 2, MAX_DEGREE) for _, _, d in phrase]
    landed = _land_on_chord(lifted, chords)
    return [(b, ln, d) for (b, ln, _), d in zip(phrase, landed)]


def _augment(phrase: list[tuple[float, float, int]]) -> list[tuple[float, float, int]]:
    """Фраза C: ритмическая аугментация — вдвое длиннее и вдвое реже.

    Берётся каждая вторая нота и растягивается. Мотив тот же, но фраза
    дышит — после двух плотных периодов это слышно как выдох.
    """
    out: list[tuple[float, float, int]] = []
    beat = 0.0
    for i, (_, length, degree) in enumerate(phrase):
        if i % 2:
            continue
        stretched = min(length * 2.0, 4.0)
        if beat + stretched > PHRASE_BEATS:
            break
        out.append((beat, stretched, degree))
        beat += stretched
    return out


def generate(seed: int, motif_id: str, title: str, style_index: int = 0,
             progression: int | None = None) -> Motif:
    """Детерминированный мотив по сиду и характеру.

    Один и тот же сид всегда даёт одну и ту же мелодию: иначе пересборка
    музыки молча меняла бы уже одобренные треки.

    `progression` перекрывает гармонию характера. Характеров восемь, а мотивов
    нужно десять — два из них берут чужой оборот, чтобы не оказаться
    вариацией уже отобранного мотива того же характера.
    """
    style = STYLES[style_index % len(STYLES)]
    chord_index = style.progression if progression is None else progression
    chords = PROGRESSIONS[chord_index % len(PROGRESSIONS)]
    plan = PHRASE_PLANS[style.plan % len(PHRASE_PLANS)]

    rng = random.Random(seed)
    a = _phrase(rng, style, chords)
    return Motif(
        id=motif_id,
        title=title,
        style=style.name,
        seed=seed,
        chords=chords,
        plan=plan,
        phrases={"A": a, "B": _answer(a, chords), "C": _augment(a)},
    )


# Имена для отобранных мотивов. Их ровно десять — столько мотивов нужно,
# чтобы закрыть матрицу 10 × 5 жанров.
# Имя попадает в имя файла (`disco_zarya_common.ogg`), поэтому оно короткое
# и латиницей, а русское — только для человека в отчётах и галерее.
MOTIF_NAMES: tuple[tuple[str, str], ...] = (
    ("zarya", "Заря"),
    ("luchik", "Лучик"),
    ("veter", "Ветерок"),
    ("rosa", "Роса"),
    ("iskra", "Искорка"),
    ("tropa", "Тропка"),
    ("volna", "Волна"),
    ("pyltsa", "Пыльца"),
    ("koster", "Костёр"),
    ("zvezda", "Звёздочка"),
)


# --- хранение -----------------------------------------------------------------
#
# Отобранные мотивы замораживаются в файл и больше не генерируются.
# Иначе правка грамматики молча меняла бы все уже одобренные треки,
# и «пересобрать музыку» стало бы операцией, после которой нужно
# переслушивать всё заново.


def load_all(path: Path) -> list[Motif]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [Motif.from_dict(m) for m in data["motifs"]]


def save_all(motifs: list[Motif], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "_readme": [
            "Отобранные мелодические мотивы BEATROOT. Источник истины.",
            "Все мотивы в МАЖОРНОЙ пентатонике: игра про танцующих монстров",
            "для семилетних, минор задавал ей похоронный характер.",
            "Ноты записаны как [доля, длина, ступень пентатоники], а не в MIDI:",
            "жанр выбирает тембр и регистр — мотив остаётся тем же.",
            "Аккорды — в полутонах от тоники (0=I, 5=IV, 7=V, 9=vi).",
            "Файл правится руками или командой `chartgen motifs --freeze`,",
            "но НЕ перегенерируется: смена мотива меняет все его треки.",
        ],
        "motifs": [m.to_dict() for m in motifs],
    }
    path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
