"""Процедурные плейсхолдеры: монстры и фрукты.

Нужны, чтобы Фаза 0 не ждала настоящего арта. Силуэты строятся из эллипсов,
затеняются рампами палитры проекта и приводятся к её цветам — поэтому экран
выглядит цельно, а не как набор цветных прямоугольников.

Форма детерминирована именем: один и тот же монстр всегда выглядит одинаково.
"""

from __future__ import annotations

import hashlib

import numpy as np
from PIL import Image

from .color import hex_to_rgb
from .palette import ENVIRONMENT

SILHOUETTES = ("biped", "quadruped", "flyer", "blob", "serpent")

# Жанр монстра определяет рампу — по цвету видно, с кем имеешь дело
GENRE_RAMP = {
    "rock": "stone",
    "disco": "warm",
    "folk": "wood",
    "electro": "water",
    "hiphop": "olive",
}

FRUIT_RAMP = ("soil", "grass", "warm", "olive", "foliage")


def _seed(name: str) -> np.random.Generator:
    # Именно hashlib, а не hash(): встроенный хеш строк рандомизируется
    # от запуска к запуску, и монстр менял бы облик при каждом старте
    digest = hashlib.sha256(name.encode("utf-8")).digest()
    return np.random.default_rng(int.from_bytes(digest[:8], "big"))


def _ellipse(mask: np.ndarray, cx: float, cy: float, rx: float, ry: float) -> None:
    h, w = mask.shape
    y, x = np.ogrid[:h, :w]
    mask |= ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def _erode(mask: np.ndarray) -> np.ndarray:
    out = mask.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        out &= np.roll(mask, (dy, dx), (0, 1))
    return out


def _body(size: int, silhouette: str, rng: np.random.Generator) -> np.ndarray:
    """Собрать силуэт. Форма симметрична — так существо читается как персонаж."""
    m = np.zeros((size, size), dtype=bool)
    s = size / 100.0
    jitter = lambda a, b: float(rng.uniform(a, b)) * s  # noqa: E731

    if silhouette == "biped":
        _ellipse(m, size / 2, 62 * s, jitter(20, 26), jitter(22, 28))   # туловище
        _ellipse(m, size / 2, 32 * s, jitter(20, 25), jitter(18, 23))   # голова
        for side in (-1, 1):
            _ellipse(m, size / 2 + side * 22 * s, 88 * s, 8 * s, 11 * s)   # ноги
            _ellipse(m, size / 2 + side * 27 * s, 60 * s, 7 * s, 15 * s)   # руки
    elif silhouette == "quadruped":
        _ellipse(m, size / 2, 58 * s, jitter(30, 36), jitter(20, 24))
        _ellipse(m, 30 * s, 38 * s, jitter(17, 21), jitter(16, 20))
        for dx in (-26, -12, 12, 26):
            _ellipse(m, size / 2 + dx * s, 82 * s, 7 * s, 14 * s)
    elif silhouette == "flyer":
        _ellipse(m, size / 2, 50 * s, jitter(16, 20), jitter(18, 22))
        for side in (-1, 1):
            _ellipse(m, size / 2 + side * 32 * s, 42 * s, jitter(20, 26), jitter(11, 15))
        _ellipse(m, size / 2, 74 * s, 9 * s, 12 * s)
    elif silhouette == "blob":
        _ellipse(m, size / 2, 60 * s, jitter(30, 36), jitter(28, 34))
        for _ in range(3):
            _ellipse(m, size / 2 + jitter(-22, 22), 40 * s + jitter(-8, 8),
                     jitter(10, 16), jitter(10, 16))
    else:  # serpent
        for i in range(6):
            t = i / 5.0
            _ellipse(m, size / 2 + np.sin(t * 6.0) * 22 * s, (24 + t * 58) * s,
                     (20 - i * 1.8) * s, (13 - i * 1.0) * s)

    return m


def _shade(mask: np.ndarray, ramp: list[str]) -> np.ndarray:
    """Затенить силуэт: свет сверху, тёмный контур по краю."""
    size = mask.shape[0]
    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    if not mask.any():
        return rgba

    ys = np.where(mask.any(axis=1))[0]
    top, bottom = ys[0], ys[-1]
    span = max(bottom - top, 1)

    # Вертикальный градиент даёт объём без расчёта нормалей
    y_idx = np.arange(size)[:, None].repeat(size, axis=1)
    t = np.clip((y_idx - top) / span, 0.0, 1.0)
    level = np.clip((4 - t * 3.2).round().astype(int), 0, 4)

    outline = mask & ~_erode(mask)
    level[outline] = 0

    colors = np.array([hex_to_rgb(c) for c in ramp], dtype=np.uint8)
    rgba[..., :3] = colors[level]
    rgba[..., 3] = np.where(mask, 255, 0)
    return rgba


