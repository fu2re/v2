"""«Первый Росток» — тестовый трек для отладки ритм-ядра.

Диско, 120 BPM, 17 тактов (34 сек). Бочка на каждую долю даёт максимально
однозначную сетку: если игрок промахивается по такому треку, проблема в коде,
а не в музыке. Мелодия — ля-минорная пентатоника над Am–C–G–Am.
"""

from ..song import A3, A4, C4, C5, D5, E5, G4, G5, Note, Song, Track, hits, repeat, shift

BPM = 120.0
BPB = 4
BARS = 17
G3 = 55

# --- мелодические фразы, относительные доли 0..15 ----------------------------

PHRASE_A = [
    Note(0.0, A4, 0.5), Note(0.5, C5, 0.5), Note(1.0, D5, 0.5),
    Note(1.5, E5, 1.0), Note(2.5, D5, 0.5), Note(3.0, C5, 1.0),

    Note(4.0, E5, 0.5), Note(4.5, D5, 0.5), Note(5.0, C5, 0.5),
    Note(5.5, A4, 1.5), Note(7.0, C5, 1.0),

    Note(8.0, A4, 0.5), Note(8.5, C5, 0.5), Note(9.0, D5, 0.5),
    Note(9.5, E5, 1.0), Note(10.5, G5, 0.5), Note(11.0, E5, 1.0),

    Note(12.0, D5, 0.5), Note(12.5, C5, 0.5), Note(13.0, A4, 1.0),
    Note(14.0, C5, 0.5), Note(14.5, D5, 1.5),
]

PHRASE_B = [
    Note(0.0, E5, 0.5), Note(0.5, G5, 0.5), Note(1.0, E5, 0.5),
    Note(1.5, D5, 0.5), Note(2.0, C5, 1.0), Note(3.0, D5, 1.0),

    Note(4.0, E5, 0.5), Note(4.5, C5, 0.5), Note(5.0, A4, 1.0),
    Note(6.0, G4, 0.5), Note(6.5, A4, 1.5),

    Note(8.0, E5, 0.5), Note(8.5, G5, 0.5), Note(9.0, G5, 0.5),
    Note(9.5, E5, 1.0), Note(10.5, D5, 0.5), Note(11.0, C5, 1.0),

    Note(12.0, D5, 0.5), Note(12.5, E5, 0.5), Note(13.0, D5, 0.5),
    Note(13.5, C5, 0.5), Note(14.0, A4, 2.0),
]

PHRASE_C = [
    Note(0.0, A4, 0.5), Note(0.5, C5, 0.5), Note(1.0, E5, 0.5),
    Note(1.5, G5, 0.5), Note(2.0, E5, 0.5), Note(2.5, D5, 0.5), Note(3.0, C5, 1.0),

    Note(4.0, D5, 0.5), Note(4.5, E5, 0.5), Note(5.0, D5, 0.5),
    Note(5.5, C5, 0.5), Note(6.0, A4, 2.0),

    Note(8.0, C5, 0.5), Note(8.5, D5, 0.5), Note(9.0, E5, 0.5),
    Note(9.5, G5, 0.5), Note(10.0, G5, 0.5), Note(10.5, E5, 0.5), Note(11.0, D5, 1.0),

    Note(12.0, C5, 0.5), Note(12.5, A4, 0.5), Note(13.0, C5, 0.5),
    Note(13.5, D5, 0.5), Note(14.0, A4, 2.0),
]

# Аранжировка: такт 1 — вступление без мелодии, дальше A B A C
LEAD = shift(PHRASE_A, 4) + shift(PHRASE_B, 20) + shift(PHRASE_A, 36) + shift(PHRASE_C, 52)

# --- ритм-секция -------------------------------------------------------------

# Бочка на каждую долю — та самая «сетка», по которой игрок ловит темп
KICK = repeat(hits([0.0, 1.0, 2.0, 3.0]), BARS, BPB)
SNARE = repeat(hits([1.0, 3.0], 0.85), BARS, BPB)
HAT = repeat(hits([0.5, 1.5, 2.5, 3.5], 0.6), BARS, BPB)

# Бас восьмыми с прыжком на октаву — диско-фигура.
# Гармония Am–C–G–Am повторяется каждые 4 такта.
_ROOTS = [A3, C4, G3, A3]


def _bass() -> list[Note]:
    out: list[Note] = []
    for bar in range(BARS):
        root = _ROOTS[bar % 4]
        base = bar * BPB
        for i in range(8):
            pitch = root if i % 2 == 0 else root + 12
            out.append(Note(base + i * 0.5, pitch, 0.45, 0.9))
    return out


SONG = Song(
    id="demo_disco",
    title="Первый Росток",
    genre="disco",
    bpm=BPM,
    bars=BARS,
    beats_per_bar=BPB,
    lead_track="lead",
    tracks=[
        Track("kick", "kick", KICK, gain=1.0),
        Track("snare", "snare", SNARE, gain=0.7),
        Track("hat", "hat", HAT, gain=0.55),
        Track("bass", "bass", _bass(), gain=0.9),
        Track("lead", "lead", LEAD, gain=1.0),
    ],
)
