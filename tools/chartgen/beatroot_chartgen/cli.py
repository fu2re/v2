"""CLI музыкального пайплайна BEATROOT."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import arrange as arrange_mod
from . import chart as chart_mod
from . import motif as motif_mod
from . import songs, synth

# tools/chartgen/beatroot_chartgen/cli.py -> корень проекта
PROJECT_ROOT = Path(__file__).resolve().parents[3]
MUSIC_DIR = PROJECT_ROOT / "music"
CHARTS_DIR = PROJECT_ROOT / "charts"
MOTIFS_PATH = PROJECT_ROOT / "data" / "motifs.json"
OUT_DIR = Path(__file__).resolve().parents[1] / "out"
AUDITION_DIR = OUT_DIR / "motifs"

DIFFICULTIES = chart_mod.LEGACY_DIFFICULTIES
GRADES = arrange_mod.GRADES

# Жанр, на котором прослушиваются кандидаты в мотивы. Диско ровнее прочих:
# на нём слышна сама мелодия, а не характер аранжировки.
AUDITION_GENRE = "disco"
AUDITION_GRADE = "rare"


def _ensure_out_dir() -> None:
    """Закрыть каталог промежуточных .wav от импортёра Godot.

    `out/` лежит внутри проекта, и без `.gdignore` движок пытается
    импортировать каждый промежуточный wav: на матрице из трёхсот треков
    это сотни мегабайт мусора в `.godot/` и заметная пауза на каждом запуске.
    Файл создаётся здесь, а не кладётся в репозиторий, потому что сам каталог
    в `.gitignore` и до свежего клона не доедет.
    """
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / ".gdignore").touch()


def cmd_list(_: argparse.Namespace) -> int:
    found = songs.all_songs()
    if found:
        print("Ручные песни:")
        for song in found.values():
            print(f"  {song.id:16} {song.title:20} {song.genre:8} "
                  f"{song.bpm:g} BPM  {song.bars} тактов  {song.duration:.1f} сек")

    motifs = motif_mod.load_all(MOTIFS_PATH)
    if not motifs:
        print("\nОтобранных мотивов нет. Собери кандидатов: chartgen motifs --audition 24")
        return 0

    print(f"\nМотивы ({len(motifs)}), каждый даёт "
          f"{len(arrange_mod.GENRES)} жанров × {len(GRADES)} грейдов "
          f"= {len(arrange_mod.GENRES) * len(GRADES)} треков:")
    for m in motifs:
        notes = len(m.phrases["A"])
        print(f"  {m.id:10} {m.title:12} сид {m.seed:<6} фраза A — {notes} нот")
    total = len(motifs) * len(arrange_mod.GENRES) * len(GRADES)
    print(f"\nВсего в матрице: {total} треков")
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    """Ручная песня из songs/*.py со старыми сложностями easy/normal/hard."""
    _ensure_out_dir()
    song = songs.get(args.song)
    print(f"{song.title} — {song.bpm:g} BPM, {song.duration:.1f} сек")

    print("  рендер аудио...")
    synth.write_wav(synth.render(song), OUT_DIR / f"{song.id}.wav")
    synth.wav_to_ogg(OUT_DIR / f"{song.id}.wav", MUSIC_DIR / f"{song.id}.ogg")
    print(f"  -> music/{song.id}.ogg")

    failed = False
    for difficulty in DIFFICULTIES:
        if not _write_chart(song, difficulty, verbose=True,
                            stem=f"{song.id}_{difficulty}"):
            failed = True
    return 1 if failed else 0


# --- мотивы -------------------------------------------------------------------


def cmd_motifs(args: argparse.Namespace) -> int:
    if args.audition:
        return _audition(args.audition)
    if args.freeze:
        return _freeze(args.freeze)
    return cmd_list(args)


def _melodic_score(m) -> float:
    """Насколько мелодия похожа на мелодию, а не на перебор клавиш.

    Не заменяет ухо, а сортирует очередь на прослушивание: правила грамматики
    гарантируют связность, но не запоминаемость, а её слышно только ушами.
    Три числа, каждое с понятной причиной:

    * средний шаг около 1.3 ступени — мелодия ведёт линию, а не прыгает;
    * размах около пяти ступеней — есть куда идти, но всё ещё поётся;
    * скачки шире кварты — штраф: один такой в фразе выразителен, три подряд
      слышатся как ошибка.
    """
    degrees = [d for _, _, d in m.phrases["A"]]
    steps = [abs(b - a) for a, b in zip(degrees, degrees[1:])]
    if not steps:
        return 1e9
    avg = sum(steps) / len(steps)
    return (abs(avg - 1.3) * 2.0
            + abs(max(degrees) - min(degrees) - 5) * 0.4
            + sum(1 for s in steps if s >= 4) * 0.8)


def _audition(per_style: int) -> int:
    """Отрендерить кандидатов в мотивы, чтобы отобрать их ушами.

    По несколько кандидатов на каждый характер, а не подряд по сидам: иначе
    в выборку попадают десять вариаций одного и того же, и слушать нечего.
    """
    _ensure_out_dir()
    styles = motif_mod.STYLES
    print(f"Кандидаты: по {per_style} на каждый из {len(styles)} характеров, "
          f"жанр {AUDITION_GENRE}, грейд {AUDITION_GRADE}\n")

    for si, style in enumerate(styles):
        ranked = sorted(
            (motif_mod.generate(seed, f"c{si}_{seed}", "кандидат", si)
             for seed in range(1, 40)),
            key=_melodic_score,
        )
        print(f"{style.name} ({style.cells}, {style.shape}, "
              f"аккорды {motif_mod.PROGRESSIONS[style.progression]}):")
        for m in ranked[:per_style]:
            song = arrange_mod.arrange(m, AUDITION_GENRE, AUDITION_GRADE)
            wav = AUDITION_DIR / f"{m.id}.wav"
            synth.write_wav(synth.render(song), wav)
            synth.wav_to_ogg(wav, AUDITION_DIR / f"{m.id}.ogg")
            wav.unlink(missing_ok=True)
            print(f"    {si}:{m.seed:<3} -> motifs/{m.id}.ogg  "
                  f"{len(m.phrases['A'])} нот, оценка {_melodic_score(m):.2f}")

    print(f"\nПослушай {AUDITION_DIR}, выбери десять и заморозь:")
    print("  chartgen motifs --freeze 0:1 1:20 2:37 ...   (характер:сид)")
    return 0


def _freeze(picks: list[str]) -> int:
    """Записать отобранные мотивы в data/motifs.json.

    После заморозки мотивы не перегенерируются. Иначе правка грамматики
    молча меняла бы все уже одобренные треки, и «пересобрать музыку» стало бы
    операцией, после которой нужно переслушивать всё заново.
    """
    names = motif_mod.MOTIF_NAMES
    if len(picks) > len(names):
        print(f"Имён всего {len(names)}, а выбрано {len(picks)}. "
              f"Добавь имена в motif.MOTIF_NAMES.")
        return 1

    motifs = []
    used_progressions: set[int] = set()
    for i, pick in enumerate(picks):
        try:
            style_index, seed = (int(x) for x in pick.split(":", 1))
        except ValueError:
            print(f"Не разобрать «{pick}». Формат: характер:сид, например 3:17")
            return 1
        style = motif_mod.STYLES[style_index % len(motif_mod.STYLES)]

        # Два мотива одного характера с одной гармонией слышались бы как
        # вариации друг друга. Второму достаётся ещё не занятый оборот.
        # Оборотов меньше, чем мотивов, поэтому перебор ограничен их числом:
        # без ограничения одиннадцатый мотив крутил бы цикл вечно.
        total = len(motif_mod.PROGRESSIONS)
        progression = style.progression
        for _ in range(total):
            if progression not in used_progressions:
                break
            progression = (progression + 1) % total
        used_progressions.add(progression)

        motifs.append(motif_mod.generate(
            seed, names[i][0], names[i][1], style_index, progression))

    motif_mod.save_all(motifs, MOTIFS_PATH)
    print(f"Заморожено мотивов: {len(motifs)} -> "
          f"{MOTIFS_PATH.relative_to(PROJECT_ROOT)}")
    for m in motifs:
        print(f"  {m.id:10} {m.title:12} {m.style:12} сид {m.seed:<4} "
              f"аккорды {m.chords}  план {'-'.join(m.plan)}")
    print("\nСобрать базовые треки: chartgen build-all --grade common")
    return 0


# --- матрица ------------------------------------------------------------------


def cmd_build_all(args: argparse.Namespace) -> int:
    motifs = motif_mod.load_all(MOTIFS_PATH)
    if not motifs:
        print(f"Нет отобранных мотивов ({MOTIFS_PATH.relative_to(PROJECT_ROOT)}).")
        print("Сначала: chartgen motifs --audition 24, потом --freeze")
        return 1

    if args.motif:
        motifs = [m for m in motifs if m.id in args.motif]
        if not motifs:
            print(f"Мотивы не найдены: {', '.join(args.motif)}")
            return 1
    genres = args.genre or list(arrange_mod.GENRES)
    grades = args.grade or list(GRADES)

    total = len(motifs) * len(genres) * len(grades)
    print(f"Матрица: {len(motifs)} мотивов × {len(genres)} жанров × "
          f"{len(grades)} грейдов = {total} треков")
    if args.charts_only:
        print("Только чарты, аудио не пересобирается.")
    else:
        _ensure_out_dir()

    done = 0
    failed: list[str] = []
    bytes_written = 0

    for m in motifs:
        for genre in genres:
            for grade in grades:
                song = arrange_mod.arrange(m, genre, grade)
                ogg = MUSIC_DIR / f"{song.id}.ogg"

                if not args.charts_only:
                    wav = OUT_DIR / f"{song.id}.wav"
                    synth.write_wav(synth.render(song), wav)
                    synth.wav_to_ogg(wav, ogg)
                    wav.unlink(missing_ok=True)
                if ogg.exists():
                    bytes_written += ogg.stat().st_size

                if not _write_chart(song, grade, verbose=args.verbose):
                    failed.append(f"{song.id}")

                done += 1
                if not args.verbose and done % 10 == 0:
                    print(f"  {done}/{total}...")

    print(f"\nГотово: {done} треков, аудио {bytes_written / 1024 / 1024:.1f} МБ")
    if failed:
        print(f"Чарты с замечаниями ({len(failed)}): {', '.join(failed[:10])}"
              + (" ..." if len(failed) > 10 else ""))
        return 1
    return 0


def _write_chart(song, difficulty: str, verbose: bool, stem: str | None = None) -> bool:
    """Собрать, проверить и записать чарт. False — если есть замечания.

    Имя файла чарта совпадает с именем аудио: `disco_zarya_rare_158.json`
    рядом с `disco_zarya_rare_158.ogg`. Ручные песни передают `stem` явно —
    у них в имени нет ни грейда, ни темпа.
    """
    c = chart_mod.generate(song, difficulty)
    problems = chart_mod.validate(c)
    path = CHARTS_DIR / f"{stem or song.id}.json"
    c.save(path)

    if verbose or problems:
        counts: dict[str, int] = {}
        for n in c.notes:
            counts[n.type] = counts.get(n.type, 0) + 1
        summary = ", ".join(f"{k}:{v}" for k, v in sorted(counts.items()))
        status = "OK" if not problems else f"замечаний: {len(problems)}"
        print(f"  -> charts/{path.name}  [{summary}]  {status}")
        for p in problems:
            print(f"       ! {p}")
    return not problems


# --- неигровая музыка ---------------------------------------------------------


def cmd_cues(args: argparse.Namespace) -> int:
    """Собрать джинглы, петли экранов и подсказки полян.

    Чарты этим трекам не нужны: под них не играют, попадать в них не во что.
    Поэтому команда отдельная — `build-all` про боевую музыку и всегда пишет
    рядом карту нот.
    """
    from . import cue as cue_mod

    _ensure_out_dir()
    motifs = {m.id: m for m in motif_mod.load_all(MOTIFS_PATH)}
    if not motifs:
        print(f"Нет мотивов ({MOTIFS_PATH.relative_to(PROJECT_ROOT)}).")
        return 1

    total = 0
    written = 0

    def _render(song, folder: str) -> None:
        nonlocal total, written
        wav = OUT_DIR / f"{song.id}.wav"
        ogg = MUSIC_DIR / folder / f"{song.id}_{song.bpm:.0f}.ogg"
        synth.write_wav(synth.render(song, tail=0.6), wav)
        synth.wav_to_ogg(wav, ogg)
        wav.unlink(missing_ok=True)
        total += 1
        written += ogg.stat().st_size
        print(f"  {ogg.relative_to(MUSIC_DIR)}  {song.duration:.1f} сек  "
              f"{song.bpm:.0f} BPM  {song.title}")

    print("Джинглы:")
    for spec in cue_mod.STINGERS:
        _render(cue_mod.stinger(spec), "cue")

    print("\nЭкраны:")
    for spec in cue_mod.SCREENS:
        motif = motifs.get(spec.motif)
        if motif is None:
            print(f"  ! экран {spec.id}: мотива '{spec.motif}' нет в motifs.json")
            return 1
        _render(cue_mod.ambient(spec, motif), "ui")

    print("\nВстречи с монстром:")
    order = list(motifs.values())
    if len(order) < cue_mod.ENCOUNTER_COUNT:
        print(f"  ! мотивов {len(order)}, а встреч нужно "
              f"{cue_mod.ENCOUNTER_COUNT} — ротация пойдёт по кругу")
    for i in range(cue_mod.ENCOUNTER_COUNT):
        motif = order[i % len(order)]
        spec = cue_mod.ENCOUNTERS[i % len(cue_mod.ENCOUNTERS)]
        _render(cue_mod.encounter(motif, spec, i), "glade")

    print("\nПоляны:")
    for spec in cue_mod.GLADES:
        for variant in range(cue_mod.GLADE_VARIANT_COUNT):
            _render(cue_mod.glade_cue(spec, variant), "glade")

    print(f"\nГотово: {total} файлов, {written / 1024 / 1024:.1f} МБ")
    return 0


# --- внешнее аудио ------------------------------------------------------------


def cmd_analyze(args: argparse.Namespace) -> int:
    from .analyze import analyze

    a = analyze(Path(args.audio), args.bpm)
    print(f"файл:        {a.path.name}")
    print(f"длительность {a.duration:.2f} сек")
    print(f"BPM:         {a.bpm}")
    print(f"первая доля: {a.offset:.3f} сек")
    print(f"долей:       {len(a.beats)}")
    print(f"онсетов:     {len(a.onsets)}")
    return 0


def cmd_autochart(args: argparse.Namespace) -> int:
    from .analyze import analyze, quantize

    audio = Path(args.audio)
    a = analyze(audio, args.bpm)
    beats = [b for b in quantize(a.onset_beats(), args.grid) if b >= 4]

    c = chart_mod.Chart(
        id=audio.stem,
        genre=args.genre,
        bpm=a.bpm,
        difficulty=args.difficulty,
        duration=a.duration,
        audio=f"res://music/{audio.stem}.ogg",
        offset=round(a.offset, 4),
        notes=[chart_mod.ChartNote(b, "beat") for b in beats],
    )
    path = CHARTS_DIR / f"{c.id}_{c.difficulty}.json"
    c.save(path)
    print(f"черновой чарт: {path.relative_to(PROJECT_ROOT)}  ({len(c.notes)} нот)")
    print("Это черновик. Щиты, скиллы и замахи монстра расставляются вручную —")
    print("автоматика не знает, где бой должен становиться напряжённым.")
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    paths = [Path(args.chart)] if args.chart else sorted(CHARTS_DIR.glob("*.json"))
    if not paths:
        print("Чартов не найдено.")
        return 1

    bad = 0
    for path in paths:
        c = chart_mod.Chart.load(path)
        problems = chart_mod.validate(c)
        if not problems:
            if args.chart:
                print(f"{c.id} [{c.difficulty}]: чарт годен, {len(c.notes)} нот")
            continue
        bad += 1
        print(f"{c.id} [{c.difficulty}]: {len(problems)} замечаний")
        for p in problems:
            print(f"  ! {p}")

    if not args.chart:
        print(f"\nПроверено чартов: {len(paths)}, с замечаниями: {bad}")
    return 1 if bad else 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="chartgen", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="мотивы и ручные песни").set_defaults(func=cmd_list)

    p = sub.add_parser("motifs", help="отбор мелодических мотивов")
    p.add_argument("--audition", type=int, metavar="N",
                   help="отрендерить по N кандидатов на каждый характер")
    p.add_argument("--freeze", nargs="+", metavar="ХАРАКТЕР:СИД",
                   help="заморозить выбранные мотивы в data/motifs.json")
    p.set_defaults(func=cmd_motifs)

    p = sub.add_parser("build-all", help="собрать всю матрицу мотив × жанр × грейд")
    p.add_argument("--motif", nargs="+", help="только эти мотивы")
    p.add_argument("--genre", nargs="+", choices=list(arrange_mod.GENRES))
    p.add_argument("--grade", nargs="+", choices=list(GRADES))
    p.add_argument("--charts-only", action="store_true",
                   help="пересобрать только чарты, аудио не трогать")
    p.add_argument("--verbose", action="store_true")
    p.set_defaults(func=cmd_build_all)

    sub.add_parser(
        "cues", help="джинглы, петли экранов и подсказки полян (без чартов)"
    ).set_defaults(func=cmd_cues)

    p = sub.add_parser("build", help="ручная песня из songs/*.py")
    p.add_argument("song")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("analyze", help="анализ внешнего аудиофайла")
    p.add_argument("audio")
    p.add_argument("--bpm", type=float, default=None, help="подсказка по темпу")
    p.set_defaults(func=cmd_analyze)

    p = sub.add_parser("autochart", help="черновой чарт из внешнего аудио")
    p.add_argument("audio")
    p.add_argument("--bpm", type=float, default=None)
    p.add_argument("--genre", default="disco")
    p.add_argument("--difficulty", default="normal",
                   choices=list(GRADES) + list(DIFFICULTIES))
    p.add_argument("--grid", type=float, default=0.5, help="0.5 — восьмые, 0.25 — шестнадцатые")
    p.set_defaults(func=cmd_autochart)

    p = sub.add_parser("validate", help="проверить чарты по правилам разметки")
    p.add_argument("chart", nargs="?", help="без аргумента проверяет все charts/*.json")
    p.set_defaults(func=cmd_validate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
