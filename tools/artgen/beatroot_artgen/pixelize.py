"""Постобработка сгенерированного арта: вырезка фона, даунскейл, квантование.

Это шаг, который превращает разрозненные генерации в единый стиль (GDD §11.3).
Модель рисует живопись в высоком разрешении — пиксель делается здесь.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

from .color import nearest, oklab_distance, to_oklab
from .palette import quantization_palette


def remove_background_ml(img: Image.Image) -> Image.Image | None:
    """Вырезать фон нейросетевой сегментацией. None, если rembg не установлен.

    Нужно потому, что на дистиллированных моделях (Turbo и подобных) промпт
    «isolated on plain white background» не работает: при cfg 1.0 негативный
    промпт инертен, и модель всё равно рисует сцену. Заливка от краёв на такой
    картинке бессильна — вырезать нечего.

    Ставится отдельно:  uv sync --extra cutout
    """
    try:
        from rembg import remove
    except ImportError:
        return None
    return remove(img.convert("RGBA"))


def cutout_background(arr: np.ndarray, tolerance: float = 0.10) -> np.ndarray:
    """Убрать плоский фон заливкой от краёв. Возвращает маску «это объект».

    Заливка именно от краёв, а не отбор по цвету всей картинки: иначе белые
    пятна внутри существа (блик в глазу, зубы) тоже станут дырами.

    Работать этим нужно на уже уменьшенной картинке — на 1024×1024 заливка
    сходится долго, а на 96×96 мгновенно.
    """
    h, w = arr.shape[:2]
    lab = to_oklab(arr[..., :3])

    # Цвет фона берём как медиану рамки — устойчиво к случайным деталям с краю
    border = np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])
    bg = np.median(border, axis=0)

    similar = oklab_distance(lab, bg[None, None, :]) < tolerance

    filled = np.zeros((h, w), dtype=bool)
    filled[0], filled[-1] = similar[0], similar[-1]
    filled[:, 0], filled[:, -1] = similar[:, 0], similar[:, -1]

    while True:
        grown = filled.copy()
        for axis, shift in ((0, 1), (0, -1), (1, 1), (1, -1)):
            grown |= np.roll(filled, shift, axis=axis)
        grown &= similar
        if np.array_equal(grown, filled):
            break
        filled = grown

    return ~filled


def pixelize(img: Image.Image, target: int = 96, palette: np.ndarray | None = None,
             alpha_cutoff: int = 128, remove_background: bool = True) -> Image.Image:
    """Привести картинку к пиксель-виду в палитре проекта.

    target — длинная сторона результата в пикселях.
    """
    img = img.convert("RGBA")

    # Сегментацию гоним ДО уменьшения: на 768×768 модель видит объект,
    # на 96×96 уже нет
    if remove_background:
        cut = remove_background_ml(img)
        if cut is not None:
            img = cut

    # BOX усредняет блоки — деталь превращается в цвет пикселя,
    # а не выбрасывается, как при NEAREST
    scale = target / max(img.width, img.height)
    small = img.resize(
        (max(int(round(img.width * scale)), 1), max(int(round(img.height * scale)), 1)),
        Image.BOX,
    )

    arr = np.array(small)
    rgb, alpha = arr[..., :3], arr[..., 3]

    # Полупрозрачные края режем жёстко: мягкая альфа читается как размытие
    # и убивает ощущение пикселя
    solid = alpha >= alpha_cutoff
    if remove_background and solid.all():
        solid = cutout_background(arr)

    pal = quantization_palette() if palette is None else palette
    idx = nearest(rgb.reshape(-1, 3), pal)
    quantized = pal[idx].reshape(rgb.shape).astype(np.uint8)

    out = np.zeros_like(arr)
    out[..., :3] = quantized
    out[..., 3] = np.where(solid, 255, 0)
    out[~solid] = 0

    return Image.fromarray(out, mode="RGBA")


def process_file(src: Path, dst: Path, target: int = 96,
                 remove_background: bool = True) -> Image.Image:
    img = pixelize(Image.open(src), target=target, remove_background=remove_background)
    dst.parent.mkdir(parents=True, exist_ok=True)
    img.save(dst)
    return img
