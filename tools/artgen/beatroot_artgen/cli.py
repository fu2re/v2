"""CLI арт-пайплайна BEATROOT."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import palette as pal
from . import placeholder, swatch

PROJECT_ROOT = Path(__file__).resolve().parents[3]
ART_DIR = PROJECT_ROOT / "art"
PLACEHOLDER_DIR = ART_DIR / "placeholder"

# Стартовый набор для Фазы 0 — по одному силуэту на жанр
DEMO_CREATURES = [
    ("bass_bear", "quadruped", "rock"),
    ("disco_sprout", "biped", "disco"),
    ("banjo_moth", "flyer", "folk"),
    ("synth_slime", "blob", "electro"),
    ("beat_serpent", "serpent", "hiphop"),
]

# Герой — человечек, а не монстр: игрок обязан отличать себя от защитника
HERO = ("hero_kid",)

DEMO_FRUITS = ["drum_berry", "bass_plum", "echo_pear", "loop_fig", "chord_apple"]


def cmd_palette(args: argparse.Namespace) -> int:
    print(pal.report())
    print()

    problems = pal.check()
    if problems:
        print(f"Палитра нарушает правило разделения, замечаний: {len(problems)}")
        for p in problems:
            print(f"  ! {p}")
    else:
        print(f"Палитра в порядке: {len(pal.environment_colors())} цветов мира, "
              f"{len(pal.GAMEPLAY)} игровых, разделение соблюдено")

    if not args.check:
        out = ART_DIR / "palette.json"
        pal.save(out)
        print(f"\n-> {out.relative_to(PROJECT_ROOT)}")

        sheet = ART_DIR / "palette.png"
        sheet.parent.mkdir(parents=True, exist_ok=True)
        placeholder.upscale(swatch.render(), 1).save(sheet)
        print(f"-> {sheet.relative_to(PROJECT_ROOT)}")

    return 1 if problems else 0


def cmd_placeholders(args: argparse.Namespace) -> int:
    PLACEHOLDER_DIR.mkdir(parents=True, exist_ok=True)

    for name, silhouette, genre in DEMO_CREATURES:
        img = placeholder.creature(name, silhouette, genre, size=args.size)
        path = PLACEHOLDER_DIR / f"monster_{name}.png"
        img.save(path)
        print(f"  -> {path.relative_to(PROJECT_ROOT)}  {silhouette}/{genre}")

    # Герой — отдельный силуэт: игрок должен отличать себя от защитника
    hero = placeholder.hero(HERO[0], size=args.size)
    hero_path = PLACEHOLDER_DIR / "hero.png"
    hero.save(hero_path)
    print(f"  -> {hero_path.relative_to(PROJECT_ROOT)}  герой")

    for name in DEMO_FRUITS:
        img = placeholder.fruit(name, size=args.size // 2)
        path = PLACEHOLDER_DIR / f"fruit_{name}.png"
        img.save(path)
        print(f"  -> {path.relative_to(PROJECT_ROOT)}")

    if args.preview:
        sheet = _contact_sheet(args.size)
        path = ART_DIR / "placeholder_preview.png"
        sheet.save(path)
        print(f"\n-> {path.relative_to(PROJECT_ROOT)}  (превью, x4)")

    return 0


def _contact_sheet(size: int):
    from PIL import Image

    from .color import hex_to_rgb
    from .palette import ENVIRONMENT
    from .swatch import dim
    import numpy as np

    cells = len(DEMO_CREATURES)
    bg = dim(np.full((size, size * cells, 3), hex_to_rgb(ENVIRONMENT["foliage"][2]), dtype=np.uint8))
    sheet = Image.fromarray(bg, mode="RGB").convert("RGBA")

    for i, (name, silhouette, genre) in enumerate(DEMO_CREATURES):
        img = placeholder.creature(name, silhouette, genre, size=size)
        sheet.alpha_composite(img, (i * size, 0))

    fruits = Image.new("RGBA", (size * cells, size // 2), (0, 0, 0, 0))
    for i, name in enumerate(DEMO_FRUITS):
        fruits.alpha_composite(placeholder.fruit(name, size=size // 2), (i * size, 0))

    out = Image.new("RGBA", (size * cells, size + size // 2), (0, 0, 0, 255))
    out.alpha_composite(sheet, (0, 0))
    out.alpha_composite(fruits, (0, size))
    return placeholder.upscale(out, 4)


def cmd_pixelize(args: argparse.Namespace) -> int:
    from .pixelize import process_file

    src = Path(args.src)
    dst = Path(args.dst) if args.dst else src.with_name(f"{src.stem}_px.png")
    img = process_file(src, dst, target=args.size, remove_background=not args.keep_background)
    print(f"{src.name} -> {dst}  ({img.width}x{img.height}, палитра проекта)")
    return 0


def cmd_comfy(args: argparse.Namespace) -> int:
    from .comfy import ComfyClient, GenerationRequest, save_workflow
    from .pixelize import pixelize

    req = GenerationRequest(
        subject=args.subject,
        checkpoint=args.checkpoint or "",
        seed=args.seed,
        steps=args.steps,
    )

    if args.dump_workflow:
        out = Path(args.dump_workflow)
        save_workflow(req, out)
        print(f"-> {out}  (можно открыть в ComfyUI и покрутить руками)")
        return 0

    client = ComfyClient(args.host)
    if not client.is_up():
        print(f"ComfyUI не отвечает на {args.host}.")
        print("Запусти его и повтори, либо выгрузи workflow: artgen comfy ... --dump-workflow wf.json")
        return 1

    available = client.checkpoints()
    if not available:
        print("В ComfyUI не установлено ни одного чекпойнта — положи модель в models/checkpoints")
        return 1
    if not req.checkpoint:
        req.checkpoint = available[0]
        print(f"чекпойнт не указан, беру первый доступный: {req.checkpoint}")
    elif req.checkpoint not in available:
        print(f"чекпойнт '{req.checkpoint}' не найден. Доступны:")
        for c in available:
            print(f"  {c}")
        return 1

    print(f"генерация: {req.subject}")
    raw = client.generate(req)

    ART_DIR.mkdir(parents=True, exist_ok=True)
    stem = args.name or "comfy_out"
    raw_path = ART_DIR / "raw" / f"{stem}.png"
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    raw.save(raw_path)
    print(f"  -> {raw_path.relative_to(PROJECT_ROOT)}  (исходник {raw.width}x{raw.height})")

    px = pixelize(raw, target=args.size)
    px_path = ART_DIR / f"{stem}.png"
    px.save(px_path)
    print(f"  -> {px_path.relative_to(PROJECT_ROOT)}  ({px.width}x{px.height}, палитра проекта)")
    print("\nДальше — ручная чистка краёв и силуэта. Автомат до конца не доводит.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="artgen", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("palette", help="проверить и выгрузить палитру проекта")
    p.add_argument("--check", action="store_true", help="только проверка, без записи файлов")
    p.set_defaults(func=cmd_palette)

    p = sub.add_parser("placeholders", help="сгенерировать плейсхолдеры для Фазы 0")
    p.add_argument("--size", type=int, default=96)
    p.add_argument("--preview", action="store_true", help="собрать общий лист превью")
    p.set_defaults(func=cmd_placeholders)

    p = sub.add_parser("pixelize", help="привести картинку из ComfyUI к палитре проекта")
    p.add_argument("src")
    p.add_argument("dst", nargs="?")
    p.add_argument("--size", type=int, default=96)
    p.add_argument("--keep-background", action="store_true", help="не вырезать фон")
    p.set_defaults(func=cmd_pixelize)

    p = sub.add_parser("comfy", help="сгенерировать в ComfyUI и сразу привести к палитре")
    p.add_argument("subject", help='что рисуем, напр. "round mossy forest creature with big eyes"')
    p.add_argument("--name", help="имя файла результата")
    p.add_argument("--checkpoint", help="имя модели; по умолчанию первая доступная")
    p.add_argument("--host", default="http://127.0.0.1:8188")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--steps", type=int, default=28)
    p.add_argument("--size", type=int, default=96, help="размер итогового пиксель-ассета")
    p.add_argument("--dump-workflow", metavar="PATH",
                   help="не генерировать, а выгрузить workflow файлом")
    p.set_defaults(func=cmd_comfy)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
