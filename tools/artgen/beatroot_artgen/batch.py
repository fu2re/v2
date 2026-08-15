"""Пакетная генерация кандидатов по манифесту.

Один прогон — это сотня с лишним обращений к модели, полчаса работы видеокарты
и гарантированный обрыв где-нибудь посередине: ComfyUI перезапустили, кончилась
память, отвалилась сеть. Поэтому прогон резюмируемый: уже сделанные кандидаты
не переделываются, и повтор команды доводит начатое, а не начинает заново.

Сид детерминирован от id ассета и номера варианта через SHA-256 — как форма
плейсхолдеров, и по той же причине: встроенный `hash()` рандомизируется между
запусками, и «перегенерировать вариант 2» давало бы каждый раз новую картинку,
а сравнить их между собой стало бы невозможно.
"""

from __future__ import annotations

import hashlib
import json
import time
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from . import metrics
from .comfy import ComfyClient, GenerationRequest, positive_prompt, profile_for
from .manifest import Asset
from .pixelize import pixelize

SEED_SPACE = 2 ** 31

# Старший грейд берётся перебором, а перебор требует материала: четырёх бросков
# мало, чтобы среди них оказался похожий на основу. Восемь — компромисс между
# шансом и временем: на 4090 это полминуты на грейд.
BRUTE_FORCE_VARIANTS = 8


