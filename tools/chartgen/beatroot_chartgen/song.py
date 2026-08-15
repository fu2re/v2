"""Модель песни.

Песня описана как данные, а не как аудиофайл. Из одного описания рендерится
и звук, и карта нот — поэтому сетка совпадает идеально, без детекции темпа.
Это главная причина существования синтезированных треков в проекте.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Названия инструментов, которые понимает synth.py
PERCUSSION = ("kick", "snare", "hat", "clap", "tom")
TONAL = ("bass", "lead", "guitar", "pluck", "saw", "sub", "pad", "bell")


@dataclass(frozen=True)
class Note:
    """Нота на дорожке. Позиция и длина — в долях, не в секундах."""

    beat: float
    pitch: int | None = None  # MIDI-номер; None для перкуссии
    length: float = 0.5
    velocity: float = 1.0


@dataclass
class Track:
    name: str
    instrument: str
    notes: list[Note] = field(default_factory=list)
    gain: float = 1.0


@dataclass
class Song:
    id: str
    title: str
    genre: str
    bpm: float
    bars: int
    beats_per_bar: int = 4
    tracks: list[Track] = field(default_factory=list)
    lead_track: str = "lead"
    ## Имя трека без грейда и сам грейд.
    ##
    ## Аудио у каждого грейда своё (`disco_zarya_rare.ogg`), а чарт лежит как
    ## `charts/<base_id>_<grade>.json` — под формулу ChartLoader.load_by_id.
    ## Отсюда два поля вместо одного: из `id` имя чарта не восстановить,
    ## грейд склеился бы дважды.
    base_id: str = ""
    grade: str = ""

    @property
    def chart_id(self) -> str:
        return self.base_id or self.id

    @property
    def total_beats(self) -> float:
        return self.bars * self.beats_per_bar

    @property
    def duration(self) -> float:
        return self.total_beats * 60.0 / self.bpm

    @property
    def sec_per_beat(self) -> float:
        return 60.0 / self.bpm

    def track(self, name: str) -> Track | None:
        return next((t for t in self.tracks if t.name == name), None)


# --- помощники для сборки паттернов ------------------------------------------


def repeat(pattern: list[Note], times: int, every: float) -> list[Note]:
    """Повторить группу нот `times` раз с шагом `every` долей."""
    out: list[Note] = []
    for i in range(times):
        shift = i * every
        out.extend(
            Note(n.beat + shift, n.pitch, n.length, n.velocity) for n in pattern
        )
    return out


def shift(pattern: list[Note], by: float) -> list[Note]:
    """Сдвинуть группу нот на `by` долей."""
    return [Note(n.beat + by, n.pitch, n.length, n.velocity) for n in pattern]


def hits(beats: list[float], velocity: float = 1.0) -> list[Note]:
    """Перкуссионные удары на перечисленных долях."""
    return [Note(b, None, 0.1, velocity) for b in beats]


# Ноты минорной пентатоники в MIDI (A=69 это A4).
# Оставлены для двух ручных треков, demo_disco и farm_folk: они написаны
# в ля-миноре, и переписывать выверенные обучение и ферму незачем.
G3 = 55
A3, C4, D4, E4, G4 = 57, 60, 62, 64, 67
A4, C5, D5, E5, G5 = 69, 72, 74, 76, 79

# Ступени МАЖОРНОЙ пентатоники внутри октавы, от тоники.
#
# Пентатоника выбрана намеренно: почти любое сочетание её ступеней звучит
# согласованно, что критично когда мелодии генерируются, а не сочиняются.
# Мажорная, а не минорная, — потому что игра про танцующих монстров
# для семилетних, а минор ей задавал похоронный характер вне зависимости
# от темпа и аранжировки.
#
# Генератору мотивов нужна не россыпь констант, а лестница, по которой
# можно ходить на «шаг вверх» и «шаг вниз» — отсюда отдельный список.
PENTATONIC_STEPS = (0, 2, 4, 7, 9)
STEPS_PER_OCTAVE = len(PENTATONIC_STEPS)
TONIC = 60  # C4


def degree_to_midi(degree: int, tonic: int = TONIC) -> int:
    """Ступень пентатоники в MIDI. Ступень 0 — тоника, 5 — она же октавой выше.

    Отрицательные ступени спускаются ниже тоники: `degree_to_midi(-1)` — это
    ля под до, а не ошибка. Так контур мелодии описывается одним целым
    числом, и шаг вверх — это всегда `+1`, в какой бы октаве он ни случился.
    """
    octave, step = divmod(degree, STEPS_PER_OCTAVE)
    return tonic + 12 * octave + PENTATONIC_STEPS[step]


# Аккорды записаны в ПОЛУТОНАХ от тоники, а не ступенями пентатоники.
#
# Иначе половина мажорных оборотов недоступна: субдоминанта (IV, +5) в
# пентатонику не входит вовсе, и гармония схлопывалась бы до трёх аккордов.
# Бас берёт основной тон в полутонах, мелодия остаётся в пентатонике —
# это ровно то, как пентатонику и используют поверх мажорной гармонии.
I, ii, iii, IV, V, vi = 0, 2, 4, 5, 7, 9

# Мажорные обороты. Разные мотивы берут разные — гармония даёт мелодии
# характер не меньше, чем сам контур.
PROGRESSIONS: tuple[tuple[int, ...], ...] = (
    (I, V, vi, IV),
    (I, vi, IV, V),
    (vi, IV, I, V),
    (I, IV, V, I),
    (I, iii, IV, V),
    (I, V, IV, V),
    (IV, I, V, vi),
    (I, ii, V, I),
)
DEFAULT_CHORDS = PROGRESSIONS[0]


def chord_tones(chord: int) -> tuple[int, ...]:
    """Тоны мажорного трезвучия от аккорда, в полутонах от тоники."""
    return (chord % 12, (chord + 4) % 12, (chord + 7) % 12)


def degrees_on_chord(chord: int) -> tuple[int, ...]:
    """Ступени пентатоники внутри октавы, попадающие в трезвучие аккорда.

    Список никогда не пуст: у любого диатонического аккорда мажорная
    пентатоника содержит хотя бы два его тона.
    """
    tones = chord_tones(chord)
    return tuple(i for i, s in enumerate(PENTATONIC_STEPS) if s % 12 in tones)
