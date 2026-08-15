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


def _manifest():
    from . import manifest

    return manifest.load()


def _select(assets, kinds: list[str] | None, ids: list[str] | None):
    """Отбор ассетов для прогона. Ручная отрисовка не отбирается никогда."""
    from . import manifest

    picked = manifest.generated(assets)
    if kinds:
        picked = [a for a in picked if a.kind.name in kinds]
    if ids:
        wanted = set(ids)
        picked = [a for a in picked if a.id in wanted]
        missing = wanted - {a.id for a in picked}
        for m in sorted(missing):
            print(f"! {m}: нет в манифесте или не генерируется")
    return picked


def cmd_manifest(args: argparse.Namespace) -> int:
    from . import manifest

    assets = _manifest()
    print(manifest.report(assets))
    print()

    risky = manifest.lint(assets)
    if risky:
        print(f"Промпты, написанные так, как уже проваливалось ({len(risky)}):")
        for r in risky:
            print(f"  ~ {r}")
        print()

    problems = manifest.check(assets)
    if problems:
        print(f"Манифест разошёлся с данными игры, замечаний: {len(problems)}")
        for p in problems:
            print(f"  ! {p}")
        return 1

    print("Манифест сходится с data/*.tres и типами полян")
    return 0


def _checkpoint_from_reports(assets) -> str:
    import json

    for asset in assets:
        path = asset.candidates_dir(PROJECT_ROOT) / "report.json"
        if path.exists():
            name = json.loads(path.read_text(encoding="utf-8")).get("checkpoint", "")
            if name:
                return name
    return ""


def cmd_batch(args: argparse.Namespace) -> int:
    from .batch import run, summary
    from .comfy import ComfyClient, profile_for

    assets = _select(_manifest(), args.kind, args.asset)
    if not assets:
        print("Нечего генерировать: под фильтр не попал ни один ассет")
        return 1

    if args.repost:
        # Перегон исходников не обращается к модели вообще: ComfyUI поднимать
        # незачем, а чекпойнт берётся из прошлого отчёта, чтобы в ASSETS.md
        # осталось записано, чем это на самом деле сгенерировано
        checkpoint = args.checkpoint or _checkpoint_from_reports(assets) or "неизвестен"
        print(f"перегон постобработки из исходников, чекпойнт из отчёта: {checkpoint}")
        outcomes = run(assets, None, checkpoint, PROJECT_ROOT,
                       variants=args.variants, repost=True)
        print()
        print(summary(outcomes))
        return 0

    client = ComfyClient(args.host)
    if not client.is_up():
        print(f"ComfyUI не отвечает на {args.host}. Запусти его и повтори.")
        return 1

    available = client.checkpoints()
    if not available:
        print("В ComfyUI нет ни одного чекпойнта — положи модель в models/checkpoints")
        return 1
    checkpoint = args.checkpoint or available[0]
    if checkpoint not in available:
        print(f"чекпойнт '{checkpoint}' не найден. Доступны: {', '.join(available)}")
        return 1

    profile = profile_for(checkpoint)
    print(f"чекпойнт: {checkpoint} (профиль {profile.name}, "
          f"{profile.steps} шагов, cfg {profile.cfg})")
    if profile.distilled:
        print("дистиллят: негативный промпт почти не действует, вырезка фона — "
              "сегментацией (uv sync --extra cutout)")
    print(f"ассетов в прогоне: {len(assets)}\n")

    outcomes = run(assets, client, checkpoint, PROJECT_ROOT,
                   variants=args.variants, force=args.force)
    print()
    print(summary(outcomes))
    return 0


def cmd_review(args: argparse.Namespace) -> int:
    from . import review

    assets = _manifest()

    if args.record:
        asset_id, _, variant = args.record.partition("=")
        if not variant:
            print("формат: --record <id>=<вариант>, например --record bass_bear=01")
            return 1
        review.record(asset_id, variant, args.status, args.note or "", PROJECT_ROOT)
        print(f"вердикт записан: {asset_id} -> вариант {variant}, {args.status}")
        return 0

    if args.build:
        built = 0
        for asset in _select(assets, args.kind, args.asset):
            if review.build_sheet(asset, PROJECT_ROOT) is not None:
                built += 1
        print(f"контакт-листов собрано: {built} -> art/review/")

    items = review.queue(assets, PROJECT_ROOT, include_reviewed=args.all)
    print()
    print(review.status_line(assets, PROJECT_ROOT))
    if not items:
        print("Очередь пуста")
        return 0

    print(f"\nЖдут ревью ({len(items)}):")
    for item in items[: args.limit]:
        print()
        print(item.summary())
        print(f"  лист: {item.sheet}")
    return 0


