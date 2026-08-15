"""Карта нот: модель, генерация из песни, проверка играбельности, экспорт."""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

from .song import Song

NOTE_TYPES = ("beat", "skill", "shield", "snack", "attack")

# Серия — это связка нот без длинной паузы. Атака ЗАВЕРШАЕТ серию: следующая
# нота начинает новую. Поэтому в длинной связке атак несколько, а не одна.
# Пауза длиннее половины такта обрывает связку. Одна доля была слишком строгой:
# на спокойных треках с редкими нотами серии не набирались вовсе, и чарт
# оставался без единой атаки — то есть непроходимым.
SERIES_GAP = 2.0
# Короче — не серия, а обрывок; атака после такого не заслужена.
MIN_SERIES_NOTES = 3
# Через столько нот связку пора венчать ударом, даже если пауза не подошла.
# Без этого на плотных чартах вся песня складывалась в одну серию с единственной
# атакой в конце, и монстра было нечем побеждать.
#
# Значение разное по сложностям НАМЕРЕННО. Монстр одинаково крепкий на всех
# уровнях, поэтому число атак должно быть примерно равным: иначе на лёгком
# чарте с вдвое меньшим числом нот его просто нечем добить. Сложность меняет
# то, насколько трудно вести серию чисто, а не то, сколько урона доступно.
TARGET_SERIES_NOTES = {
    "easy": 4,
    "normal": 6,
    "hard": 8,
}

# Максимальная плотность нот в секунду. Ограничение из GDD §10.3 —
# верхняя граница подобрана под то, что успевает семилетний ребёнок.
MAX_DENSITY = {"easy": 2.0, "normal": 4.0, "hard": 8.0}

# Минимальный разрыв между щитами в долях. Меньше — игрок физически не успевает.
MIN_SHIELD_GAP = 2.0

# За сколько долей до щита монстр обязан начать замах.
WINDUP_LEAD = 2.0


@dataclass(frozen=True)
class ChartNote:
    beat: float
    type: str = "beat"


@dataclass(frozen=True)
class PatternEvent:
    """Событие танца монстра. `windup` — видимый замах перед атакой."""

    beat: float
    action: str


