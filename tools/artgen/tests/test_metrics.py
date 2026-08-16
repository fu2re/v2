"""Ворота проверяются мутацией.

На каждую проверку — картинка, сломанная ровно её способом. Тест «годный спрайт
проходит» сам по себе ничего не стоит: он одинаково зелёный и когда ворота
работают, и когда они всё пропускают.
"""

from __future__ import annotations

import pytest

from beatroot_artgen import metrics


def failed_names(report: metrics.Report) -> set[str]:
    return {c.name for c in report.checks if not c.ok}


def evaluate(img, **kw) -> metrics.Report:
    return metrics.evaluate(img, "проба", "00", **kw)


# ─────────────────────────────── спрайты ────────────────────────────────────

def test_годный_спрайт_проходит(good_sprite):
    report = evaluate(good_sprite)
    assert report.passed, f"годный спрайт завёрнут: {failed_names(report)}"
    assert not report.warnings, f"годный спрайт получил замечания: {failed_names(report)}"


def test_невырезанный_фон_валится(uncut_background):
    report = evaluate(uncut_background)
    assert not report.passed
    assert "coverage" in failed_names(report)


def test_обрезанный_краем_силуэт_валится(cropped_sprite):
    report = evaluate(cropped_sprite)
    assert not report.passed
    assert "edge_touch" in failed_names(report)


def test_мусор_от_вырезки_валится(shredded_sprite):
    report = evaluate(shredded_sprite)
    assert not report.passed
    assert "debris" in failed_names(report)


def test_игровой_цвет_в_ассете_валится(gameplay_colored_sprite):
    """Правило GDD §11.1.1: цвет ноты не имеет права появиться в окружении."""
    report = evaluate(gameplay_colored_sprite)
    assert not report.passed
    assert "palette_leak" in failed_names(report)


def test_белый_блик_не_считается_утечкой(highlighted_sprite):
    """`perfect` белый, но белый блик в глазу — не нарушение.

    Без этого исключения ворота заворачивали бы каждого монстра с бликом,
    а таких — все.
    """
    report = evaluate(highlighted_sprite)
    assert "palette_leak" not in failed_names(report)
    assert report.passed


def test_слившийся_с_поляной_силуэт_валится(camouflaged_sprite):
    """Squint-тест из GDD §11.1.1: на размытом мелком кадре силуэт обязан остаться."""
    report = evaluate(camouflaged_sprite)
    assert not report.passed
    assert "squint" in failed_names(report)


def test_пустая_картинка_валится():
    from PIL import Image

    report = evaluate(Image.new("RGBA", (96, 96), (0, 0, 0, 0)))
    assert not report.passed
    assert "coverage" in failed_names(report)


# ──────────────────────────────── фоны и тайлы ───────────────────────────────

def test_годный_фон_проходит(good_backdrop):
    report = evaluate(good_backdrop, cutout=False)
    assert report.passed, f"годный фон завёрнут: {failed_names(report)}"


def test_дыра_в_фоне_валится(holed_backdrop):
    report = evaluate(holed_backdrop, cutout=False)
    assert not report.passed
    assert "opaque" in failed_names(report)


def test_перегруженный_деталью_фон_получает_замечание(busy_backdrop):
    """Требование GDD §11.1: ландшафтная плотность деталей на портретном
    телефоне превращается в кашу, и ноты в ней тонут."""
    report = evaluate(busy_backdrop, cutout=False)
    assert "detail_load" in failed_names(report)


def test_шов_тайла_виден(seamed_tile):
    report = evaluate(seamed_tile, cutout=False, tiling=True)
    assert "tile_seam" in failed_names(report)


def test_шов_проверяется_только_у_тайлов(seamed_tile):
    """Тот же файл без флага замощения про шов молчит: фон поляны не мостится,
    и требовать от него сходящихся краёв незачем."""
    report = evaluate(seamed_tile, cutout=False, tiling=False)
    assert "tile_seam" not in {c.name for c in report.checks}


# ─────────────────────────── устройство отчёта ──────────────────────────────

def test_замечание_не_закрывает_дорогу(good_sprite):
    """Разделение провалов и замечаний — не украшение: замечание должно быть
    видно в галерее, но выбрасывать за него кандидата нельзя."""
    report = metrics.Report("проба", "00", checks=[
        metrics.Check("выдумка", 1.0, False, metrics.WARN, "просто замечание"),
    ])
    assert report.passed
    assert report.warnings


def test_провал_закрывает_дорогу():
    report = metrics.Report("проба", "00", checks=[
        metrics.Check("выдумка", 1.0, False, metrics.FAIL, "настоящий брак"),
    ])
    assert not report.passed


def test_фон_боя_темнее_исходной_листвы():
    """Ассет меряется на притемнённом фоне, а не на чистом цвете листвы:
    в бою фон притемняется на 30% (GDD §11.1.1)."""
    from beatroot_artgen.color import hex_to_rgb, luminance
    from beatroot_artgen.palette import ENVIRONMENT

    assert luminance(metrics.battle_backdrop()) < luminance(hex_to_rgb(ENVIRONMENT["foliage"][2]))


def test_похожесть_на_себя_полная(good_sprite):
    """Опора шкалы: если кандидат — та же картинка, похожесть обязана быть 1.0."""
    check = metrics.similarity(good_sprite, good_sprite)
    assert check.value == pytest.approx(1.0)
    assert check.ok


def test_другое_существо_не_похоже(good_sprite, gameplay_colored_sprite):
    """Тот же силуэт, другой цвет — похожесть обязана просесть, иначе перебор
    ранжирует наугад."""
    assert metrics.similarity(good_sprite, gameplay_colored_sprite).value < 0.6


def test_похожесть_видит_разницу_силуэта(good_sprite, cropped_sprite):
    assert metrics.similarity(good_sprite, cropped_sprite).value < \
        metrics.similarity(good_sprite, good_sprite).value


def test_похожесть_не_закрывает_дорогу(good_sprite, gameplay_colored_sprite):
    """Непохожий кандидат бывает лучше похожего — решает человек."""
    assert metrics.similarity(good_sprite, gameplay_colored_sprite).severity == metrics.WARN


def test_похожесть_считается_только_когда_есть_основа(good_sprite):
    without = metrics.evaluate(good_sprite, "проба", "00")
    with_ref = metrics.evaluate(good_sprite, "проба", "00", reference=good_sprite)
    assert "similarity" not in {c.name for c in without.checks}
    assert "similarity" in {c.name for c in with_ref.checks}


@pytest.mark.parametrize("kind_cutout,expected", [
    (True, {"coverage", "edge_touch", "centering", "fragments", "debris",
            "specks", "squint", "palette_leak", "palette_fit", "backdrop_contrast"}),
    (False, {"opaque", "detail_load", "palette_leak", "palette_fit"}),
])
def test_состав_проверок_зависит_от_вида(good_sprite, kind_cutout, expected):
    """Спрайт и фон проверяются разным. Требовать вырезанного фона от поляны —
    значит заворачивать все поляны подряд."""
    report = evaluate(good_sprite, cutout=kind_cutout)
    assert {c.name for c in report.checks} == expected
