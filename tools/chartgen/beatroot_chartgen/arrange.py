"""Аранжировка мотива: жанр даёт характер, грейд — напряжение.

`arrange(motif, genre, grade)` — единственная точка, где мотив превращается
в песню. Из неё же выводится чарт (`chart.generate`), поэтому сетка нот
и звук совпадают по построению, без детекции темпа.

Матрица 10 мотивов × 5 жанров × 6 грейдов = 300 треков.

**Грейд — это ремикс, а не перемотка.** Простое ускорение слышно сразу:
тембры звучат как на кассете, промотанной вперёд, а тот же рисунок ударных
на большем темпе воспринимается как ошибка сведения. Поэтому вместе с темпом
меняется сама фактура — добавляются подголоски, орнаменты, филлы, — и
легендарный трек слышится как более взрослая версия обычного, а не как
тот же трек, проигранный быстрее.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .motif import Motif
from .song import Note, Song, Track, hits

BEATS_PER_BAR = 4
PHRASE_BARS = 4
PHRASE_BEATS = PHRASE_BARS * BEATS_PER_BAR

# Порядок = порядок MonsterData.Rarity. Грейд монстра и есть сложность трека:
# отдельной оси easy/normal/hard у боевой музыки больше нет.
GRADES = ("common", "uncommon", "rare", "unique", "epic", "legendary")

# Множители темпа по грейдам: от обычного до легендарного ровно вдвое.
GRADE_BPM = (1.00, 1.15, 1.32, 1.52, 1.74, 2.00)

# Растяжение мелодии в долях — то, из-за чего удвоение темпа НЕ превращается
# в безумный раш.
#
# На верхних грейдах мотив записывается вдвое длинными нотами. Темп при этом
# вдвое выше, и мелодия звучит с той же скоростью, что на обычном, — но сетка
# под ней стала вдвое мельче, и вся освободившаяся площадь уходит на фактуру:
# филлы, подголоски, дробные ударные. Это ровно то, чем настоящий double-time
# ремикс отличается от кассеты, промотанной вперёд.
#
# Сложность для игрока при этом всё равно растёт — но растёт она по своей
# оси, через потолок плотности нот в `chart.MAX_DENSITY`, а не через темп.
GRADE_STRETCH = (1.0, 1.0, 1.0, 1.0, 1.0, 2.0)

# С какого грейда ударные переходят в half-time: бочка и снейр встают вдвое
# реже относительно сетки. Без этого удвоенный темп гонит пульс, и трек
# слышится как паника, а не как разогнавшийся танец.
#
# Дробного растяжения (×1.5) в лестнице сознательно нет. Полтора периода
# в трек не помещаются, и эпический терял целую фразу — нот у него
# оказывалось МЕНЬШЕ, чем у уникального, то есть лестница шла вниз.
# Первые пять грейдов разгоняются как есть, а на легендарном разгон
# переворачивается в double-time: это отдельный приём и отдельное событие,
# а не размазанный по трём ступеням переход.
HALF_TIME_FROM = 5

# С какого грейда жанр берёт вторую фигуру баса. Смена рисунка целиком слышна
# сразу, в отличие от добавленных нот поверх прежней партии.
BASS_VARIANT_FROM = 2

# Модуляция на верхнем грейде: тоника уходит на большую секунду вверх.
# Сдвигается тональность целиком, а не ступени мелодии, — иначе верхние ноты
# вылезли бы за диапазон мотива и контур сломался бы.
GRADE_TONIC_SHIFT = (0, 0, 0, 0, 0, 2)

# Длина трека. GDD §10.1 требует 20–35 секунд, и число тактов подбирается
# под темп: на быстром жанре периодов больше, а секунд столько же.
TARGET_SECONDS = 30.0

# Порядок фраз задаёт сам мотив (`Motif.plan`): у разных характеров он разный,
# и это слышно не меньше, чем сами ноты. Здесь только запасной вариант
# для мотивов, сохранённых до появления поля.
FALLBACK_PHRASE_ORDER = ("A", "B", "A", "C")

# Потолок числа периодов. Шесть — это уже полторы минуты на медленном жанре,
# а трек обязан быть петлёй на 20–35 секунд (GDD §10.1).
MAX_PHRASES = 6


@dataclass(frozen=True)
class GenreSpec:
    """Характер жанра. Стихия в GDD §5 — то же самое, названное для игрока."""

    element: str
    bpm: float
    lead: str
    bass: str
    lead_tonic: int
    bass_tonic: int
    kick: tuple[float, ...]
    snare: tuple[float, ...]
    snare_voice: str
    hat: tuple[float, ...]
    bass_figure: str
    gains: dict[str, float] = field(default_factory=dict)


# Базовые темпы разведены намеренно: если у всех жанров один BPM, стихии
# перестают различаться на слух, а именно по звуку игрок и должен узнавать,
# с кем встретился.
GENRES: dict[str, GenreSpec] = {
    "rock": GenreSpec(
        element="Камень", bpm=104.0, lead="guitar", bass="bass",
        lead_tonic=65, bass_tonic=41,
        kick=(0.0, 2.5), snare=(1.0, 3.0), snare_voice="snare",
        hat=(0.0, 1.0, 2.0, 3.0), bass_figure="fifths",
        gains={"kick": 1.0, "snare": 0.85, "hat": 0.4, "bass": 0.95, "lead": 1.0},
    ),
    "disco": GenreSpec(
        element="Солнце", bpm=120.0, lead="lead", bass="bass",
        lead_tonic=69, bass_tonic=45,
        kick=(0.0, 1.0, 2.0, 3.0), snare=(1.0, 3.0), snare_voice="snare",
        hat=(0.5, 1.5, 2.5, 3.5), bass_figure="octave8",
        gains={"kick": 1.0, "snare": 0.7, "hat": 0.55, "bass": 0.9, "lead": 1.0},
    ),
    "folk": GenreSpec(
        element="Листва", bpm=100.0, lead="pluck", bass="bass",
        lead_tonic=67, bass_tonic=43,
        kick=(0.0, 2.0), snare=(), snare_voice="snare",
        hat=(1.0, 3.0), bass_figure="roots2",
        gains={"kick": 0.9, "snare": 0.0, "hat": 0.3, "bass": 0.8, "lead": 1.0},
    ),
    "electro": GenreSpec(
        element="Искра", bpm=128.0, lead="saw", bass="bass",
        lead_tonic=69, bass_tonic=45,
        kick=(0.0, 1.0, 2.0, 3.0), snare=(1.0, 3.0), snare_voice="clap",
        hat=(0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75),
        bass_figure="sync16",
        gains={"kick": 1.0, "clap": 0.7, "hat": 0.45, "bass": 0.9, "lead": 1.0},
    ),
    # Ветер нейтрален в таблице стихий (GDD §5), и жанр ему нужен такой же:
    # ни тяжёлый, ни резкий. Латина взята вместо хип-хопа, который на этом
    # синтезе звучал откровенно плохо — разреженный бит и длинный саб
    # оставляли трек почти пустым, а «почти пустой» для ритм-игры
    # означает «не по чему попадать».
    "latin": GenreSpec(
        element="Ветер", bpm=108.0, lead="pluck", bass="bass",
        lead_tonic=67, bass_tonic=43,
        kick=(0.0, 1.5, 2.5), snare=(1.0, 2.5), snare_voice="clap",
        hat=(0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5), bass_figure="tumbao",
        gains={"kick": 0.95, "clap": 0.55, "hat": 0.4, "bass": 0.9, "lead": 1.0},
    ),
}


def bars_for(bpm: float, stretch: float = 1.0,
             target_seconds: float = TARGET_SECONDS) -> int:
    """Сколько тактов нужно, чтобы трек уложился около TARGET_SECONDS.

    Один такт уходит на вступление: игрок обязан услышать сетку до первой
    ноты, иначе первый такт боя читается как «игра началась без меня».

    Растяжение учитывается здесь же: на легендарном период занимает восемь
    тактов вместо четырёх, темп вдвое выше, и в секундах выходит то же самое.
    """
    beats = target_seconds * bpm / 60.0
    span = PHRASE_BEATS * stretch
    phrases = max(2, min(MAX_PHRASES, round((beats - BEATS_PER_BAR) / span)))
    return 1 + int(phrases * PHRASE_BARS * stretch)


# --- ведущая мелодия ----------------------------------------------------------


def _lead_notes(motif: Motif, spec: GenreSpec, bars: int, tonic_shift: int,
                stretch: float = 1.0) -> list[Note]:
    """Мотив, разложенный по плану фраз. Первый такт остаётся пустым.

    `stretch` растягивает и позиции, и длительности. При вдвое большем темпе
    и растяжении вдвое мелодия звучит ровно с прежней скоростью — меняется
    только то, насколько мелкая сетка оказывается под ней.
    """
    tonic = spec.lead_tonic + tonic_shift
    span = PHRASE_BEATS * stretch
    phrases = max(int((bars - 1) * BEATS_PER_BAR / span), 1)
    plan = motif.plan or FALLBACK_PHRASE_ORDER
    out: list[Note] = []
    for i in range(phrases):
        base = BEATS_PER_BAR + i * span
        for n in motif.notes(plan[i % len(plan)], tonic):
            out.append(Note(n.beat * stretch + base, n.pitch,
                            n.length * stretch, n.velocity))
    return sorted(out, key=lambda n: n.beat)


# Условия для проходящих нот по грейдам: (минимальная пауза, минимальный
# интервал в полутонах). Чем выше грейд, тем мельче промежутки и тем более
# тесные ходы он заполняет.
#
# Оба числа обязаны двигаться вместе с грейдом. Пока порог паузы был один
# на все ступени, редкий и уникальный давали чарт нота в ноту одинаковый:
# аранжировка у них различалась (октавный дубль, синкопы в басу), но ни то,
# ни другое в карту нот не попадает, и ступень получалась пустой для игрока.
#
# Промежуточное значение 0.75 тоже не годится: ритмические ячейки мотива
# набраны из долей кратных 0.5, и паузы длиной от 0.75 до 1.0 в них
# не встречаются вовсе. Поэтому уникальный отличается не паузой, а интервалом.
PASSING_RULE = {
    # Необычный: только самые длинные паузы с широким ходом. Без этой строки
    # мотивы, написанные четвертями, давали на необычном тот же чарт нота
    # в ноту, что и на обычном: фильтр целых долей у них нечего отсеивать,
    # а потолок плотности на таких мотивах не срабатывает вовсе.
    1: (2.0, 3),
    2: (1.0, 2),
    3: (0.5, 3),
    4: (0.5, 2),
    5: (0.5, 1),
}


def _passing_tones(notes: list[Note], min_gap: float, step: int = 2) -> list[Note]:
    """Проходящие ноты между соседними нотами мотива.

    Ставятся только там, где между нотами есть и время, и расстояние:
    иначе орнамент вырождается в дребезг и мотив перестаёт читаться.
    Высота — ровно посередине, поэтому линия остаётся линией.
    """
    out = list(notes)
    for a, b in zip(notes, notes[1:]):
        gap = b.beat - a.beat
        if gap < min_gap or a.pitch is None or b.pitch is None:
            continue
        if abs(b.pitch - a.pitch) < step:
            continue
        mid = a.beat + gap / 2.0
        out.append(Note(mid, (a.pitch + b.pitch) // 2, min(gap / 2.0, 0.5), 0.75))
    return sorted(out, key=lambda n: n.beat)


def _sixteenths(notes: list[Note]) -> list[Note]:
    """Раздробить длинные ноты повтором на шестнадцатую.

    Приём из чиптюна: длинная нота, повторённая коротким эхом, звучит
    настойчивее, но не добавляет новой высоты — мотив цел.
    """
    out = list(notes)
    for n in notes:
        if n.length >= 1.0 and n.pitch is not None:
            out.append(Note(n.beat + n.length - 0.25, n.pitch, 0.25, 0.6))
    return sorted(out, key=lambda n: n.beat)


def _octave_double(notes: list[Note]) -> list[Note]:
    """Дубль октавой выше, тише основного. Отдельной дорожкой.

    Именно отдельной: чарт читает только ведущую дорожку, и дубль не должен
    удваивать ноты в карте — он утолщает звук, а не задачу игрока.
    """
    return [
        Note(n.beat, n.pitch + 12, n.length, n.velocity * 0.45)
        for n in notes if n.pitch is not None
    ]


def _counter_melody(motif: Motif, spec: GenreSpec, bars: int, tonic_shift: int,
                    stretch: float = 1.0) -> list[Note]:
    """Контр-мелодия: фраза B в обращении, октавой ниже, редкими нотами.

    Обращение (движение в противоположную сторону) даёт вторую линию,
    родственную мотиву, но не спорящую с ним за внимание.
    """
    tonic = spec.lead_tonic + tonic_shift - 12
    base_notes = motif.notes("B", tonic)
    if not base_notes:
        return []
    pivot = base_notes[0].pitch or tonic

    out: list[Note] = []
    span = PHRASE_BEATS * stretch
    phrases = max(int((bars - 1) * BEATS_PER_BAR / span), 1)
    for i in range(phrases):
        if i % 2 == 0:
            continue  # через период: постоянная вторая линия утомляет
        base = BEATS_PER_BAR + i * span
        for j, n in enumerate(base_notes):
            if j % 2 or n.pitch is None:
                continue
            out.append(Note(n.beat * stretch + base, 2 * pivot - n.pitch,
                            n.length * stretch, 0.5))
    return out


# --- ритм-секция --------------------------------------------------------------


def _halve(pattern: tuple[float, ...]) -> list[float]:
    """Рисунок в half-time: те же удары, но растянутые на два такта.

    Считается по чётным тактам, поэтому вызывающий сам решает, какому такту
    что досталось. Пульс от этого вдвое реже относительно сетки — именно так
    удвоенный темп перестаёт гнать.
    """
    return [b * 2.0 for b in pattern if b * 2.0 < BEATS_PER_BAR * 2.0]


def _drums(spec: GenreSpec, bars: int, level: int) -> dict[str, list[Note]]:
    """Ударные по тактам.

    Лестница грейдов меняет рисунок, а не досыпает ноты поверх прежнего:
    добавленный хэт слышен как «тот же трек с шумом», а смена самого рисунка —
    как другая версия вещи. Поэтому здесь три разных режима, а не один
    с надбавками: базовый, уплотнённый и half-time.
    """
    kick: list[Note] = []
    snare: list[Note] = []
    hat: list[Note] = []
    tom: list[Note] = []

    half_time = level >= HALF_TIME_FROM
    hat_beats = list(spec.hat)
    if level >= 1 and len(hat_beats) < 8:
        # Хэт вдвое чаще: между каждой парой ударов появляется ещё один
        extra = [b + 0.5 for b in hat_beats]
        hat_beats = sorted(set(hat_beats) | {b % BEATS_PER_BAR for b in extra})

    for bar in range(1, bars):  # такт 0 — вступление, только хэт
        base = bar * BEATS_PER_BAR

        if half_time:
            # Бочка и снейр раскладываются на пару тактов: в чётном такте
            # первая половина рисунка, в нечётном — вторая. Сетка мельче,
            # а пульс остаётся тем же, что на обычном грейде.
            half = bar % 2
            span = BEATS_PER_BAR
            kick.extend(hits([base + b - half * span for b in _halve(spec.kick)
                              if half * span <= b < (half + 1) * span]))
            snare.extend(hits([base + b - half * span for b in _halve(spec.snare)
                               if half * span <= b < (half + 1) * span], 0.85))
        else:
            kick.extend(hits([base + b for b in spec.kick]))
            snare.extend(hits([base + b for b in spec.snare], 0.85))
            if level >= 1 and spec.snare:
                # Призрачные ноты: тихий снейр перед основным ударом
                snare.extend(hits([base + b - 0.5 for b in spec.snare if b >= 1.0], 0.3))

        hat.extend(hits([base + b for b in hat_beats], 0.6))
        if half_time:
            # Шестнадцатые в хэте — та самая мелкая сетка, ради которой
            # и удваивался темп. Без неё half-time звучит просто пусто.
            hat.extend(hits([base + b + 0.25 for b in hat_beats
                             if b + 0.25 < BEATS_PER_BAR], 0.35))

        if level >= 3 and bar % PHRASE_BARS == 0:
            fill = (2.0, 2.5, 3.0, 3.5) if level >= 5 else (3.0, 3.5)
            tom.extend(hits([base + b for b in fill], 0.7))

    hat.extend(hits(list(hat_beats), 0.35))  # вступительный такт
    return {"kick": kick, "snare": snare, "hat": hat, "tom": tom}


# Вторая фигура баса для каждого жанра. Берётся с грейда BASS_VARIANT_FROM.
#
# Смена фигуры целиком — приём ремикса, а добавление нот поверх прежней
# партии — приём мастеринга. На слух разница огромная: первое узнаётся как
# другая версия вещи, второе как та же вещь, записанная погромче.
BASS_VARIANT = {
    "octave8": "walking",
    "fifths": "octave8",
    "roots2": "fifths",
    "sync16": "octave8",
    "tumbao": "walking",
}


def _bass(spec: GenreSpec, motif: Motif, bars: int, level: int, tonic_shift: int,
          stretch: float = 1.0) -> list[Note]:
    """Бас по гармонии мотива. Фигура — часть характера жанра, а не украшение."""
    tonic = spec.bass_tonic + tonic_shift
    out: list[Note] = []
    syncopate = level >= 3
    figure = spec.bass_figure
    if level >= BASS_VARIANT_FROM:
        figure = BASS_VARIANT.get(figure, figure)

    # Гармония идёт по музыкальному времени, а не по тактам: при растяжении
    # такт становится вдвое короче относительно фразы, и аккорд, меняющийся
    # каждый такт, превратился бы в частокол.
    chord_bars = max(int(round(stretch)), 1)

    for bar in range(1, bars):
        base = bar * BEATS_PER_BAR
        # Аккорды мотива записаны в полутонах от тоники, а не ступенями
        # пентатоники: иначе субдоминанты (IV) в гармонии быть не могло.
        root = tonic + motif.chords[((bar - 1) // chord_bars) % len(motif.chords)]

        if figure == "walking":
            # Шагающий бас: основной тон, терция, квинта, секста — по одной
            # на долю. Классический приём разгона, работающий в любом жанре.
            for i, semitones in enumerate((0, 4, 7, 9)):
                out.append(Note(base + i, root + semitones, 0.9, 0.9))
        elif figure == "octave8":
            for i in range(8):
                pitch = root if i % 2 == 0 else root + 12
                out.append(Note(base + i * 0.5, pitch, 0.45, 0.9))
        elif figure == "fifths":
            for beat, pitch in ((0.0, root), (1.5, root + 7), (2.0, root), (3.0, root + 7)):
                out.append(Note(base + beat, pitch, 0.9, 0.95))
        elif figure == "roots2":
            out.append(Note(base, root, 1.8, 0.85))
            out.append(Note(base + 2.0, root + 7, 1.8, 0.8))
        elif figure == "sync16":
            pattern = (0.0, 0.75, 1.5, 1.75, 2.5, 3.25) if syncopate else (0.0, 1.5, 2.5, 3.25)
            for beat in pattern:
                out.append(Note(base + beat, root, 0.4, 0.9))
        elif figure == "tumbao":
            # Опорный тон приходит не на сильную долю, а перед ней —
            # отсюда ощущение качания, на котором держится вся латина
            for beat, pitch in ((0.0, root), (1.5, root + 7), (2.5, root + 12)):
                out.append(Note(base + beat, pitch, 0.7, 0.9))
        elif figure == "sub":
            out.append(Note(base, root, 2.4, 1.0))
            if bar % 2:
                out.append(Note(base + 2.5, root + 7, 1.2, 0.8))
        else:
            raise ValueError(f"неизвестная фигура баса: {figure}")

    if syncopate and figure in ("octave8", "fifths"):
        # Сдвиг доли назад на шестнадцатую даёт тягу вперёд, но только
        # у слабых нот: сдвинутая сильная доля читается как ошибка темпа
        out = [
            Note(n.beat + 0.25, n.pitch, n.length, n.velocity)
            if abs(n.beat - round(n.beat)) > 1e-6 else n
            for n in out
        ]
    return out


# --- сборка -------------------------------------------------------------------


def arrange(motif: Motif, genre: str, grade: str) -> Song:
    if genre not in GENRES:
        raise ValueError(f"неизвестный жанр: {genre} (есть {', '.join(GENRES)})")
    if grade not in GRADES:
        raise ValueError(f"неизвестный грейд: {grade} (есть {', '.join(GRADES)})")

    spec = GENRES[genre]
    level = GRADES.index(grade)
    bpm = spec.bpm * GRADE_BPM[level]
    stretch = GRADE_STRETCH[level]
    tonic_shift = GRADE_TONIC_SHIFT[level]
    bars = bars_for(bpm, stretch)

    lead = _lead_notes(motif, spec, bars, tonic_shift, stretch)
    if level in PASSING_RULE:
        # Порог НЕ масштабируется растяжением, и это главное место, где
        # double-time превращается из идеи в ноты. Растянутый мотив оставляет
        # вдвое большие промежутки; неподвижный порог означает, что орнамент
        # заполняет ровно ту площадь, которую растяжение и освободило.
        # Если порог растянуть вместе с мелодией, эпический и легендарный
        # получат МЕНЬШЕ нот, чем уникальный, — лестница пойдёт вниз.
        min_gap, step = PASSING_RULE[level]
        lead = _passing_tones(lead, min_gap, step)
    if level >= 5:
        # Второй проход по уже орнаментированной линии: растяжение вдвое
        # освободило вдвое больше места, и одного прохода не хватает —
        # без него легендарный получался почти вровень с эпическим.
        lead = _passing_tones(lead, min_gap, step)
        lead = _sixteenths(lead)

    drums = _drums(spec, bars, level)
    tracks = [
        Track("kick", "kick", drums["kick"], gain=spec.gains.get("kick", 1.0)),
        Track(spec.snare_voice, spec.snare_voice, drums["snare"],
              gain=spec.gains.get(spec.snare_voice, 0.8)),
        Track("hat", "hat", drums["hat"], gain=spec.gains.get("hat", 0.5)),
        Track("bass", spec.bass,
              _bass(spec, motif, bars, level, tonic_shift, stretch),
              gain=spec.gains.get("bass", 0.9)),
        Track("lead", spec.lead, lead, gain=spec.gains.get("lead", 1.0)),
    ]

    if drums["tom"]:
        tracks.append(Track("tom", "tom", drums["tom"], gain=0.6))
    if level >= 3:
        tracks.append(Track("lead_oct", spec.lead, _octave_double(lead), gain=0.5))
    if level >= 4:
        counter = _counter_melody(motif, spec, bars, tonic_shift, stretch)
        if counter:
            tracks.append(Track("counter", spec.lead, counter, gain=0.55))

    return Song(
        id=track_id(motif.id, genre, grade, bpm),
        base_id=base_id(motif.id, genre),
        grade=grade,
        title=f"{motif.title} · {spec.element}",
        genre=genre,
        bpm=bpm,
        bars=bars,
        beats_per_bar=BEATS_PER_BAR,
        lead_track="lead",
        tracks=tracks,
    )


def base_id(motif_id: str, genre: str) -> str:
    """Id трека без грейда и темпа. Именно его хранит пул монстра."""
    return f"{genre}_{motif_id}"


def track_id(motif_id: str, genre: str, grade: str, bpm: float) -> str:
    """Полное имя файла: {жанр}_{мотив}_{грейд}_{BPM}.

    Темп в имени — требование к содержимому папки: по списку файлов сразу
    видно лестницу, и перепутать `disco_zarya_common_120` с
    `disco_zarya_legendary_240` невозможно. Формула пути при этом теряется,
    поэтому игра ищет чарт по индексу каталога (`ChartLoader`), а не склейкой
    строк.
    """
    return f"{base_id(motif_id, genre)}_{grade}_{bpm:.0f}"