@dataclass
class Chart:
    id: str
    genre: str
    bpm: float
    difficulty: str
    duration: float
    audio: str
    beats_per_bar: int = 4
    offset: float = 0.0
    notes: list[ChartNote] = field(default_factory=list)
    monster_pattern: list[PatternEvent] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = asdict(self)
        d["notes"] = sorted(d["notes"], key=lambda n: n["beat"])
        d["monster_pattern"] = sorted(d["monster_pattern"], key=lambda e: e["beat"])
        return d

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(self.to_dict(), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    @classmethod
    def load(cls, path: Path) -> Chart:
        d = json.loads(path.read_text(encoding="utf-8"))
        notes = [ChartNote(**n) for n in d.pop("notes", [])]
        pattern = [PatternEvent(**e) for e in d.pop("monster_pattern", [])]
        return cls(notes=notes, monster_pattern=pattern, **d)


def generate(song: Song, difficulty: str = "normal") -> Chart:
    """Вывести чарт из мелодии песни.

    Ноты берутся из ведущей дорожки, а не из анализа аудио: источник тот же,
    что и у звука, поэтому попадание в сетку точное по построению.
    """
    if difficulty not in MAX_DENSITY:
        raise ValueError(f"неизвестная сложность: {difficulty}")

    bpb = song.beats_per_bar
    lead = song.track(song.lead_track)
    if lead is None:
        raise ValueError(f"в песне нет ведущей дорожки '{song.lead_track}'")

    # Первый такт оставляем пустым — игроку нужно поймать ритм до первой ноты
    candidates = sorted({n.beat for n in lead.notes if n.beat >= bpb})

    if difficulty == "easy":
        # Только сильные доли: ребёнок попадает по счёту «раз-два-три-четыре»
        candidates = [b for b in candidates if abs(b - round(b)) < 1e-6]
    elif difficulty == "hard":
        hat = song.track("hat")
        if hat is not None:
            extra = {n.beat for n in hat.notes if n.beat >= bpb * 2 and n.beat % 1.0 != 0}
            candidates = sorted(set(candidates) | extra)

    beats = {b: "beat" for b in candidates}

    # Атаки монстра: раз в 4 такта, начиная с 4-го. Каждой предшествует замах.
    pattern: list[PatternEvent] = []
    shields: list[float] = []
    attack = float(bpb * 4)
    while attack < song.total_beats - bpb:
        shields.append(attack)
        pattern.append(PatternEvent(attack - WINDUP_LEAD, "windup"))
        pattern.append(PatternEvent(attack, "strike"))
        attack += bpb * 4

    # Щит вытесняет любую ноту, оказавшуюся на той же доле
    for s in shields:
        for b in [k for k in beats if abs(k - s) < 0.25]:
            del beats[b]
        beats[s] = "shield"

    # Скилл и перекус ставим в такты без атак, чтобы не смешивать задачи
    _retype(beats, at=bpb * 6, new_type="skill", avoid=shields)
    _retype(beats, at=bpb * 14, new_type="skill", avoid=shields)
    _retype(beats, at=bpb * 10 + 2, new_type="snack", avoid=shields)

    notes = [ChartNote(b, t) for b, t in beats.items()]
    notes = _ease_in(notes, until=bpb * 2)
    notes = _thin(notes, MAX_DENSITY[difficulty], song.sec_per_beat)
    notes = _mark_attacks(notes, TARGET_SERIES_NOTES.get(difficulty, 6))

    return Chart(
        id=song.id,
        genre=song.genre,
        bpm=song.bpm,
        difficulty=difficulty,
        duration=song.duration,
        audio=f"res://music/{song.id}.ogg",
        beats_per_bar=bpb,
        notes=sorted(notes, key=lambda n: n.beat),
        monster_pattern=pattern,
    )


def _retype(beats: dict[float, str], at: float, new_type: str, avoid: list[float]) -> None:
    """Превратить ближайшую к `at` обычную ноту в ноту другого типа."""
    plain = [b for b, t in beats.items() if t == "beat" and b not in avoid]
    if not plain:
        return
    nearest = min(plain, key=lambda b: abs(b - at))
    if abs(nearest - at) <= 2.0:
        beats[nearest] = new_type


def _mark_attacks(notes: list[ChartNote], target: int) -> list[ChartNote]:
    """Расставить атакующие ноты — единственный источник урона по монстру.

    Атака завершает серию: игрок ведёт связку чисто и «выстреливает» в конце.
    Ставится либо перед паузой (естественный конец связки), либо после
    TARGET_SERIES_NOTES нот, если пауза так и не наступила.

    Сразу после паузы атаки не бывает: перед ней тогда нет серии, и правило
    «чистая серия» становится бессмысленным.
    """
    notes = sorted(notes, key=lambda n: n.beat)
    out = list(notes)
    since = 0

    for i, note in enumerate(notes):
        gap = note.beat - notes[i - 1].beat if i > 0 else 1e9
        if gap > SERIES_GAP:
            since = 1  # первая нота новой связки, атакой быть не может
            continue

        since += 1
        # since считает и саму ноту, а правило требует MIN_SERIES_NOTES нот
        # ПЕРЕД атакой — отсюда +1. Без этой поправки генератор ставил атаки,
        # которые бой отвергал как «серия слишком коротка», и на лёгком чарте
        # три четверти ударов проходили вхолостую.
        if note.type != "beat" or since < MIN_SERIES_NOTES + 1:
            continue

        next_gap = notes[i + 1].beat - note.beat if i + 1 < len(notes) else 1e9
        ends_series = next_gap > SERIES_GAP
        if ends_series or since >= target:
            out[i] = ChartNote(note.beat, "attack")
            since = 0

    return out


def _ease_in(notes: list[ChartNote], until: float) -> list[ChartNote]:
    """Разредить вход в бой до одной ноты на долю.

    Первые такты игрок ещё ловит темп. Плотный старт читается как «игра
    началась без меня» — это самая частая причина, по которой ребёнок бросает
    ритм-игру на первом бою.
    """
    return [
        n for n in notes
        if n.beat >= until or n.type != "beat" or abs(n.beat - round(n.beat)) < 1e-6
    ]


def _thin(notes: list[ChartNote], max_per_sec: float, sec_per_beat: float) -> list[ChartNote]:
    """Проредить обычные ноты до допустимой плотности.

    Ноты-щиты, скиллы и перекусы неприкосновенны: они несут смысл, а не ритм-наполнение.
    """
    min_gap = (1.0 / max_per_sec) / sec_per_beat
    kept: list[ChartNote] = []
    last_plain = -1e9
    for n in sorted(notes, key=lambda x: x.beat):
        if n.type != "beat":
            kept.append(n)
            continue
        if n.beat - last_plain >= min_gap - 1e-6:
            kept.append(n)
            last_plain = n.beat
    return kept


def validate(chart: Chart) -> list[str]:
    """Проверить чарт по правилам разметки. Пустой список = чарт годен."""
    problems: list[str] = []
    notes = sorted(chart.notes, key=lambda n: n.beat)
    spb = 60.0 / chart.bpm
    bpb = chart.beats_per_bar

    for n in notes:
        if n.type not in NOTE_TYPES:
            problems.append(f"доля {n.beat}: неизвестный тип ноты '{n.type}'")

    # 1. Каждый щит телеграфируется замахом
    windups = [e.beat for e in chart.monster_pattern if e.action == "windup"]
    for n in notes:
        if n.type != "shield":
            continue
        if not any(n.beat - w >= WINDUP_LEAD - 1e-6 and n.beat - w <= bpb for w in windups):
            problems.append(f"доля {n.beat}: щит без замаха минимум за {WINDUP_LEAD} доли")

    # 2. Щиты не ближе MIN_SHIELD_GAP друг к другу
    shields = [n.beat for n in notes if n.type == "shield"]
    for a, b in zip(shields, shields[1:]):
        if b - a < MIN_SHIELD_GAP - 1e-6:
            problems.append(f"доли {a}–{b}: щиты подряд, разрыв меньше {MIN_SHIELD_GAP}")

    # 3. Плотность
    limit = MAX_DENSITY.get(chart.difficulty, 4.0)
    for i, n in enumerate(notes):
        window = [m for m in notes[i:] if m.beat - n.beat < 1.0 / spb]
        if len(window) > limit:
            problems.append(
                f"доля {n.beat}: плотность {len(window)} нот/сек выше предела {limit}"
            )
            break

    # 4. Первые два такта — не больше одной ноты на долю
    intro = [n for n in notes if n.beat < bpb * 2]
    for a, b in zip(intro, intro[1:]):
        if b.beat - a.beat < 1.0 - 1e-6:
            problems.append(f"доли {a.beat}–{b.beat}: вход в бой слишком плотный")
            break

    # 5. Не начинать раньше первого такта
    if notes and notes[0].beat < bpb - 1e-6:
        problems.append(f"доля {notes[0].beat}: первая нота раньше конца первого такта")

    # 6. Щит не совпадает с нотой другого типа
    for a, b in zip(notes, notes[1:]):
        if abs(a.beat - b.beat) < 1e-6 and "shield" in (a.type, b.type):
            problems.append(f"доля {a.beat}: щит совпадает с нотой '{a.type}/{b.type}'")

    # 7. Атака стоит только в конце связки и никогда сразу после паузы
    problems.extend(_check_attacks(notes))

    return problems


def _check_attacks(notes: list[ChartNote]) -> list[str]:
    """Перед каждой атакой обязана быть серия минимум из MIN_SERIES_NOTES нот.

    Серия считается от предыдущей атаки или от паузы — смотря что ближе,
    ровно так же, как её считает бой. Атака сразу после паузы запрещена:
    серии перед ней нет, и правило «чистая серия» становится бессмысленным.
    """
    problems: list[str] = []
    since = 0

    for i, note in enumerate(notes):
        gap = note.beat - notes[i - 1].beat if i > 0 else 1e9
        if gap > SERIES_GAP:
            since = 1
        else:
            since += 1

        if note.type != "attack":
            continue

        if i == 0 or gap > SERIES_GAP:
            problems.append(
                f"доля {note.beat}: атака в начале связки — серии перед ней нет"
            )
        elif since - 1 < MIN_SERIES_NOTES:
            problems.append(
                f"доля {note.beat}: связка перед атакой всего {since - 1} нот, "
                f"нужно {MIN_SERIES_NOTES}"
            )
        since = 0

    return problems