def seed_for(asset_id: str, variant: int, attempt: int = 0) -> int:
    """Номер попытки входит в сид намеренно.

    Отклонённый ассет генерируется заново — и без смены попытки выдал бы ровно
    ту же картинку, потому что сид детерминирован. Счётчик попытки двигает
    `artgen promote --reject`.
    """
    digest = hashlib.sha256(f"{asset_id}:{attempt}:{variant}".encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big") % SEED_SPACE


@dataclass
class Outcome:
    asset_id: str
    made: int
    skipped: int
    failed: int
    passed: int


def _variant_paths(asset: Asset, index: int, root: Path, attempt: int) -> tuple[Path, Path]:
    """Попытка входит в имя файла: иначе новый прогон затирал бы прошлый брак,
    и сравнить «стало ли лучше» было бы не с чем."""
    directory = asset.candidates_dir(root)
    prefix = f"{index:02d}" if attempt == 0 else f"{attempt}-{index:02d}"
    return directory / f"{prefix}.raw.png", directory / f"{prefix}.png"


def _reference(asset: Asset, root: Path):
    """Принятая основа, с которой сравниваются кандидаты старшего грейда."""
    from . import review

    return review.reference_image(asset, root)


def source_for_grade(asset: Asset, root: Path) -> Path | None:
    """Исходник для img2img: принятый вариант предыдущего грейда.

    Берётся именно raw в полном разрешении, а не готовый пиксель-ассет:
    квантованные 96×96 модель разберёт как мусор, и вместо «того же зверя
    в убранстве побогаче» получится новое существо.

    None означает, что строить не на чем — предыдущий грейд ещё не принят.
    """
    from .promote import load_decisions

    previous = asset.previous_grade_id()
    if previous is None:
        return None

    decision = load_decisions(root).get(previous, {})
    if decision.get("status") != "принят":
        return None

    raw = root / "art" / "candidates" / previous / f"{decision['variant']}.raw.png"
    return raw if raw.exists() else None


def _postprocess(raw: Image.Image, asset: Asset) -> Image.Image:
    """Живопись -> пиксель в палитре проекта. Фон вырезается только там,
    где ассет — объект: у поляны фон и есть содержимое."""
    from .palette import quantization_palette

    # Золото доступно только легендарному: иначе к нему тянутся все тёплые
    # светлые пиксели подряд и желтеет вся коллекция
    legendary = asset.grade is not None and asset.grade.key == "legendary"
    return pixelize(raw, target=asset.kind.size, remove_background=asset.kind.cutout,
                    quantize=asset.kind.quantize,
                    palette=quantization_palette(gold=legendary))


def generate_asset(asset: Asset, client: ComfyClient | None, checkpoint: str, root: Path,
                   variants: int | None = None, force: bool = False,
                   attempt: int = 0, repost: bool = False, log=print) -> Outcome:
    graded = asset.grade is not None and not asset.grade.is_base
    count = variants or (BRUTE_FORCE_VARIANTS if graded else asset.kind.variants)
    directory = asset.candidates_dir(root)
    directory.mkdir(parents=True, exist_ok=True)

    # Старший грейд рисуется ТЕМ ЖЕ промптом и с чистого листа, а годным
    # считается похожий на принятую основу. img2img здесь не годится: шесть
    # опытов показали, что он либо ничего не меняет, либо ломает персонажа
    # (разбор — в шапке art/assets.toml).
    init_name = ""
    denoise = 1.0
    reference = None
    if asset.grade is not None and not asset.grade.is_base:
        reference = _reference(asset, root)
        if reference is None:
            log(f"    пропуск: грейд {asset.grade.name} отбирается по похожести "
                f"на {asset.previous_grade_id()}, а тот ещё не принят")
            return Outcome(asset.id, 0, count, 0, 0)

    made = skipped = failed = passed = 0
    records: list[dict] = []

    for i in range(count):
        raw_path, px_path = _variant_paths(asset, i, root, attempt)
        seed = seed_for(asset.id, i, attempt)

        if repost:
            # Перегнать исходник заново, не трогая модель. Нужно, когда изменилась
            # постобработка или палитра: генерация стоит секунды видеокарты,
            # но исходники — единственное, что нельзя воспроизвести бит в бит
            # после смены чекпойнта, и переводить их впустую незачем.
            if not raw_path.exists():
                skipped += 1
                continue
            _postprocess(Image.open(raw_path), asset).save(px_path)
            made += 1
        elif px_path.exists() and raw_path.exists() and not force:
            skipped += 1
        else:
            req = GenerationRequest(
                subject=asset.full_subject(),
                checkpoint=checkpoint,
                seed=seed,
                width=asset.kind.gen_width,
                height=asset.kind.gen_height,
                # Фон и спрайт просятся у модели противоположными словами.
                # Признак один и тот же: у фона нечего вырезать
                scene=not asset.kind.cutout,
                init_image=init_name,
                denoise=denoise,
            )
            started = time.time()
            try:
                raw = client.generate(req)
            except Exception as e:  # noqa: BLE001 — обрыв одного варианта не должен
                failed += 1        # рушить прогон на сто ассетов
                log(f"    вариант {i}: {type(e).__name__}: {e}")
                continue
            raw.save(raw_path)
            _postprocess(raw, asset).save(px_path)
            made += 1
            log(f"    вариант {i}: {time.time() - started:.0f} сек")

        report = metrics.evaluate(
            Image.open(px_path), asset.id, px_path.stem,
            cutout=asset.kind.cutout,
            tiling=asset.kind.name == "tile",
            reference=reference,
            world=asset.kind.quantize,
        )
        if report.passed:
            passed += 1

        record = report.as_dict()
        record["seed"] = seed
        record["raw"] = raw_path.name
        record["image"] = px_path.name
        records.append(record)

    # Перебор имеет смысл только отсортированным: похожие сверху, иначе
    # человек листает восемь картинок и держит сравнение в голове
    if reference is not None:
        def match(rec: dict) -> float:
            found = [c["value"] for c in rec["checks"] if c["name"] == "similarity"]
            return found[0] if found else 0.0

        records.sort(key=match, reverse=True)

    (directory / "report.json").write_text(
        json.dumps({
            "asset_id": asset.id,
            "kind": asset.kind.name,
            "checkpoint": checkpoint,
            "profile": profile_for(checkpoint).name,
            "prompt": positive_prompt(asset.full_subject(), checkpoint,
                                      scene=not asset.kind.cutout),
            "size": asset.kind.size,
            "cutout": asset.kind.cutout,
            "grade": asset.grade.key if asset.grade else None,
            "grade_name": asset.grade.name if asset.grade else None,
            "base_id": asset.base_id,
            ## С чем сравнивались кандидаты при отборе по похожести
            "compared_to": asset.previous_grade_id() if reference is not None else None,
            "variants": records,
        }, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    return Outcome(asset.id, made, skipped, failed, passed)


def run(assets: list[Asset], client: ComfyClient | None, checkpoint: str, root: Path,
        variants: int | None = None, force: bool = False, repost: bool = False,
        log=print) -> list[Outcome]:
    from .promote import attempt_of

    outcomes: list[Outcome] = []
    for n, asset in enumerate(assets, 1):
        attempt = attempt_of(asset.id, root)
        suffix = f", попытка {attempt}" if attempt else ""
        log(f"[{n}/{len(assets)}] {asset.id} ({asset.kind.name}{suffix})")
        outcome = generate_asset(asset, client, checkpoint, root,
                                 variants, force, attempt, repost, log)
        outcomes.append(outcome)
        log(f"    сделано {outcome.made}, пропущено {outcome.skipped}, "
            f"ошибок {outcome.failed}, прошло ворота {outcome.passed}")
    return outcomes


def summary(outcomes: list[Outcome]) -> str:
    made = sum(o.made for o in outcomes)
    skipped = sum(o.skipped for o in outcomes)
    failed = sum(o.failed for o in outcomes)
    passed = sum(o.passed for o in outcomes)
    # Ассет без исходника ничего не генерировал: у него нечему было провалиться.
    # Смешивать его с «сгенерировали и всё забраковано» нельзя — это разные
    # проблемы, и лечатся они разным.
    waiting = [o.asset_id for o in outcomes if o.made == 0 and o.passed == 0 and o.failed == 0]
    empty = [o.asset_id for o in outcomes
             if o.passed == 0 and o.asset_id not in waiting]

    lines = [
        f"ассетов: {len(outcomes)}, сгенерировано: {made}, из кэша: {skipped}, "
        f"ошибок генерации: {failed}",
        f"прошло автоматические ворота: {passed}",
    ]
    if waiting:
        lines.append(
            f"ждут принятого младшего грейда ({len(waiting)}): {', '.join(waiting)}"
        )
    if empty:
        lines.append(
            f"без единого годного кандидата ({len(empty)}): {', '.join(empty)}"
        )
        lines.append("им нужен другой промпт или другой чекпойнт — сами не исправятся")
    return "\n".join(lines)
