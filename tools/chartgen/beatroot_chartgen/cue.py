"""Неигровая музыка: заставка, экраны усадьбы, поляны, победа и поражение.

Отличается от боевой ровно одним, но принципиальным свойством: **под неё
не играют**. Чарта у этих треков нет, попадать в них не нужно, и потолок
плотности к ним не применяется. Зато появляется требование, которого у боевой
музыки нет, — их слушают долго и не глядя, поэтому фоновые петли обязаны быть
разреженными. Всё, что имеет резкую атаку и плотный рисунок, через десять
минут в лавке начинает раздражать.

Отсюда три формы:

* **джингл** (`stinger`) — 2–4 секунды, событие: победа, поражение, вход в игру;
* **петля экрана** (`ambient`) — 25–35 секунд, фон меню, свой на каждый экран;
* **подсказка поляны** (`glade_cue`) — 4–7 секунд, характер встречи в ленте леса.

Мелодический материал берётся из тех же мотивов, что и бой (`data/motifs.json`).
Это не экономия: игрок должен узнавать музыку игры как одну музыку, а заставка,
цитирующая главный мотив, связывает разрозненные экраны в целое.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .arrange import bars_for
from .motif import Motif
from .song import Note, Song, Track, degree_to_midi, hits

BEATS_PER_BAR = 4

# Длина фоновой петли. Короче боевого трека: под меню не играют, и петля
# должна успевать вернуться к началу до того, как надоест.
AMBIENT_SECONDS = 28.0

# --- джинглы ------------------------------------------------------------------


@dataclass(frozen=True)
class StingerSpec:
    """Короткое событие. `degrees` — ступени пентатоники, `beats` — их доли."""

    id: str
    title: str
    bpm: float
    tonic: int
    degrees: tuple[int, ...]
    beats: tuple[float, ...]
    lengths: tuple[float, ...]
    voice: str = "bell"
    with_bass: bool = True


STINGERS: tuple[StingerSpec, ...] = (
    # Вход в игру цитирует «Зарю» — первый мотив матрицы. Заставка обязана
    # быть той же музыкой, что и всё остальное, иначе игра начинается
    # с чужой ноты.
    StingerSpec(
        id="boot", title="Заставка", bpm=104.0, tonic=72,
        degrees=(0, 2, 4, 3, 5), beats=(0.0, 0.5, 1.0, 2.0, 2.5),
        lengths=(0.5, 0.5, 1.0, 0.5, 2.5),
    ),
    # Победа: восходящее трезвучие и разрешение октавой выше. Ничего
    # изобретать не надо — этот жест читается без объяснений.
    StingerSpec(
        id="victory", title="Наплясался", bpm=120.0, tonic=72,
        degrees=(0, 2, 3, 5), beats=(0.0, 0.33, 0.66, 1.0),
        lengths=(0.4, 0.4, 0.4, 2.0),
    ),
    # Поражение НЕ минорное и не резкое.
    #
    # Монстр убежал, а не победил игрока (GDD §4.2.2), и худший исход встречи
    # по замыслу — «стало ближе», а не «не получилось» (§6.1). Печальный
    # аккорд здесь противоречил бы механике: дружба всё равно выросла.
    # Поэтому фраза спускается, но заканчивается на мажорной терции —
    # это «ой, в другой раз», а не «ты проиграл».
    StingerSpec(
        id="defeat", title="Убежал", bpm=96.0, tonic=72,
        degrees=(4, 3, 1, 2), beats=(0.0, 0.5, 1.0, 1.75),
        lengths=(0.5, 0.5, 0.75, 2.25), voice="pluck",
    ),
)


def stinger(spec: StingerSpec) -> Song:
    notes = [
        Note(b, degree_to_midi(d, spec.tonic), ln, 1.0)
        for b, d, ln in zip(spec.beats, spec.degrees, spec.lengths)
    ]
    tracks = [Track("lead", spec.voice, notes, gain=1.0)]

    if spec.with_bass:
        # Одна длинная нота под всей фразой: джингл должен иметь опору,
        # но вторая мелодия в двух секундах уже толкается с первой.
        end = max(b + ln for b, ln in zip(spec.beats, spec.lengths))
        tracks.append(Track("bass", "pad",
                            [Note(0.0, degree_to_midi(0, spec.tonic - 24), end, 0.9)],
                            gain=0.8))

    total = max(b + ln for b, ln in zip(spec.beats, spec.lengths))
    return Song(
        id=f"cue_{spec.id}", base_id=f"cue_{spec.id}", grade="",
        title=spec.title, genre="cue", bpm=spec.bpm,
        bars=max(int(-(-total // BEATS_PER_BAR)), 1),
        beats_per_bar=BEATS_PER_BAR, lead_track="lead", tracks=tracks,
    )


# --- петли экранов ------------------------------------------------------------


@dataclass(frozen=True)
class ScreenSpec:
    """Фоновая петля одного экрана.

    `motif` и `genre` разведены между экранами намеренно: игрок обязан
    понимать, где он находится, не глядя на экран. Две одинаковые петли
    на соседних экранах — это не экономия, а потерянная навигация.
    """

    id: str
    title: str
    motif: str
    bpm: float
    tonic: int
    lead: str
    pulse: str          # "none" | "soft" | "walk"
    density: float = 0.5   # доля нот мотива, которая доживает до петли


SCREENS: tuple[ScreenSpec, ...] = (
    ScreenSpec("lobby", "Двор усадьбы", "zarya", 96.0, 72, "pluck", "soft"),
    ScreenSpec("farm", "Огород", "luchik", 84.0, 69, "pluck", "none", density=0.4),
    ScreenSpec("collection", "Дом защитников", "volna", 92.0, 71, "lead", "soft"),
    ScreenSpec("inventory", "Амбар", "rosa", 88.0, 69, "pluck", "none", density=0.4),
    ScreenSpec("merchant", "Лавка", "tropa", 104.0, 72, "pluck", "walk", density=0.6),
    ScreenSpec("shop", "Наряды", "iskra", 112.0, 74, "bell", "walk", density=0.6),
    ScreenSpec("run_feed", "Лес", "veter", 100.0, 70, "lead", "soft", density=0.55),
    ScreenSpec("taming", "Приручение", "zvezda", 80.0, 72, "bell", "none", density=0.35),
)


def ambient(spec: ScreenSpec, motif: Motif) -> Song:
    """Фоновая петля экрана: подложка, разреженная мелодия, лёгкий пульс."""
    # Число тактов считается от темпа, а не задаётся константой. С фиксированными
    # семнадцатью тактами медленные экраны выходили на пятьдесят секунд —
    # вдвое длиннее петли, которую требует GDD §10.1, и вдвое дольше до того
    # места, где игрок наконец услышит, что музыка повторяется.
    bars = bars_for(spec.bpm, target_seconds=AMBIENT_SECONDS)
    plan = motif.plan or ("A", "B", "A", "C")
    phrases = (bars - 1) // 4

    lead: list[Note] = []
    for i in range(phrases):
        base = BEATS_PER_BAR + i * 16
        phrase = motif.notes(plan[i % len(plan)], spec.tonic)
        # Прореживание по шагу, а не случайное: мелодия обязана остаться
        # узнаваемой. Случайный выбор рвал бы контур в разных местах
        # на каждом периоде, и петля переставала бы читаться как петля.
        step = max(int(round(1.0 / max(spec.density, 0.05))), 1)
        for j, n in enumerate(phrase):
            if j % step:
                continue
            lead.append(Note(n.beat + base, n.pitch, max(n.length, 1.0), 0.85))

    pad: list[Note] = []
    for bar in range(bars):
        chord = motif.chords[bar % len(motif.chords)]
        root = spec.tonic - 12 + chord
        for semitones in (0, 4, 7):
            pad.append(Note(bar * BEATS_PER_BAR, root + semitones,
                            float(BEATS_PER_BAR), 0.55))

    tracks = [
        Track("pad", "pad", pad, gain=1.0),
        Track("lead", spec.lead, lead, gain=0.85),
    ]

    if spec.pulse != "none":
        bass: list[Note] = []
        hat: list[Note] = []
        for bar in range(1, bars):
            base = bar * BEATS_PER_BAR
            root = spec.tonic - 24 + motif.chords[bar % len(motif.chords)]
            if spec.pulse == "walk":
                for i, semitones in enumerate((0, 4, 7, 4)):
                    bass.append(Note(base + i, root + semitones, 0.9, 0.75))
                hat.extend(hits([base + b for b in (0.5, 1.5, 2.5, 3.5)], 0.3))
            else:
                bass.append(Note(base, root, 1.8, 0.7))
                bass.append(Note(base + 2.0, root + 7, 1.8, 0.65))
                hat.extend(hits([base + b for b in (1.0, 3.0)], 0.22))
        tracks.append(Track("bass", "bass", bass, gain=0.7))
        tracks.append(Track("hat", "hat", hat, gain=0.4))

    return Song(
        id=f"ui_{spec.id}", base_id=f"ui_{spec.id}", grade="",
        title=spec.title, genre="ambient", bpm=spec.bpm, bars=bars,
        beats_per_bar=BEATS_PER_BAR, lead_track="lead", tracks=tracks,
    )


# --- подсказки полян ----------------------------------------------------------


@dataclass(frozen=True)
class GladeSpec:
    """Характер типа поляны и пять его вариантов.

    Варианты выписаны нотами, а не получены транспозицией одной фразы.
    Транспозиция была первой попыткой и оказалась пустой: пять раз одна
    и та же фраза на разной высоте — это по-прежнему одна фраза, и лента
    начинала повторяться ровно так же быстро, как с единственным звуком.

    Общим у вариантов остаётся ЖЕСТ: бой всегда идёт вверх и повисает,
    костёр всегда оседает к тонике, встреча всегда обрывается на
    неустойчивой ступени. По жесту игрок и узнаёт, что попалось, —
    конкретные ноты для этого не нужны.
    """

    id: str
    title: str
    bpm: float
    tonic: int
    voice: str
    variants: tuple[tuple[tuple[int, ...], tuple[float, ...]], ...]
    bass_degree: int = 0
    gains: dict[str, float] = field(default_factory=dict)


GLADES: tuple[GladeSpec, ...] = (
    # Бой сюда НЕ входит: встреча с монстром — это не подсказка, а сцена.
    # Игрок стоит перед карточкой и решает, ввязываться ли, и четыре ноты
    # на две секунды в этот момент читаются как звонок в дверь, а не как
    # «впереди кто-то большой». Ему отведён отдельный генератор ниже.
    #
    # Дикий куст: лёгкий росчерк вверх, ничего не обещает и не угрожает.
    GladeSpec("wild_bush", "Дикий куст", 104.0, 74, "pluck", bass_degree=2, variants=(
        ((2, 4, 5, 4), (0.4, 0.4, 0.4, 1.2)),
        ((3, 5, 4, 5), (0.3, 0.3, 0.6, 1.2)),
        ((2, 3, 5, 6), (0.4, 0.2, 0.4, 1.4)),
        ((4, 3, 5, 4), (0.3, 0.5, 0.4, 1.2)),
        ((2, 5, 4, 6), (0.5, 0.3, 0.3, 1.3)),
    )),
    # Костёр: спуск к тонике и покой. Это место, где отдыхают.
    GladeSpec("campfire", "Костёр", 76.0, 69, "pad", bass_degree=0, variants=(
        ((4, 3, 1, 0), (0.75, 0.75, 0.75, 2.0)),
        ((5, 3, 2, 0), (0.5, 1.0, 0.75, 2.0)),
        ((3, 2, 1, 0), (1.0, 0.5, 0.75, 2.0)),
        ((4, 2, 3, 0), (0.75, 0.5, 1.0, 2.0)),
        ((6, 4, 2, 0), (0.5, 0.75, 1.0, 2.0)),
    )),
    # Встреча: фраза обрывается на неустойчивой ступени — музыкальный знак
    # вопроса. Что именно попалось, игрок ещё не знает.
    GladeSpec("encounter", "Встреча", 92.0, 72, "bell", bass_degree=0, variants=(
        ((0, 3, 2, 4), (0.5, 0.5, 0.75, 1.25)),
        ((1, 2, 4, 3), (0.5, 0.75, 0.5, 1.25)),
        ((0, 4, 1, 3), (0.75, 0.5, 0.5, 1.25)),
        ((2, 0, 3, 4), (0.5, 0.5, 0.5, 1.5)),
        ((1, 4, 2, 6), (0.5, 0.75, 0.75, 1.0)),
    )),
)

GLADE_VARIANT_COUNT = 5


def glade_cue(spec: GladeSpec, variant: int) -> Song:
    degrees, rhythm = spec.variants[variant % len(spec.variants)]
    tonic = spec.tonic

    beat = 0.0
    notes: list[Note] = []
    for degree, length in zip(degrees, rhythm):
        notes.append(Note(beat, degree_to_midi(degree, tonic), length, 1.0))
        beat += length

    total = beat
    tracks = [
        Track("lead", spec.voice, notes, gain=1.0),
        Track("bass", "pad",
              [Note(0.0, degree_to_midi(spec.bass_degree, tonic - 24), total, 0.85)],
              gain=0.7),
    ]
    return Song(
        id=f"glade_{spec.id}_{variant + 1}", base_id=f"glade_{spec.id}",
        grade="", title=f"{spec.title} {variant + 1}", genre="cue",
        bpm=spec.bpm, bars=max(int(-(-total // BEATS_PER_BAR)), 1),
        beats_per_bar=BEATS_PER_BAR, lead_track="lead", tracks=tracks,
    )


# --- встреча с монстром -------------------------------------------------------
#
# Отдельная форма, а не удлинённая подсказка поляны. Карточка боя — это сцена:
# игрок смотрит на монстра и решает, ввязываться ли. Значит нужна музыка
# с развитием — вступление, нарастание, кульминация и возврат в петлю.
#
# **Угроза здесь делается НЕ минором.** Во-первых, все треки игры мажорные.
# Во-вторых, аудитория 7+, и по GDD монстр «сбивается с ритма», а не получает
# урон, — пугать ребёнка нечем и незачем. Нужное чувство — «ого, кто-то
# большой», а не «страшно». Оно набирается четырьмя приёмами, каждый из
# которых внутри мажора:
#
#   * низкий регистр и настойчивый пульс — «оно приближается»;
#   * педальный тон под меняющейся гармонией — напряжение без диссонанса;
#   * восходящая секвенция — «оно всё ближе»;
#   * трезвучия vi и ii — минорные аккорды ВНУТРИ мажорной тональности.
#     Тональность остаётся мажорной, а краска темнеет.

# Раскладка восьми тактов. Выписана таблицей, а не выведена арифметикой:
# драматургия встречи — это дизайнерское решение, и его должно быть видно.
#
#   такт 0     педаль и один удар колокольчика — «оно тебя заметило»
#   такты 1–2  входит пульс, мелодии ещё нет — «оно приближается»
#   такты 3–4  мелодия, первая половина фразы мотива
#   такты 5–6  та же фраза ступенью выше — восходящая секвенция
#   такт  7    кульминация: верхний тон, сдвоенный том, обрыв в петлю
ENCOUNTER_BARS = 8
ENCOUNTER_MELODY_FROM = 3
ENCOUNTER_LIFT_FROM = 5
ENCOUNTER_LIFT = 2

# Сколько мелодий встречи держать в ротации. Десять — чтобы за забег
# из тридцати полян одна и та же не попалась дважды подряд.
ENCOUNTER_COUNT = 10


@dataclass(frozen=True)
class EncounterSpec:
    """Характер встречи. Пять характеров на десять мотивов."""

    name: str
    bpm: float
    lead: str
    kick: tuple[float, ...]
    accent: tuple[float, ...]
    bass: str          # "drone" | "pulse" | "run" | "stab"
    tonic: int = 62


ENCOUNTERS: tuple[EncounterSpec, ...] = (
    EncounterSpec("нарастание", 112.0, "guitar",
                  kick=(0.0, 2.0), accent=(3.5,), bass="pulse"),
    EncounterSpec("удары", 104.0, "guitar",
                  kick=(0.0, 1.5), accent=(2.0, 3.0), bass="stab"),
    EncounterSpec("педаль", 120.0, "saw",
                  kick=(0.0, 1.0, 2.0, 3.0), accent=(1.5,), bass="drone"),
    EncounterSpec("погоня", 126.0, "saw",
                  kick=(0.0, 0.75, 1.5, 2.5), accent=(3.75,), bass="run"),
    EncounterSpec("фанфара", 108.0, "guitar",
                  kick=(0.0, 2.5), accent=(1.0, 3.0), bass="pulse"),
)

# Гармония встречи: тоника, затем минорные трезвучия внутри мажора,
# и возврат на доминанту — чтобы петля тянула обратно к началу,
# а не разрешалась и не останавливалась.
ENCOUNTER_CHORDS = (0, 9, 5, 7, 0, 9, 2, 7)   # I vi IV V I vi ii V


def _encounter_bass(spec: EncounterSpec, bar: int, root: int) -> list[Note]:
    base = bar * BEATS_PER_BAR
    if spec.bass == "drone":
        # Педаль: тоника держится под меняющейся гармонией. Напряжение
        # берётся из расхождения баса и аккорда, а не из диссонанса.
        return [Note(base, spec.tonic - 24, float(BEATS_PER_BAR), 0.95)]
    if spec.bass == "pulse":
        return [Note(base + i, root, 0.8, 0.9) for i in range(BEATS_PER_BAR)]
    if spec.bass == "run":
        return [Note(base + i * 0.5, root + (0 if i % 2 == 0 else 7), 0.45, 0.85)
                for i in range(BEATS_PER_BAR * 2)]
    if spec.bass == "stab":
        return [Note(base, root, 0.4, 1.0), Note(base + 1.5, root, 0.4, 0.9),
                Note(base + 2.5, root + 7, 0.9, 0.85)]
    raise ValueError(f"неизвестная фигура баса встречи: {spec.bass}")


def encounter(motif: Motif, spec: EncounterSpec, index: int) -> Song:
    """Мелодия встречи с монстром: вступление, нарастание, кульминация, петля."""
    tonic = spec.tonic
    plan = motif.plan or ("A", "B", "A", "C")

    lead: list[Note] = []
    counter: list[Note] = []
    bass: list[Note] = []
    kick: list[Note] = []
    tom: list[Note] = []
    bell: list[Note] = []
    pad: list[Note] = []

    for bar in range(ENCOUNTER_BARS):
        base = bar * BEATS_PER_BAR
        chord = ENCOUNTER_CHORDS[bar % len(ENCOUNTER_CHORDS)]
        root = tonic - 24 + chord

        # Подложка трезвучиями идёт с самого начала: она и есть та краска,
        # которая темнеет на vi и ii, оставаясь в мажоре.
        for semitones in (0, 3 if chord in (9, 2) else 4, 7):
            pad.append(Note(base, tonic - 12 + chord + semitones,
                            float(BEATS_PER_BAR), 0.5))

        if bar == 0:
            bass.append(Note(base, tonic - 24, float(BEATS_PER_BAR), 0.9))
            bell.append(Note(base + 2.0, tonic + 12, 2.0, 0.8))
            continue

        bass.extend(_encounter_bass(spec, bar, root))
        kick.extend(hits([base + b for b in spec.kick]))
        tom.extend(hits([base + b for b in spec.accent], 0.75))

        if bar >= ENCOUNTER_MELODY_FROM:
            lift = ENCOUNTER_LIFT if bar >= ENCOUNTER_LIFT_FROM else 0
            phrase = motif.notes(plan[0], tonic + lift)
            # Такт мелодии берётся из соответствующего такта фразы мотива:
            # такт 3 встречи — первый такт фразы, такт 6 — четвёртый.
            # Так фраза звучит целиком, а не первыми четырьмя нотами четырежды.
            start = (bar - ENCOUNTER_MELODY_FROM) * BEATS_PER_BAR
            for n in phrase:
                if not start <= n.beat < start + BEATS_PER_BAR:
                    continue
                lead.append(Note(base + (n.beat - start), n.pitch,
                                 min(n.length, 1.0), 0.9))

        # Кульминация: последний такт держит верхний тон и обрывается,
        # чтобы петля тянула обратно, а не заканчивалась.
        if bar == ENCOUNTER_BARS - 1:
            counter.append(Note(base, tonic + 12 + 7, 2.5, 0.85))
            tom.extend(hits([base + 3.0, base + 3.5], 0.9))

    tracks = [
        Track("pad", "pad", pad, gain=0.8),
        Track("bass", "sub", bass, gain=1.0),
        Track("kick", "kick", kick, gain=1.0),
        Track("tom", "tom", tom, gain=0.7),
        Track("bell", "bell", bell, gain=0.6),
        Track("lead", spec.lead, lead, gain=0.95),
    ]
    if counter:
        tracks.append(Track("counter", "guitar", counter, gain=0.7))

    return Song(
        id=f"glade_battle_{index + 1}", base_id="glade_battle", grade="",
        title=f"Встреча · {spec.name}", genre="cue", bpm=spec.bpm,
        bars=ENCOUNTER_BARS, beats_per_bar=BEATS_PER_BAR,
        lead_track="lead", tracks=tracks,
    )