def cmd_gallery(args: argparse.Namespace) -> int:
    from . import gallery

    assets = _manifest()
    out = Path(args.out) if args.out else ART_DIR / "review" / "gallery.html"
    path = gallery.build(assets, PROJECT_ROOT, out)
    size = path.stat().st_size / 1024
    print(f"-> {path}  ({size:.0f} КБ)")
    print("Открой в браузере, расставь решения, скопируй команду внизу страницы")
    return 0


def cmd_splash(args: argparse.Namespace) -> int:
    from . import splash
    from .promote import load_decisions

    decisions = load_decisions(PROJECT_ROOT)

    def source(asset_id: str, override: str | None) -> Path | None:
        variant = override or decisions.get(asset_id, {}).get("variant")
        if variant is None:
            print(f"! {asset_id}: не принят и вариант не указан "
                  f"(--{asset_id.split('_')[0]} <вариант>)")
            return None
        path = ART_DIR / "candidates" / asset_id / f"{variant}.png"
        if not path.exists():
            print(f"! {asset_id}: вариант {variant} не найден ({path})")
            return None
        return path

    background = source("splash_bg", args.background)
    if background is None:
        return 1

    # Эмблема необязательна: заставка это фон и название
    emblem = source("logo_emblem", args.emblem) if args.emblem else None
    if args.emblem and emblem is None:
        return 1

    out = Path(args.out) if args.out else ART_DIR / "splash.png"
    splash.build(PROJECT_ROOT, background, emblem, out)
    print(f"-> {out.relative_to(PROJECT_ROOT)}  ({splash.SCREEN[0]}x{splash.SCREEN[1]})")
    print("Надпись набрана пиксельными литерами из splash.py — не шрифтом "
          "и не генерацией")
    return 0


