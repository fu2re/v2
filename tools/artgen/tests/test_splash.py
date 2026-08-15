"""Заставка: надпись, эмблема, фон.

Надпись — единственная часть арта, набранная кодом, а не сгенерированная
и не нарисованная в редакторе. Значит она и ломается по-своему: молча,
если в слове окажется буква, которой нет в наборе литер.
"""

from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from beatroot_artgen import splash


def test_литеры_есть_на_всё_название():
    """Мутация, от которой защищаемся: название поменяли, литеру дорисовать
    забыли, и заставка ушла в билд с дырой вместо буквы."""
    assert set(splash.TITLE) <= set(splash.GLYPHS)


def test_незнакомая_буква_роняет_а_не_рисует_пустоту():
    with pytest.raises(ValueError, match="нет литер"):
        splash.render_word("BEATROOTZ")


def test_все_литеры_одного_размера():
    """Разъехавшийся размер сдвинул бы всё слово, и заметить это можно было бы
    только глазами на готовой заставке."""
    for name, glyph in splash.GLYPHS.items():
        assert len(glyph) == splash.GLYPH_H, f"{name}: не {splash.GLYPH_H} строк"
        assert {len(row) for row in glyph} == {splash.GLYPH_W}, f"{name}: рваная ширина"


def test_литеры_непустые():
    for name, glyph in splash.GLYPHS.items():
        assert any("#" in row for row in glyph), f"{name}: пустая литера"


def test_надпись_растёт_с_масштабом():
    small = splash.render_word("BEAT", scale=2)
    big = splash.render_word("BEAT", scale=8)
    assert big.width == small.width * 4


def test_надпись_обведена():
    """Без обводки тёмные буквы теряются на тёмных стволах по краям кадра."""
    word = splash.render_word("BEAT", scale=1)
    colors = {tuple(p[:3]) for p in np.array(word).reshape(-1, 4) if p[3]}
    assert splash.INK in colors
    assert splash.OUTLINE in colors


def test_заставка_ровно_в_размер_экрана():
    bg = Image.new("RGBA", (328, 480), (120, 100, 80, 255))
    emblem = Image.new("RGBA", (64, 64), (90, 70, 50, 255))
    assert splash.compose(bg, emblem).size == splash.SCREEN


def test_фон_растягивается_целым_множителем():
    """Дробный пересчёт размывает пиксельную сетку, ради которой делается
    вся постобработка."""
    bg = Image.new("RGBA", (100, 100), (0, 0, 0, 255))
    filled = splash._fill_screen(bg, (300, 300))
    assert filled.size == (300, 300)

    # При множителе 3 каждый исходный пиксель обязан стать ровно блоком 3×3
    bg.putpixel((0, 0), (255, 0, 0, 255))
    filled = splash._fill_screen(bg, (300, 300))
    block = np.array(filled)[0:3, 0:3, 0]
    assert (block == 255).all()


def test_заставка_не_прозрачна():
    """Заставка показывается первой; дыра в ней — это чёрный провал на экране."""
    bg = Image.new("RGBA", (328, 480), (120, 100, 80, 255))
    emblem = Image.new("RGBA", (64, 64), (90, 70, 50, 0))
    assert splash.compose(bg, emblem).mode == "RGB"
