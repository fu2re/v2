"""Двор усадьбы: раскладка построек.

Раскладка задаёт сразу две вещи — где нарисована постройка и где будет кнопка,
которая по ней бьёт. Разъехавшись, они дадут кнопку рядом с домом, а не на нём:
игрок жмёт на дом, ничего не происходит, и понять почему по коду нельзя.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from beatroot_artgen import lobby, manifest

PROJECT_ROOT = Path(__file__).resolve().parents[3]


def test_каждая_постройка_есть_в_манифесте():
    ids = {a.id for a in manifest.load()}
    for spot in lobby.LAYOUT:
        assert spot.asset in ids, f"{spot.asset} нет в манифесте"


def test_каждая_постройка_ведёт_в_существующую_сцену():
    """Мутация, от которой защищаемся: сцену переименовали, лобби ведёт в никуда."""
    for spot in lobby.LAYOUT:
        rel = spot.scene.removeprefix("res://")
        assert (PROJECT_ROOT / rel).exists(), f"{spot.title}: нет {spot.scene}"


def test_у_построек_нет_двух_одинаковых_мест():
    assets = [s.asset for s in lobby.LAYOUT]
    assert len(assets) == len(set(assets))


def test_множитель_целый():
    """Дробный размыл бы пиксельную сетку, ради которой делается вся
    постобработка."""
    for spot in lobby.LAYOUT:
        assert isinstance(spot.zoom, int) and spot.zoom >= 1


def test_все_постройки_стоят_на_дворе():
    """Основание ниже линии горизонта фона. Первая раскладка ставила лес выше,
    и его пятно земли зависло в воздухе островом."""
    for spot in lobby.LAYOUT:
        assert 0.55 < spot.ground <= 1.0, f"{spot.title}: основание {spot.ground}"
        assert 0.0 < spot.x < 1.0


def test_дальние_меньше_ближних():
    """Глубина изображается размером. Если дальняя постройка крупнее ближней,
    двор читается плоским."""
    by_depth = sorted(lobby.LAYOUT, key=lambda s: s.ground)
    zooms = [s.zoom for s in by_depth]
    assert zooms == sorted(zooms), f"размер не растёт с приближением: {zooms}"


def test_постройка_равняется_по_содержимому_а_не_по_холсту():
    """Вписывание оставляет поля. Постройка, выровненная по краю холста,
    повиснет над землёй ровно на величину поля."""
    canvas = Image.new("RGBA", lobby.SCREEN, (0, 0, 0, 255))
    building = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    building.paste(Image.new("RGBA", (40, 20), (200, 150, 100, 255)), (30, 10))

    spot = lobby.Spot("проба", 0.5, 0.5, 2, "Проба", "res://x.tscn")
    left, top, w, h = lobby.place(canvas, building, spot)

    assert (w, h) == (80, 40), "обрезка по содержимому не сработала"
    assert top + h == int(lobby.SCREEN[1] * 0.5), "основание не на линии земли"


def test_возвращённый_прямоугольник_совпадает_с_нарисованным():
    """Кнопка ставится по этому прямоугольнику. Если он врёт, игрок жмёт мимо."""
    canvas = Image.new("RGBA", lobby.SCREEN, (0, 0, 0, 255))
    building = Image.new("RGBA", (60, 60), (0, 0, 0, 0))
    building.paste(Image.new("RGBA", (30, 30), (200, 150, 100, 255)), (15, 15))

    spot = lobby.Spot("проба", 0.5, 0.8, 3, "Проба", "res://x.tscn")
    left, top, w, h = lobby.place(canvas, building, spot)

    painted = canvas.crop((left, top, left + w, top + h))
    assert painted.getbbox() == (0, 0, w, h), "нарисовано не там, где обещано"


def test_ближние_перекрывают_дальних():
    """Порядок отрисовки от дальних к ближним. Иначе дальний лес ляжет
    поверх грядок на переднем плане."""
    background = Image.new("RGBA", (100, 200), (10, 10, 10, 255))
    near, far = (0, 0, 255, 255), (255, 0, 0, 255)

    def block(color):
        img = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
        img.paste(Image.new("RGBA", (40, 40), color), (0, 0))
        return img

    layout = (
        lobby.Spot("далеко", 0.5, 0.60, 1, "Далеко", "res://x.tscn"),
        lobby.Spot("близко", 0.5, 0.62, 1, "Близко", "res://y.tscn"),
    )
    original, lobby.LAYOUT = lobby.LAYOUT, layout
    try:
        image, _ = lobby.compose(background, {"далеко": block(far), "близко": block(near)})
    finally:
        lobby.LAYOUT = original

    # В зоне перекрытия обязан быть ближний
    overlap = image.getpixel((lobby.SCREEN[0] // 2, int(lobby.SCREEN[1] * 0.61)))
    assert overlap[2] > overlap[0], "дальняя постройка перекрыла ближнюю"
