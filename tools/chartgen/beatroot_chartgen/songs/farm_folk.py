"""«Тёплая грядка» — трек фермы.

Фолк, 100 BPM, 12 тактов (28.8 сек). Медленнее и мягче боевого: ферма — это
передышка между забегами, и музыка обязана это сообщать раньше, чем игрок
прочитает хоть слово. Без малого барабана, только мягкий пульс и бас.
"""

from ..song import A3, A4, C4, C5, D5, E4, E5, G4, G5, Note, Song, Track, hits, repeat, shift

BPM = 100.0
BPB = 4
BARS = 12
G3 = 55

# Мелодия качается по пентатонике широкими шагами — колыбельная, а не хук
PHRASE_A = [
    Note(0.0, A4, 1.0), Note(1.0, C5, 1.0), Note(2.0, E5, 1.5),
    Note(3.5, D5, 0.5),

    Note(4.0, C5, 1.0), Note(5.0, A4, 1.0), Note(6.0, G4, 2.0),

    Note(8.0, C5, 1.0), Note(9.0, D5, 1.0), Note(10.0, E5, 1.0),
    Note(11.0, G5, 1.0),

    Note(12.0, E5, 1.5), Note(13.5, D5, 0.5), Note(14.0, C5, 2.0),
]

PHRASE_B = [
    Note(0.0, E5, 1.0), Note(1.0, D5, 1.0), Note(2.0, C5, 1.0),
    Note(3.0, A4, 1.0),

    Note(4.0, G4, 1.5), Note(5.5, A4, 0.5), Note(6.0, C5, 2.0),

    Note(8.0, D5, 1.0), Note(9.0, C5, 1.0), Note(10.0, A4, 1.5),
    Note(11.5, G4, 0.5),

    Note(12.0, A4, 3.0),
]

# Такт 1 — вступление без мелодии, дальше A, потом B
LEAD = shift(PHRASE_A, 4) + shift(PHRASE_B, 20)

# Мягкий пульс: бочка на 1 и 3, тихий хэт на слабые доли, малого барабана нет
KICK = repeat(hits([0.0, 2.0], 0.85), BARS, BPB)
HAT = repeat(hits([1.5, 3.5], 0.4), BARS, BPB)

# Гармония Am–C–G–Am, бас половинными — спокойно, без диско-прыжков
_ROOTS = [A3, C4, G3, A3]


def _bass() -> list[Note]:
    out: list[Note] = []
    for bar in range(BARS):
        root = _ROOTS[bar % 4]
        base = bar * BPB
        out.append(Note(base, root, 1.8, 0.8))
        out.append(Note(base + 2.0, root + 7, 1.8, 0.7))
    return out


SONG = Song(
    id="farm_folk",
    title="Тёплая грядка",
    genre="folk",
    bpm=BPM,
    bars=BARS,
    beats_per_bar=BPB,
    lead_track="lead",
    tracks=[
        Track("kick", "kick", KICK, gain=0.8),
        Track("hat", "hat", HAT, gain=0.35),
        Track("bass", "bass", _bass(), gain=0.85),
        Track("lead", "lead", LEAD, gain=0.95),
    ],
)
