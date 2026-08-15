"""Сборка лобби: двор усадьбы с постройками, как городской экран в «Героях».

Постройки накладываются на фон, а не впечатаны в него. Разница принципиальная:
вплавленную в фон постройку нельзя ни подсветить при наведении, ни заменить,
когда она разовьётся, ни повесить на неё значок «есть урожай». Здесь же
компоновка одна и та же и для картинки-превью, и для расстановки узлов
в сцене — координаты берутся из одной таблицы.

Глубина изображается размером и высотой: чем дальше постройка, тем она выше
в кадре и меньше. Лес стоит дальше всех, грядки — ближе всех.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image

## Экран игры (project.godot: портрет 1080×1920)
SCREEN = (1080, 1920)


@dataclass(frozen=True)
class Spot:
    """Место постройки во дворе.

    `x` — доля ширины экрана до ЦЕНТРА постройки.
    `ground` — доля высоты до её ОСНОВАНИЯ, а не до верхнего края: постройки
    стоят на земле, и равнять их надо по земле, иначе высокий дом «взлетает».
    `zoom` — целый множитель. Дробный размыл бы пиксельную сетку.
    `scene` — куда ведёт нажатие. Хранится здесь же, чтобы расстановка и
    назначение не разъезжались по разным файлам.
    """

    asset: str
    x: float
    ground: float
    zoom: int
    title: str
    scene: str


# Раскладка двора. Глубина изображается высотой основания и размером: лес
# дальше всех и мельче, грядки ближе всех и крупнее.
#
# Все основания лежат НИЖЕ линии горизонта фона (она примерно на 0.55). Первая
# раскладка ставила лес на 0.44 — это пришлось на дальнюю кромку леса, и его
# собственное пятно земли зависло в воздухе островом. На дворе постройка обязана
# стоять на дворе, а не на нарисованном лесу.
#
# Верхняя треть намеренно оставлена пустой: там пойдёт полоса интерфейса
# с валютами и кнопкой настроек.
LAYOUT: tuple[Spot, ...] = (
    Spot("building_forest", 0.50, 0.60, 3, "Лес",
         "res://scenes/run/RunFeed.tscn"),
    Spot("building_guardians", 0.23, 0.72, 3, "Дом защитников",
         "res://scenes/collection/Collection.tscn"),
    Spot("building_storehouse", 0.78, 0.71, 3, "Амбар",
         "res://scenes/inventory/Inventory.tscn"),
    # Лавка встаёт в проход между домом и амбаром: середина двора пустовала,
    # а прилавок и должен стоять на виду, а не с краю
    Spot("building_merchant", 0.50, 0.78, 3, "Лавка",
         "res://scenes/merchant/Merchant.tscn"),
    # Множитель 6, а не 4: выбранные грядки низкие и широкие, и на общем
    # множителе передний план терял вес — постройка ближе всех, а выглядела
    # мельче дальнего амбара. Множитель подбирается под конкретный силуэт,
    # общей формулы тут нет.
    Spot("building_garden", 0.50, 0.93, 6, "Огород",
         "res://scenes/farm/Farm.tscn"),
)


def _fill_screen(bg: Image.Image, screen: tuple[int, int]) -> Image.Image:
    """Растянуть фон на экран целым множителем и обрезать лишнее."""
    factor = max(
        (screen[0] + bg.width - 1) // bg.width,
        (screen[1] + bg.height - 1) // bg.height,
        1,
    )
    big = bg.resize((bg.width * factor, bg.height * factor), Image.NEAREST)
    left = (big.width - screen[0]) // 2
    top = (big.height - screen[1]) // 2
    return big.crop((left, top, left + screen[0], top + screen[1]))


def place(canvas: Image.Image, building: Image.Image, spot: Spot,
          screen: tuple[int, int] = SCREEN) -> tuple[int, int, int, int]:
    """Поставить постройку и вернуть её прямоугольник на экране.

    Прямоугольник нужен снаружи: по нему в сцене ставится кнопка. Считать его
    второй раз по своей формуле — верный способ получить кнопку, съехавшую
    относительно картинки.
    """
    img = building.convert("RGBA")

    # Равняем по СОДЕРЖИМОМУ, а не по холсту: вписывание оставляет поля,
    # и постройка, выровненная по краю холста, повиснет над землёй
    box = img.getbbox()
    if box is None:
        return (0, 0, 0, 0)
    img = img.crop(box)

    big = img.resize((img.width * spot.zoom, img.height * spot.zoom), Image.NEAREST)
    left = int(screen[0] * spot.x) - big.width // 2
    top = int(screen[1] * spot.ground) - big.height

    canvas.alpha_composite(big, (left, top))
    return (left, top, big.width, big.height)


def compose(background: Image.Image, buildings: dict[str, Image.Image],
            screen: tuple[int, int] = SCREEN) -> tuple[Image.Image, dict[str, tuple]]:
    """Собрать двор. Возвращает картинку и прямоугольники построек."""
    canvas = _fill_screen(background.convert("RGBA"), screen)

    rects: dict[str, tuple] = {}
    # Порядок важен: дальние ставятся первыми, ближние перекрывают их
    for spot in sorted(LAYOUT, key=lambda s: s.ground):
        img = buildings.get(spot.asset)
        if img is None:
            continue
        rects[spot.asset] = place(canvas, img, spot, screen)

    return canvas.convert("RGB"), rects


def build(background: Path, buildings: dict[str, Path], out: Path) -> dict[str, tuple]:
    image, rects = compose(
        Image.open(background),
        {name: Image.open(path) for name, path in buildings.items()},
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    return rects
