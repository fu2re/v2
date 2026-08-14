"""CLI музыкального пайплайна BEATROOT."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import chart as chart_mod
from . import songs, synth

# tools/chartgen/beatroot_chartgen/cli.py -> корень проекта
PROJECT_ROOT = Path(__file__).resolve().parents[3]
MUSIC_DIR = PROJECT_ROOT / "music"
CHARTS_DIR = PROJECT_ROOT / "charts"
DIFFICULTIES = ("easy", "normal", "hard")


def cmd_list(_: argparse.Namespace) -> int:
    found = songs.all_songs()
    if not found:
        print("Синтезированных песен пока нет.")
        return 0
    for song in found.values():
        print(f"{song.id:16} {song.title:20} {song.genre:8} "
              f"{song.bpm:g} BPM  {song.bars} тактов  {song.duration:.1f} сек")
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    song = songs.get(args.song)
    print(f"{song.title} — {song.bpm:g} BPM, {song.duration:.1f} сек")

    wav = Path(__file__).resolve().parents[1] / "out" / f"{song.id}.wav"
    ogg = MUSIC_DIR / f"{song.id}.ogg"

    print("  рендер аудио...")
    synth.write_wav(synth.render(song), wav)
    synth.wav_to_ogg(wav, ogg)
    print(f"  -> {ogg.relative_to(PROJECT_ROOT)}")

    failed = False
    for difficulty in DIFFICULTIES:
        c = chart_mod.generate(song, difficulty)
        problems = chart_mod.validate(c)
        path = CHARTS_DIR / f"{song.id}_{difficulty}.json"
        c.save(path)

        counts: dict[str, int] = {}
        for n in c.notes:
            counts[n.type] = counts.get(n.type, 0) + 1
        summary = ", ".join(f"{k}:{v}" for k, v in sorted(counts.items()))
        status = "OK" if not problems else f"замечаний: {len(problems)}"
        print(f"  -> {path.relative_to(PROJECT_ROOT)}  [{summary}]  {status}")
        for p in problems:
            print(f"       ! {p}")
            failed = True

    return 1 if failed else 0


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
    c = chart_mod.Chart.load(Path(args.chart))
    problems = chart_mod.validate(c)
    if not problems:
        print(f"{c.id} [{c.difficulty}]: чарт годен, {len(c.notes)} нот")
        return 0
    print(f"{c.id} [{c.difficulty}]: {len(problems)} замечаний")
    for p in problems:
        print(f"  ! {p}")
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="chartgen", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="список синтезированных песен").set_defaults(func=cmd_list)

    p = sub.add_parser("build", help="отрендерить песню и собрать чарты всех сложностей")
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
    p.add_argument("--difficulty", default="normal", choices=DIFFICULTIES)
    p.add_argument("--grid", type=float, default=0.5, help="0.5 — восьмые, 0.25 — шестнадцатые")
    p.set_defaults(func=cmd_autochart)

    p = sub.add_parser("validate", help="проверить чарт по правилам разметки")
    p.add_argument("chart")
    p.set_defaults(func=cmd_validate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
