"""Отрисовка листа палитры — визуальная проверка стиля."""

from __future__ import annotations

import numpy as np
from PIL import Image

from .color import hex_to_rgb
from .palette import BATTLE_DESATURATE, BATTLE_DIM, ENVIRONMENT, GAMEPLAY

CELL = 48
PAD = 8


def _row(colors: list[str]) -> np.ndarray:
    row = np.zeros((CELL, CELL * len(colors), 3), dtype=np.uint8)
    for i, c in enumerate(colors):
        row[:, i * CELL:(i + 1) * CELL] = hex_to_rgb(c)
    return row


def dim(rgb: np.ndarray) -> np.ndarray:
    """Как выглядит мир в бою: притемнён и обесцвечен (GDD §11.1.1)."""
    grey = rgb.mean(axis=-1, keepdims=True)
    mixed = rgb * (1 - BATTLE_DESATURATE) + grey * BATTLE_DESATURATE
    return (mixed * (1 - BATTLE_DIM)).astype(np.uint8)


def render() -> Image.Image:
    env_rows = [_row(ramp) for ramp in ENVIRONMENT.values()]
    ui = _row(list(GAMEPLAY.values()))
    width = max(max(r.shape[1] for r in env_rows), ui.shape[1])

    blocks: list[np.ndarray] = []
    for row in env_rows:
        padded = np.zeros((CELL, width, 3), dtype=np.uint8)
        padded[:, :row.shape[1]] = row
        blocks.append(padded)
        blocks.append(np.zeros((PAD, width, 3), dtype=np.uint8))

    blocks.append(np.zeros((PAD * 2, width, 3), dtype=np.uint8))

    # Игровые цвета — на притемнённом фоне боя, как их увидит игрок
    backdrop = dim(np.full((CELL, width, 3), hex_to_rgb(ENVIRONMENT["foliage"][2]), dtype=np.uint8))
    backdrop[:, :ui.shape[1]] = ui
    blocks.append(backdrop)
    blocks.append(np.zeros((PAD, width, 3), dtype=np.uint8))

    # Та же рампа мира в боевом притемнении — видно, насколько отступает фон
    blocks.append(dim(blocks[0]))

    return Image.fromarray(np.vstack(blocks), mode="RGB")
