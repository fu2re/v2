"""Сборка иконки приложения: вырезанный герой на плашке.

Плашка собирается кодом, а не выпрашивается у модели, по той же причине, что
надпись на заставке и постройки во дворе: композиция — не задача генерации.
Проверено дорого: при попытке нарисовать иконку целиком модель получила шаблон
фона («пустое место, фон во весь кадр»), выполнила его буквально и приклеила
морду медвежонка поверх нарисованной пустыни.

Витрины магазинов накладывают на иконку собственную маску скругления и никогда
не показывают её вплотную к краю. Поэтому здесь квадрат целиком и заметные
поля вокруг героя: то, что уедет под маску, не должно нести смысла.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from .color import hex_to_rgb
from .palette import ENVIRONMENT

## Сторона иконки. 1024 — то, что просят и Google Play, и App Store;
## всё меньшее они делают сами.
SIZE = 1024

## Плашка светлая, из палитры мира. Тёмный корнеплод на ней читается силуэтом,
## а силуэт — единственное, что работает на 48 пикселях витрины.
##
## Соблазн был обратный: сделать плашку тёмной и «богатой». Но и свёкла, и её
## листва в палитре мира тёмные, и на тёмном они слились бы в пятно. Контраст
## тут важнее настроения.
PLATE = hex_to_rgb(ENVIRONMENT["warm"][4])
PLATE_EDGE = hex_to_rgb(ENVIRONMENT["warm"][2])

## Доля стороны, которую занимает герой. Больше — и уши срежет маской витрины.
FILL = 0.78


def compose(subject: Image.Image, size: int = SIZE,
            plate: tuple[int, int, int] = PLATE) -> Image.Image:
    """Положить вырезанного героя по центру плашки."""
    canvas = Image.new("RGBA", (size, size), plate + (255,))

    # Лёгкая виньетка по краю: на плоской заливке иконка выглядит наклейкой,
    # а витрина показывает её среди объёмных соседей
    edge = Image.new("RGBA", (size, size), PLATE_EDGE + (255,))
    mask = Image.linear_gradient("L").resize((size, size))
    canvas = Image.composite(edge, canvas, mask.point(lambda v: int(v * 0.45)))

    art = subject.convert("RGBA")
    box = art.getbbox()
    if box is not None:
        art = art.crop(box)

    # Целый множитель здесь не нужен и вреден: иконка не показывается
    # в пиксельной сетке игры, её масштабирует витрина как хочет,
    # а обрезанный до целого множителя герой не займёт кадр
    target = int(size * FILL)
    scale = target / max(art.width, art.height)
    art = art.resize((max(int(art.width * scale), 1),
                      max(int(art.height * scale), 1)), Image.NEAREST)

    canvas.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return canvas.convert("RGB")


def build(subject: Path, out: Path, size: int = SIZE) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    compose(Image.open(subject), size).save(out)
    return out
