"""Цветовые преобразования и метрики.

Расстояние считаем в OKLab, а не в RGB: евклидово расстояние в RGB плохо
соответствует тому, как глаз видит разницу, и правило зарезервированной палитры
на нём проверить нельзя.
"""

from __future__ import annotations

import numpy as np

RGB = tuple[int, int, int]


def hex_to_rgb(value: str) -> RGB:
    v = value.lstrip("#")
    return (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16))


def rgb_to_hex(rgb: RGB) -> str:
    return "#{:02X}{:02X}{:02X}".format(*(int(round(c)) for c in rgb))


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = c / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_oklab(rgb: np.ndarray) -> np.ndarray:
    """sRGB (0..255, форма (..., 3)) -> OKLab (L, a, b)."""
    lin = srgb_to_linear(np.asarray(rgb, dtype=np.float64))
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]

    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    l_, m_, s_ = np.cbrt(l), np.cbrt(m), np.cbrt(s)

    return np.stack([
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    ], axis=-1)


def oklab_distance(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Перцептивное расстояние. ~0.02 — едва различимо, >0.15 — явно разные цвета."""
    return np.linalg.norm(np.asarray(a) - np.asarray(b), axis=-1)


def chroma(rgb: RGB) -> float:
    """Насыщенность в OKLab. Земляные тона дают ~0.02-0.06, неон — >0.15."""
    lab = to_oklab(np.array(rgb))
    return float(np.hypot(lab[1], lab[2]))


def luminance(rgb: RGB) -> float:
    """Относительная яркость по WCAG. Нужна для проверки на размытом кадре."""
    lin = srgb_to_linear(np.array(rgb, dtype=np.float64))
    return float(0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2])


def contrast_ratio(a: RGB, b: RGB) -> float:
    """Контраст по WCAG, от 1 (одинаковые) до 21 (чёрный/белый)."""
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def nearest(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Индексы ближайших цветов палитры для каждого пикселя. rgb: (N, 3)."""
    lab_px = to_oklab(rgb)[:, None, :]
    lab_pal = to_oklab(palette)[None, :, :]
    return np.argmin(oklab_distance(lab_px, lab_pal), axis=1)
