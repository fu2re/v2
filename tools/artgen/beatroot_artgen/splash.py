"""Сборка заставки: фон, эмблема, надпись.

Заставка не генерируется целиком, и это не лень пайплайна. Диффузия не умеет
буквы — она рисует похожие на буквы закорючки. То же правило, по которому
вручную рисуются ноты и интерфейс (GDD §11.3): от читаемости надписи зависит
первое впечатление, и отдавать её на волю случая нельзя.

Поэтому части разные по происхождению:

  фон      — генерируется (лес, это предмет, модель его умеет)
  надпись  — набирается ЗДЕСЬ, пиксельными литерами из кода

Эмблема поддерживается, но сейчас не используется: заставка это фон и название.

Литеры в коде, а не шрифтом, по двум причинам. Шрифт пришлось бы лицензировать
под коммерческую игру, а свободного в системе нет. И растровые литеры 5×7,
увеличенные целым множителем, дают ровный пиксель — тот же приём, что во всём
остальном арте, вместо сглаженного контура чужой гарнитуры.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from .color import hex_to_rgb
from .palette import ENVIRONMENT

# Экран игры (project.godot: портрет 1080×1920)
SCREEN = (1080, 1920)

# Литеры 5×7. Нужны только буквы слова BEATROOT — рисовать весь алфавит
# незачем, а неполный алфавит с молчаливым пропуском был бы ловушкой:
# `render_word` падает на незнакомой букве, а не рисует пустоту.
GLYPHS: dict[str, tuple[str, ...]] = {
    "B": ("####.",
          "#...#",
          "#...#",
          "####.",
          "#...#",
          "#...#",
          "####."),
    "E": ("#####",
          "#....",
          "#....",
          "####.",
          "#....",
          "#....",
          "#####"),
    "A": (".###.",
          "#...#",
          "#...#",
          "#####",
          "#...#",
          "#...#",
          "#...#"),
    "T": ("#####",
          "..#..",
          "..#..",
          "..#..",
          "..#..",
          "..#..",
          "..#.."),
    "R": ("####.",
          "#...#",
          "#...#",
          "####.",
          "#..#.",
          "#...#",
          "#...#"),
    "O": (".###.",
          "#...#",
          "#...#",
          "#...#",
          "#...#",
          "#...#",
          ".###."),
}

GLYPH_W, GLYPH_H = 5, 7

TITLE = "BEATROOT"

# Тёмная охра по светлому лесу: надпись ляжет на просвет между стволами,
# а он самый светлый в кадре
INK = hex_to_rgb(ENVIRONMENT["soil"][0])
# Обводка светлая — она отделяет буквы от тёмных стволов по краям кадра.
# На светлом просвете она не видна, и там за отделение отвечает тень.
OUTLINE = hex_to_rgb(ENVIRONMENT["warm"][4])
SHADOW = hex_to_rgb(ENVIRONMENT["wood"][1])


def render_word(word: str, scale: int = 12, spacing: int = 1,
                ink=INK, outline=OUTLINE) -> Image.Image:
    """Набрать слово пиксельными литерами.

    Обводка обязательна: без неё тёмная надпись теряется на тёмных стволах,
    а светлая — на просвете. С обводкой читается на обоих.
    """
    unknown = sorted(set(word) - set(GLYPHS))
    if unknown:
        raise ValueError(f"нет литер для {unknown} — дорисуй их в GLYPHS")

    cells_w = len(word) * GLYPH_W + (len(word) - 1) * spacing
    small = Image.new("RGBA", (cells_w + 2, GLYPH_H + 2), (0, 0, 0, 0))
    px = small.load()

    for n, ch in enumerate(word):
        left = 1 + n * (GLYPH_W + spacing)
        for y, row in enumerate(GLYPHS[ch]):
            for x, cell in enumerate(row):
                if cell == "#":
                    px[left + x, 1 + y] = ink + (255,)

    # Обводка ставится по соседям уже набранного слова: так она обтекает
    # надпись целиком, а не каждую букву отдельно
    outlined = small.copy()
    opx = outlined.load()
    for y in range(small.height):
        for x in range(small.width):
            if px[x, y][3]:
                continue
            near = any(
                0 <= x + dx < small.width and 0 <= y + dy < small.height
                and px[x + dx, y + dy][3]
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
            )
            if near:
                opx[x, y] = outline + (255,)

    return outlined.resize(
        (outlined.width * scale, outlined.height * scale), Image.NEAREST)


def _fill_screen(bg: Image.Image, screen: tuple[int, int]) -> Image.Image:
    """Растянуть фон на экран целым множителем и обрезать лишнее.

    Множитель именно целый: дробный пересчёт размывает пиксельную сетку,
    ради которой вся постобработка и делается.
    """
    factor = max(
        (screen[0] + bg.width - 1) // bg.width,
        (screen[1] + bg.height - 1) // bg.height,
        1,
    )
    big = bg.resize((bg.width * factor, bg.height * factor), Image.NEAREST)
    left = (big.width - screen[0]) // 2
    top = (big.height - screen[1]) // 2
    return big.crop((left, top, left + screen[0], top + screen[1]))


def compose(background: Image.Image, emblem: Image.Image | None = None,
            screen: tuple[int, int] = SCREEN, title: str = TITLE) -> Image.Image:
    """Собрать заставку: фон на весь экран и надпись.

    Эмблема необязательна. Без неё надпись — единственный элемент, и она
    поднимается в верхнюю треть и набирается крупнее: одинокий заголовок,
    прижатый к середине, читается как недоделанный макет.
    """
    canvas = _fill_screen(background.convert("RGBA"), screen)

    badge_bottom = 0
    if emblem is not None:
        # Эмблема целым множителем, примерно в четверть высоты экрана
        factor = max(1, round(screen[1] / 4.5 / max(emblem.width, emblem.height)))
        badge = emblem.convert("RGBA")
        badge = badge.resize((badge.width * factor, badge.height * factor), Image.NEAREST)
        badge_top = int(screen[1] * 0.16)
        canvas.alpha_composite(badge, ((screen[0] - badge.width) // 2, badge_top))
        badge_bottom = badge_top + badge.height + int(screen[1] * 0.02)

    word = render_word(title, scale=max(1, screen[0] // (70 if emblem else 58)))
    if word.width > screen[0] * 0.86:
        scale = screen[0] * 0.86 / word.width
        word = word.resize(
            (int(word.width * scale), int(word.height * scale)), Image.NEAREST)

    left = (screen[0] - word.width) // 2
    top = badge_bottom or int(screen[1] * 0.26)

    # Тень отделяет буквы от светлого просвета, где светлая обводка не видна
    shade = Image.new("RGBA", word.size, (0, 0, 0, 0))
    shade.paste(Image.new("RGBA", word.size, SHADOW + (150,)), (0, 0), word)
    offset = max(2, word.height // 24)
    canvas.alpha_composite(shade, (left + offset, top + offset))
    canvas.alpha_composite(word, (left, top))

    return canvas.convert("RGB")


def build(root: Path, background: Path, emblem: Path | None, out: Path) -> Path:
    splash = compose(Image.open(background),
                     Image.open(emblem) if emblem else None)
    out.parent.mkdir(parents=True, exist_ok=True)
    splash.save(out)
    return out
