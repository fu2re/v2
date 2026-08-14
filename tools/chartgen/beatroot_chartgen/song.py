"""Модель песни.

Песня описана как данные, а не как аудиофайл. Из одного описания рендерится
и звук, и карта нот — поэтому сетка совпадает идеально, без детекции темпа.
Это главная причина существования синтезированных треков в проекте.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Названия инструментов, которые понимает synth.py
PERCUSSION = ("kick", "snare", "hat")
TONAL = ("bass", "lead")


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
# Пентатоника выбрана намеренно: почти любое сочетание её ступеней звучит
# согласованно, что критично когда мелодии генерируются, а не сочиняются.
A3, C4, D4, E4, G4 = 57, 60, 62, 64, 67
A4, C5, D5, E5, G5 = 69, 72, 74, 76, 79