def cmd_lobby(args: argparse.Namespace) -> int:
    from . import lobby, review
    from .promote import load_decisions

    decisions = load_decisions(PROJECT_ROOT)
    verdicts = review.load_verdicts(PROJECT_ROOT)
    preview: list[str] = []

    def candidate(asset_id: str) -> Path | None:
        # Решение человека главнее. Но пока его нет, собираем предпросмотр
        # по вердикту Клода — иначе двор нельзя увидеть до конца ревью,
        # а увидеть его надо именно чтобы ревью было осмысленным
        variant = decisions.get(asset_id, {}).get("variant")
        if variant is None:
            variant = verdicts.get(asset_id, {}).get("chosen")
            if variant is not None:
                preview.append(asset_id)
        if variant is None:
            print(f"! {asset_id}: нет ни решения, ни вердикта")
            return None
        path = ART_DIR / "candidates" / asset_id / f"{variant}.png"
        return path if path.exists() else None

    background = candidate("screen_lobby")
    if background is None:
        return 1

    buildings: dict[str, Path] = {}
    for spot in lobby.LAYOUT:
        path = candidate(spot.asset)
        if path is not None:
            buildings[spot.asset] = path

    out = Path(args.out) if args.out else ART_DIR / "lobby.png"
    rects = lobby.build(background, buildings, out)

    print(f"-> {out.relative_to(PROJECT_ROOT)}  ({lobby.SCREEN[0]}x{lobby.SCREEN[1]})")
    if preview:
        print(f"предпросмотр: по вердикту Клода, решения человека ещё нет "
              f"({', '.join(preview)})")
    print("\nпостройки и куда ведут (координаты — под кнопки в сцене):")
    for spot in lobby.LAYOUT:
        rect = rects.get(spot.asset)
        if rect is None:
            print(f"  {spot.title:18} — нет принятого ассета")
            continue
        print(f"  {spot.title:18} x={rect[0]:4} y={rect[1]:4} "
              f"{rect[2]}x{rect[3]}  -> {spot.scene}")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    from .promote import promote

    picks: dict[str, str] = {}
    for item in args.pick or []:
        asset_id, _, variant = item.partition("=")
        if not variant:
            print(f"! {item}: формат --pick <id>=<вариант>, например --pick bass_bear=01")
            return 1
        picks[asset_id] = variant

    result = promote(_manifest(), picks, args.reject or [], PROJECT_ROOT,
                     checkpoint=args.checkpoint or "")
    print(result.as_text())
    return 1 if result.problems else 0


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
    from . import review as review_module

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

    p = sub.add_parser("manifest", help="состав графики игры и сверка с data/*.tres")
    p.set_defaults(func=cmd_manifest)

    p = sub.add_parser("batch", help="сгенерировать кандидатов по манифесту")
    p.add_argument("--kind", action="append", help="только этот вид (можно повторять)")
    p.add_argument("--asset", action="append", help="только этот ассет (можно повторять)")
    p.add_argument("--variants", type=int, help="сколько вариантов на ассет")
    p.add_argument("--checkpoint", help="имя модели; по умолчанию первая доступная")
    p.add_argument("--host", default="http://127.0.0.1:8188")
    p.add_argument("--force", action="store_true", help="перегенерировать уже сделанное")
    p.add_argument("--repost", action="store_true",
                   help="перегнать постобработку из исходников, не трогая модель")
    p.set_defaults(func=cmd_batch)

    p = sub.add_parser("review", help="контакт-листы и вердикты первой ступени ревью")
    p.add_argument("--build", action="store_true", help="пересобрать контакт-листы")
    p.add_argument("--all", action="store_true", help="показать и уже отсмотренные")
    p.add_argument("--limit", type=int, default=5, help="сколько ассетов показать")
    p.add_argument("--kind", action="append")
    p.add_argument("--asset", action="append")
    p.add_argument("--record", metavar="ID=ВАРИАНТ", help="записать вердикт")
    p.add_argument("--status", default=review_module.ACCEPT,
                   choices=list(review_module.STATUSES))
    p.add_argument("--note", help="чем обосновано решение")
    p.set_defaults(func=cmd_review)

    p = sub.add_parser("gallery", help="собрать HTML-страницу для ревью глазами")
    p.add_argument("--out", help="куда положить страницу")
    p.set_defaults(func=cmd_gallery)

    p = sub.add_parser("splash", help="собрать заставку из фона, эмблемы и надписи")
    p.add_argument("--background", help="вариант splash_bg; по умолчанию принятый")
    p.add_argument("--emblem", help="вариант logo_emblem; по умолчанию принятый")
    p.add_argument("--out", help="куда положить заставку")
    p.set_defaults(func=cmd_splash)

    p = sub.add_parser("lobby", help="собрать двор усадьбы с постройками")
    p.add_argument("--out", help="куда положить картинку двора")
    p.set_defaults(func=cmd_lobby)

    p = sub.add_parser("promote", help="перенести принятых кандидатов в игру")
    p.add_argument("--pick", action="append", metavar="ID=ВАРИАНТ")
    p.add_argument("--reject", action="append", metavar="ID")
    p.add_argument("--checkpoint", help="чем сгенерировано — попадёт в ASSETS.md")
    p.set_defaults(func=cmd_promote)

    p = sub.add_parser("comfy", help="сгенерировать в ComfyUI и сразу привести к палитре")
    p.add_argument("subject", help='что рисуем, напр. "round mossy forest creature with big eyes"')
    p.add_argument("--name", help="имя файла результата")
    p.add_argument("--checkpoint", help="имя модели; по умолчанию первая доступная")
    p.add_argument("--host", default="http://127.0.0.1:8188")
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--steps", type=int, default=0,
                   help="по умолчанию берётся из профиля модели")
    p.add_argument("--size", type=int, default=96, help="размер итогового пиксель-ассета")
    p.add_argument("--dump-workflow", metavar="PATH",
                   help="не генерировать, а выгрузить workflow файлом")
    p.set_defaults(func=cmd_comfy)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
