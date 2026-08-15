"""Фикстуры арт-пайплайна: заведомо годные и заведомо сломанные картинки.

Ворота проверяются мутацией, а не зелёным цветом (CLAUDE.md). Каждой проверке
здесь соответствует картинка, сломанная ровно тем способом, который проверка
обязана поймать. Если порог поедет и проверка перестанет ловить свою поломку —
упадёт именно её тест, а не «что-то в наборе».
"""

from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from beatroot_artgen.color import hex_to_rgb
from beatroot_artgen.metrics import battle_backdrop
from beatroot_artgen.palette import ENVIRONMENT, GAMEPLAY

SIZE = 96

# Земляные цвета из палитры мира — то, чем ассеты и должны быть покрашены
BODY = hex_to_rgb(ENVIRONMENT["soil"][3])
DARK = hex_to_rgb(ENVIRONMENT["soil"][1])


def blank() -> np.ndarray:
    return np.zeros((SIZE, SIZE, 4), dtype=np.uint8)


def disc(arr: np.ndarray, cx: float, cy: float, r: float,
         color=BODY, alpha: int = 255) -> np.ndarray:
    ys, xs = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    mask = (xs - cx) ** 2 + (ys - cy) ** 2 <= r ** 2
    arr[mask, :3] = color
    arr[mask, 3] = alpha
    return arr


def to_image(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(arr, mode="RGBA")


@pytest.fixture
def good_sprite() -> Image.Image:
    """Годный спрайт: один компактный объект по центру, земляные цвета,
    заметный на фоне боя, до рамки не достаёт."""
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2 + 4, 26, BODY)
    disc(arr, SIZE / 2, SIZE / 2 - 12, 16, DARK)
    return to_image(arr)


@pytest.fixture
def uncut_background() -> Image.Image:
    """Фон не вырезан: непрозрачен весь кадр."""
    arr = blank()
    arr[..., :3] = hex_to_rgb(ENVIRONMENT["warm"][4])
    arr[..., 3] = 255
    disc(arr, SIZE / 2, SIZE / 2, 26, BODY)
    return to_image(arr)


@pytest.fixture
def cropped_sprite() -> Image.Image:
    """Существо упирается в рамку — в игре это срезанное ухо."""
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2, SIZE * 0.62, BODY)
    return to_image(arr)


@pytest.fixture
def shredded_sprite() -> Image.Image:
    """Вырезка порвала объект: вокруг рассыпаны островки."""
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2, 20, BODY)
    rng = np.random.default_rng(7)
    for _ in range(14):
        cx, cy = rng.integers(6, SIZE - 6, size=2)
        disc(arr, float(cx), float(cy), 2.0, DARK)
    return to_image(arr)


@pytest.fixture
def gameplay_colored_sprite() -> Image.Image:
    """Монстр цветом ноты — прямое нарушение GDD §11.1.1."""
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2, 26, hex_to_rgb(GAMEPLAY["note_beat"]))
    return to_image(arr)


@pytest.fixture
def highlighted_sprite() -> Image.Image:
    """Тот же годный спрайт, но с белым бликом в глазу.

    Белый совпадает с игровым `perfect`, и наивная проверка утечки объявила бы
    брак каждому монстру с бликом. Этот тест держит исключение на месте.
    """
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2, 26, BODY)
    disc(arr, SIZE / 2 - 6, SIZE / 2 - 6, 3, (255, 255, 255))
    return to_image(arr)


@pytest.fixture
def camouflaged_sprite() -> Image.Image:
    """Существо в точности цвета поляны: на размытом кадре исчезает."""
    arr = blank()
    disc(arr, SIZE / 2, SIZE / 2, 26, battle_backdrop())
    return to_image(arr)


@pytest.fixture
def good_backdrop() -> Image.Image:
    """Годный фон поляны: сплошной, мягкие переходы, деталь низкая."""
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    top = np.array(hex_to_rgb(ENVIRONMENT["foliage"][1]), dtype=np.float64)
    bottom = np.array(hex_to_rgb(ENVIRONMENT["grass"][2]), dtype=np.float64)
    t = (ys / (SIZE - 1))[..., None]
    arr = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    arr[..., :3] = (top * (1 - t) + bottom * t).astype(np.uint8)
    arr[..., 3] = 255
    return to_image(arr)


@pytest.fixture
def busy_backdrop() -> Image.Image:
    """Фон с ландшафтной плотностью деталей: на телефоне превратится в кашу."""
    rng = np.random.default_rng(3)
    arr = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    arr[..., :3] = rng.integers(0, 255, size=(SIZE, SIZE, 3), dtype=np.uint8)
    arr[..., 3] = 255
    return to_image(arr)


@pytest.fixture
def holed_backdrop(good_backdrop: Image.Image) -> Image.Image:
    """Фон с дырой — в игре сквозь неё будет видно пустоту."""
    arr = np.array(good_backdrop)
    disc(arr, SIZE / 2, SIZE / 2, 12, BODY, alpha=0)
    return to_image(arr)


@pytest.fixture
def seamed_tile() -> Image.Image:
    """Тайл, у которого края не сходятся: при замощении виден шов."""
    arr = np.zeros((SIZE, SIZE, 4), dtype=np.uint8)
    arr[..., :3] = hex_to_rgb(ENVIRONMENT["soil"][1])
    arr[:, SIZE // 2:, :3] = hex_to_rgb(ENVIRONMENT["warm"][4])
    arr[..., 3] = 255
    return to_image(arr)