def _eyes(rgba: np.ndarray, mask: np.ndarray, rng: np.random.Generator) -> None:
    """Глаза — единственная деталь, которая превращает силуэт в существо."""
    size = mask.shape[0]
    ys = np.where(mask.any(axis=1))[0]
    eye_y = int(ys[0] + (ys[-1] - ys[0]) * rng.uniform(0.22, 0.32))
    gap = int(size * rng.uniform(0.09, 0.14))
    r = max(int(size * 0.035), 2)

    for side in (-1, 1):
        cx = size // 2 + side * gap
        eye = np.zeros((size, size), dtype=bool)
        _ellipse(eye, cx, eye_y, r * 1.3, r * 1.5)
        eye &= mask
        rgba[eye, :3] = (28, 22, 20)
        rgba[eye, 3] = 255

        glint = np.zeros((size, size), dtype=bool)
        _ellipse(glint, cx - r * 0.4, eye_y - r * 0.5, max(r * 0.45, 1), max(r * 0.45, 1))
        glint &= eye
        rgba[glint, :3] = (240, 236, 228)


def hero(name: str = "hero", size: int = 96) -> Image.Image:
    """Человечек: голова, туловище, руки, ноги, волосы.

    Отдельная функция, а не силуэт из SILHOUETTES: герой — не монстр,
    и игрок обязан отличать себя от защитника с первого взгляда.
    Пропорции детские — крупная голова, короткие ноги.
    """
    rng = _seed(f"hero/{name}")
    s = size / 100.0
    cx = size / 2.0

    skin = ENVIRONMENT["skin"]
    clothes = ENVIRONMENT[FRUIT_RAMP[rng.integers(len(FRUIT_RAMP))]]
    hair = ENVIRONMENT["soil"]

    rgba = np.zeros((size, size, 4), dtype=np.uint8)

    # Ноги и руки рисуем первыми — туловище ляжет поверх и скроет стыки
    legs = np.zeros((size, size), dtype=bool)
    for side in (-1, 1):
        _ellipse(legs, cx + side * 11 * s, 84 * s, 7 * s, 14 * s)
    _paint(rgba, legs, clothes[1])

    arms = np.zeros((size, size), dtype=bool)
    for side in (-1, 1):
        _ellipse(arms, cx + side * 25 * s, 58 * s, 6 * s, 15 * s)
    _paint(rgba, arms, skin[2])

    body = np.zeros((size, size), dtype=bool)
    _ellipse(body, cx, 62 * s, 18 * s, 20 * s)
    _paint(rgba, body, clothes[2])

    head = np.zeros((size, size), dtype=bool)
    _ellipse(head, cx, 30 * s, 17 * s, 18 * s)
    _paint(rgba, head, skin[3])

    # Волосы — шапочкой поверх верха головы
    fringe = np.zeros((size, size), dtype=bool)
    _ellipse(fringe, cx, 24 * s, 18 * s, 13 * s)
    fringe &= head
    _paint(rgba, fringe, hair[1])

    _hero_face(rgba, head, size, s, cx)
    return Image.fromarray(rgba, mode="RGBA")


def _paint(rgba: np.ndarray, mask: np.ndarray, colour_hex: str) -> None:
    rgba[mask, :3] = hex_to_rgb(colour_hex)
    rgba[mask, 3] = 255


def _hero_face(rgba: np.ndarray, head: np.ndarray, size: int, s: float, cx: float) -> None:
    for side in (-1, 1):
        eye = np.zeros((size, size), dtype=bool)
        _ellipse(eye, cx + side * 6 * s, 33 * s, 2.6 * s, 3.2 * s)
        eye &= head
        rgba[eye, :3] = (28, 22, 20)
        rgba[eye, 3] = 255

    smile = np.zeros((size, size), dtype=bool)
    _ellipse(smile, cx, 40 * s, 5 * s, 2 * s)
    smile &= head
    rgba[smile, :3] = (120, 70, 60)
    rgba[smile, 3] = 255


def creature(name: str, silhouette: str = "blob", genre: str = "disco",
             size: int = 96) -> Image.Image:
    if silhouette not in SILHOUETTES:
        raise ValueError(f"неизвестный силуэт: {silhouette}. Доступны: {SILHOUETTES}")

    rng = _seed(f"{name}/{silhouette}/{genre}")
    ramp = ENVIRONMENT[GENRE_RAMP.get(genre, "warm")]

    mask = _body(size, silhouette, rng)
    rgba = _shade(mask, ramp)
    _eyes(rgba, mask, rng)
    return Image.fromarray(rgba, mode="RGBA")


def fruit(name: str, size: int = 48) -> Image.Image:
    rng = _seed(f"fruit/{name}")
    ramp = ENVIRONMENT[FRUIT_RAMP[rng.integers(len(FRUIT_RAMP))]]
    s = size / 100.0

    mask = np.zeros((size, size), dtype=bool)
    _ellipse(mask, size / 2, 60 * s, rng.uniform(26, 33) * s, rng.uniform(28, 35) * s)
    lobes = int(rng.integers(0, 3))
    for i in range(lobes):
        _ellipse(mask, size / 2 + (i - 0.5) * 18 * s, 52 * s, 15 * s, 17 * s)

    rgba = _shade(mask, ramp)

    leaf = np.zeros((size, size), dtype=bool)
    _ellipse(leaf, size / 2 + 7 * s, 20 * s, 11 * s, 5 * s)
    rgba[leaf, :3] = hex_to_rgb(ENVIRONMENT["grass"][2])
    rgba[leaf, 3] = 255

    return Image.fromarray(rgba, mode="RGBA")


def upscale(img: Image.Image, factor: int) -> Image.Image:
    """Увеличение nearest neighbour — единственный способ не размыть пиксель."""
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)
