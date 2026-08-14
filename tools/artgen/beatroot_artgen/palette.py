"""Палитра проекта BEATROOT.

Разделена на два непересекающихся набора:

  ENVIRONMENT — мир. Тёплые земляные тона, низкая насыщенность, HD-пиксель.
  GAMEPLAY    — ноты, шкалы, индикаторы. Холодные, максимально насыщенные.

Правило (GDD §11.1.1): ни один цвет из GAMEPLAY не имеет права появиться
в окружении. Это единственное, что позволяет держать одновременно приглушённый
живописный стиль и мгновенную читаемость ноты в ритм-бою.

Проверяется командой `artgen palette --check`.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .color import chroma, contrast_ratio, hex_to_rgb, oklab_distance, to_oklab

# Минимальное перцептивное расстояние между любым игровым и любым цветом мира.
# 0.15 в OKLab — уверенно различимая разница даже боковым зрением.
MIN_SEPARATION = 0.15

# Игровые цвета должны быть насыщеннее любого цвета мира.
# Порог 0.135, а не выше: у голубого в OKLab низкий потолок насыщенности,
# он физически не берёт 0.18, оставаясь ярким. Гарантию даёт не насыщенность
# сама по себе, а MIN_SEPARATION вместе с контрастом.
MIN_GAMEPLAY_CHROMA = 0.135
MAX_ENVIRONMENT_CHROMA = 0.13

# Рампы мира: от тёмного к светлому, по 5 ступеней.
ENVIRONMENT: dict[str, list[str]] = {
    "soil":    ["#2E1E17", "#4A3122", "#6B4630", "#8C5F41", "#A87A56"],
    "wood":    ["#3A2A1C", "#5C4229", "#7D5C3A", "#9C7A50", "#BA9A6D"],
    "stone":   ["#2B2A28", "#4A4844", "#6B6862", "#8D8982", "#ADA99F"],
    "foliage": ["#182619", "#24391F", "#33512A", "#446B36", "#578744"],
    "grass":   ["#2F4A24", "#446A31", "#5C8A3F", "#78A852", "#97C46A"],
    "olive":   ["#3A3A1E", "#56552C", "#74713C", "#93904F", "#B0AE68"],
    # Вода намеренно уведена в бирюзу, а не в синеву: синий зарезервирован
    # под щит, и пруд не имеет права с ним спорить
    "water":   ["#17262A", "#253E42", "#345A5C", "#457B78", "#5D9A93"],
    # Верхняя ступень притушена — чистое белое нужно для «идеального» тайминга
    "warm":    ["#6B5340", "#90735A", "#B39578", "#C9AF8E", "#DCC7A4"],
    "skin":    ["#5C3A2A", "#8A5A40", "#B07C58", "#D0A078", "#E8C6A0"],
}

# Игровые цвета. Холодные и неоновые — в земляном мире таких нет физически.
GAMEPLAY: dict[str, str] = {
    "note_beat":   "#00E5FF",  # обычная нота
    "note_shield": "#2E9BFF",  # щит
    "note_skill":  "#FF6BDE",  # скилл
    "note_snack":  "#B87AFF",  # перекус
    "windup":      "#FF5C7A",  # замах монстра, единственный «тревожный» цвет
    "perfect":     "#FFFFFF",  # идеальный тайминг
    "bar_groove":  "#1ED8FF",  # шкала Ритма игрока
    "bar_vibe":    "#FF57C4",  # шкала Настроя монстра
}

# Фон боя притемняется и обесцвечивается, чтобы не спорить с нотами (GDD §11.1.1)
BATTLE_DIM = 0.30
BATTLE_DESATURATE = 0.30


def environment_colors() -> dict[str, str]:
    return {f"{name}_{i}": c for name, ramp in ENVIRONMENT.items() for i, c in enumerate(ramp)}


def all_colors() -> dict[str, str]:
    return {**environment_colors(), **{f"ui_{k}": v for k, v in GAMEPLAY.items()}}


def check() -> list[str]:
    """Проверить палитру. Пустой список — палитра соблюдает правило."""
    problems: list[str] = []

    env = environment_colors()
    env_rgb = np.array([hex_to_rgb(c) for c in env.values()])
    env_lab = to_oklab(env_rgb)

    for name, hex_c in GAMEPLAY.items():
        rgb = hex_to_rgb(hex_c)
        lab = to_oklab(np.array(rgb))

        dists = oklab_distance(env_lab, lab[None, :])
        i = int(np.argmin(dists))
        if dists[i] < MIN_SEPARATION:
            near = list(env)[i]
            problems.append(
                f"{name} {hex_c}: слишком близок к цвету мира {near} {list(env.values())[i]} "
                f"(расстояние {dists[i]:.3f} < {MIN_SEPARATION})"
            )

        # perfect намеренно белый: это вспышка, а не цвет, насыщенность не требуется
        if name != "perfect" and chroma(rgb) < MIN_GAMEPLAY_CHROMA:
            problems.append(
                f"{name} {hex_c}: насыщенность {chroma(rgb):.3f} ниже "
                f"порога {MIN_GAMEPLAY_CHROMA} — потеряется на фоне"
            )

    for name, hex_c in env.items():
        c = chroma(hex_to_rgb(hex_c))
        if c > MAX_ENVIRONMENT_CHROMA:
            problems.append(
                f"мир {name} {hex_c}: насыщенность {c:.3f} выше "
                f"порога {MAX_ENVIRONMENT_CHROMA} — начнёт спорить с нотами"
            )

    # Тест «размытого скриншота»: нота обязана отличаться от типового фона
    # не только цветом, но и яркостью — на мелком экране цвет теряется первым.
    backdrop = hex_to_rgb(ENVIRONMENT["foliage"][2])
    for name, hex_c in GAMEPLAY.items():
        ratio = contrast_ratio(hex_to_rgb(hex_c), backdrop)
        if ratio < 3.0:
            problems.append(
                f"{name} {hex_c}: контраст к типовому фону всего {ratio:.2f}:1 "
                f"(нужно от 3:1) — пропадёт на размытом кадре"
            )

    return problems


def report() -> str:
    """Человекочитаемая сводка по разделению палитр."""
    env = environment_colors()
    env_rgb = np.array([hex_to_rgb(c) for c in env.values()])
    env_lab = to_oklab(env_rgb)
    backdrop = hex_to_rgb(ENVIRONMENT["foliage"][2])

    lines = [f"{'цвет':14} {'hex':9} {'до мира':>8} {'насыщ.':>7} {'контраст':>9}"]
    for name, hex_c in GAMEPLAY.items():
        rgb = hex_to_rgb(hex_c)
        d = float(np.min(oklab_distance(env_lab, to_oklab(np.array(rgb))[None, :])))
        lines.append(
            f"{name:14} {hex_c:9} {d:8.3f} {chroma(rgb):7.3f} "
            f"{contrast_ratio(rgb, backdrop):8.2f}:1"
        )
    return "\n".join(lines)


def save(path: Path) -> None:
    """Выгрузить палитру для Godot и для шага квантования."""
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "environment": ENVIRONMENT,
        "gameplay": GAMEPLAY,
        "battle_dim": BATTLE_DIM,
        "battle_desaturate": BATTLE_DESATURATE,
        "rules": {
            "min_separation_oklab": MIN_SEPARATION,
            "min_gameplay_chroma": MIN_GAMEPLAY_CHROMA,
            "max_environment_chroma": MAX_ENVIRONMENT_CHROMA,
        },
    }
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def quantization_palette() -> np.ndarray:
    """Цвета, к которым приводится сгенерированный арт.

    Только мир: ассеты не должны случайно попасть в игровые цвета.
    """
    return np.array([hex_to_rgb(c) for c in environment_colors().values()])
