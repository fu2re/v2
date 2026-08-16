"""Автоматические ворота: отсев брака до того, как на него потратят внимание.

Смысл слоя — дешёвая проверка перед дорогой. Генерация даёт сотню кандидатов,
и большая часть брака в них механическая: невырезанный фон, обрезанный краем
кадра силуэт, каша из двух существ, крошево после квантования. Всё это видно
арифметикой, и незачем показывать это ни модели, ни человеку.

Чего этот слой НЕ умеет и не должен: судить, похож ли зверь на медведя, милый
ли он и годится ли для семи лет. Это следующая ступень (ревью Клодом) и
последняя (ревью глазами).

Пороги подобраны на процедурных плейсхолдерах и на заведомо сломанных картинках
из tests/. Меняя порог, прогоняй tests — они держат его снизу и сверху.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageFilter

from .color import contrast_ratio, hex_to_rgb, nearest, oklab_distance, to_oklab
from .palette import BATTLE_DESATURATE, BATTLE_DIM, ENVIRONMENT, GAMEPLAY, quantization_palette

# Провал закрывает кандидату дорогу дальше. Замечание не закрывает: его видно
# в галерее, и решает человек. Разделение нужно, чтобы ворота не выкидывали
# ассет за вкусовщину — они на неё не способны.
FAIL = "провал"
WARN = "замечание"


@dataclass(frozen=True)
class Check:
    name: str
    value: float
    ok: bool
    severity: str
    detail: str

    def as_dict(self) -> dict:
        return {
            "name": self.name,
            "value": round(self.value, 4),
            "ok": self.ok,
            "severity": self.severity,
            "detail": self.detail,
        }


@dataclass
class Report:
    asset_id: str
    variant: str
    checks: list[Check] = field(default_factory=list)

    @property
    def failures(self) -> list[Check]:
        return [c for c in self.checks if not c.ok and c.severity == FAIL]

    @property
    def warnings(self) -> list[Check]:
        return [c for c in self.checks if not c.ok and c.severity == WARN]

    @property
    def passed(self) -> bool:
        return not self.failures

    def as_dict(self) -> dict:
        return {
            "asset_id": self.asset_id,
            "variant": self.variant,
            "passed": self.passed,
            "checks": [c.as_dict() for c in self.checks],
        }


# ─────────────────────────────── общий фон боя ───────────────────────────────

def battle_backdrop() -> tuple[int, int, int]:
    """Типовой фон боя: цвет листвы, притемнённый и обесцвеченный (GDD §11.1.1).

    Ассет проверяется именно на нём, а не на белом: на белом читается всё.
    """
    rgb = np.array(hex_to_rgb(ENVIRONMENT["foliage"][2]), dtype=np.float64)
    grey = float(rgb.mean())
    rgb = rgb * (1.0 - BATTLE_DESATURATE) + grey * BATTLE_DESATURATE
    rgb = rgb * (1.0 - BATTLE_DIM)
    return tuple(int(round(c)) for c in rgb)


def on_backdrop(img: Image.Image) -> Image.Image:
    """Положить ассет на фон боя. Так его увидит игрок, так и надо мерить."""
    bg = Image.new("RGBA", img.size, battle_backdrop() + (255,))
    bg.alpha_composite(img.convert("RGBA"))
    return bg.convert("RGB")


# ──────────────────────────────── примитивы ──────────────────────────────────

def _label(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """Связные компоненты по 4-связности. Свой цикл вместо scipy: массивы
    здесь 96×96, а лишняя зависимость в пайплайне дороже пятнадцати строк."""
    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    current = 0
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or labels[y, x]:
                continue
            current += 1
            stack = [(y, x)]
            labels[y, x] = current
            while stack:
                cy, cx = stack.pop()
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = current
                        stack.append((ny, nx))
    return labels, current


def _rms_contrast(grey: np.ndarray) -> float:
    """Разброс яркости. На размытом уменьшенном кадре именно он отвечает
    за то, различим ли силуэт вообще."""
    return float(np.std(grey) / 255.0)


# ───────────────────────────────── проверки ──────────────────────────────────

def _coverage(alpha: np.ndarray) -> Check:
    value = float((alpha > 0).mean())
    # Верх: непрозрачно почти всё — значит фон не вырезан, в игре будет плашка.
    # Низ: вырезка съела существо, остались ошмётки.
    ok = 0.10 <= value <= 0.80
    if value > 0.80:
        detail = f"занято {value:.0%} кадра — фон не вырезан, в игре будет прямоугольник"
    elif value < 0.10:
        detail = f"занято всего {value:.0%} кадра — вырезка съела объект или он крошечный"
    else:
        detail = f"занято {value:.0%} кадра (норма 10–80%)"
    return Check("coverage", value, ok, FAIL, detail)


def _edge_touch(alpha: np.ndarray) -> Check:
    """Объект, упирающийся в рамку, обрезан. В игре это видно как срезанное ухо."""
    solid = alpha > 0
    border = np.concatenate([solid[0], solid[-1], solid[:, 0], solid[:, -1]])
    value = float(border.mean())
    ok = value <= 0.03
    return Check(
        "edge_touch", value, ok, FAIL,
        f"{value:.0%} рамки занято объектом" + ("" if ok else " — силуэт обрезан краем кадра"),
    )


def _centering(alpha: np.ndarray) -> Check:
    """Смещение центра тяжести. Риг собирается от центра, съехавший ассет
    придётся двигать руками на каждом монстре."""
    solid = alpha > 0
    if not solid.any():
        return Check("centering", 1.0, False, FAIL, "пусто — центр считать не от чего")
    h, w = solid.shape
    ys, xs = np.nonzero(solid)
    dy = (ys.mean() - (h - 1) / 2) / (h / 2)
    dx = (xs.mean() - (w - 1) / 2) / (w / 2)
    value = float(np.hypot(dx, dy))
    ok = value <= 0.30
    return Check(
        "centering", value, ok, WARN,
        f"центр смещён на {value:.0%} полукадра" + ("" if ok else " — заметно не по центру"),
    )


def _fragments(alpha: np.ndarray) -> Check:
    """Сколько крупных кусков.

    Порог в 15% площади, а не «любой отдельный кусок»: у фрукта отдельно висит
    листик, у героя — кисти рук, и это нормально. А вот два куска сопоставимого
    размера — это уже либо второе существо в кадре, либо порванный вырезкой силуэт.

    Провал только от трёх кусков: два — повод посмотреть глазами, а не выбросить.
    Медведь, обнимающий контрабас, честно даёт два куска и имеет право жить.
    """
    solid = alpha > 0
    labels, count = _label(solid)
    if count == 0:
        return Check("fragments", 0, False, FAIL, "ни одного объекта")
    sizes = np.bincount(labels.ravel())[1:]
    significant = int((sizes >= 0.15 * solid.sum()).sum())
    ok = significant <= 1
    return Check(
        "fragments", float(significant), ok, FAIL if significant >= 3 else WARN,
        f"крупных кусков: {significant}"
        + ("" if ok else " — лишний объект в кадре или рваный силуэт"),
    )


def _debris(alpha: np.ndarray) -> Check:
    """Островки, оставшиеся от вырезки фона.

    Отдельно от specks: specks видит одиночные пиксели, а вырезка оставляет
    кляксы по пять-десять пикселей — их одиночными не назовёшь, но в игре это
    грязь, висящая рядом с монстром.
    """
    solid = alpha > 0
    if not solid.any():
        return Check("debris", 99.0, False, FAIL, "пусто")
    labels, _ = _label(solid)
    sizes = np.bincount(labels.ravel())[1:]
    value = float((sizes < 0.15 * solid.sum()).sum())
    ok = value <= 6
    return Check(
        "debris", value, ok, FAIL,
        f"мелких островков: {value:.0f}"
        + ("" if ok else " — вырезка оставила мусор вокруг объекта"),
    )


def _specks(alpha: np.ndarray) -> Check:
    """Крошево после квантования: пиксели почти без соседей. Именно оно
    выдаёт «сгенерировано» с первого взгляда."""
    solid = alpha > 0
    if not solid.any():
        return Check("specks", 1.0, False, FAIL, "пусто")
    padded = np.pad(solid, 1)
    neighbours = np.zeros(solid.shape, dtype=np.int32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                neighbours += padded[1 + dy: 1 + dy + solid.shape[0],
                                     1 + dx: 1 + dx + solid.shape[1]].astype(np.int32)
    lonely = solid & (neighbours <= 2)
    value = float(lonely.sum() / solid.sum())
    ok = value <= 0.04
    return Check(
        "specks", value, ok, WARN,
        f"{value:.1%} пикселей висят в воздухе" + ("" if ok else " — края надо чистить"),
    )


def _palette_fit(rgb: np.ndarray, solid: np.ndarray) -> Check:
    """Насколько сильно квантование исказило исходный цвет.

    Большое расстояние значит, что модель ушла из палитры проекта: получившийся
    ассет будет «в цвете игры», но форму и объём квантование помнёт.
    """
    if not solid.any():
        return Check("palette_fit", 1.0, False, FAIL, "пусто")
    pal = quantization_palette()
    px = rgb[solid].reshape(-1, 3)
    idx = nearest(px, pal)
    value = float(np.mean(oklab_distance(to_oklab(px), to_oklab(pal[idx]))))
    ok = value <= 0.06
    return Check(
        "palette_fit", value, ok, WARN,
        f"среднее расстояние до палитры {value:.3f}"
        + ("" if ok else " — модель рисует мимо палитры, квантование мнёт форму"),
    )


def _palette_leak(rgb: np.ndarray, solid: np.ndarray) -> Check:
    """Игровой цвет в окружении — прямое нарушение GDD §11.1.1.

    По построению ноль: `quantization_palette()` отдаёт только цвета мира,
    а они гарантированно дальше MIN_SEPARATION от игровых. Проверка стоит здесь
    не ради генерации, а как страховка от правки палитры: если однажды в набор
    квантования попадёт игровой цвет, это вскроется тут, а не в бою, где нота
    перестанет читаться на шкуре монстра.

    Белый (`perfect`) из набора исключён намеренно. Это вспышка идеального
    попадания, а не зарезервированный тон: блик в глазу монстра тоже почти белый
    и ничему не мешает. Палитра относится к нему так же — `check()` не требует
    от него насыщенности.
    """
    if not solid.any():
        return Check("palette_leak", 1.0, False, FAIL, "пусто")
    game = np.array([hex_to_rgb(c) for k, c in GAMEPLAY.items() if k != "perfect"])
    px = np.unique(rgb[solid].reshape(-1, 3), axis=0)
    d = oklab_distance(to_oklab(px)[:, None, :], to_oklab(game)[None, :, :])
    value = float((d.min(axis=1) < 0.15).mean())
    ok = value == 0.0
    return Check(
        "palette_leak", value, ok, FAIL,
        "игровых цветов нет" if ok else
        f"{value:.0%} цветов ассета неотличимы от игровых — нота потеряется на нём",
    )


def _backdrop_contrast(rgb: np.ndarray, solid: np.ndarray) -> Check:
    """Виден ли ассет на фоне боя вообще."""
    if not solid.any():
        return Check("backdrop_contrast", 1.0, False, FAIL, "пусто")
    mean = tuple(int(round(c)) for c in rgb[solid].reshape(-1, 3).mean(axis=0))
    value = contrast_ratio(mean, battle_backdrop())
    ok = value >= 1.6
    return Check(
        "backdrop_contrast", value, ok, WARN,
        f"контраст к фону боя {value:.2f}:1"
        + ("" if ok else " — сливается с поляной, монстра будет не видно"),
    )


def _squint(img: Image.Image) -> Check:
    """Тест размытого скриншота из GDD §11.1.1, применённый к одному ассету.

    Кладём на фон боя, ужимаем до 30%, размываем — силуэт обязан остаться
    различимым. Меряем разбросом яркости: если после размытия ассет слился
    с поляной, разброс падает почти к нулю.
    """
    scene = on_backdrop(img)
    small = scene.resize(
        (max(int(scene.width * 0.3), 4), max(int(scene.height * 0.3), 4)), Image.BOX
    ).filter(ImageFilter.GaussianBlur(radius=1.0))
    grey = np.array(small.convert("L"), dtype=np.float64)
    value = _rms_contrast(grey)
    ok = value >= 0.04
    return Check(
        "squint", value, ok, FAIL,
        f"разброс яркости на размытом кадре {value:.3f}"
        + ("" if ok else " — силуэт пропадает, когда кадр мелкий"),
    )


def similarity(img: Image.Image, reference: Image.Image) -> Check:
    """Насколько кандидат похож на принятую основу.

    Нужна для перебора: старший грейд рисуется тем же промптом, и годится тот
    кандидат, который вышел тем же зверем. Глазами перебирать восемь картинок
    на грейд бессмысленно, поэтому похожесть считается и кандидаты по ней
    сортируются.

    Считается по двум вещам сразу, потому что порознь обе обманываются:
    силуэт совпадает у любых двух клякс одного размера, а раскладка по палитре
    совпадает у одинаково покрашенных, но по-разному слепленных существ.

    Это ЗАМЕЧАНИЕ, а не ворота: похожесть — цель перебора, но решает человек.
    Непохожий кандидат бывает лучше похожего.
    """
    a = np.array(img.convert("RGBA"))
    b = np.array(reference.convert("RGBA").resize(img.size, Image.NEAREST))

    mask_a, mask_b = a[..., 3] > 0, b[..., 3] > 0
    union = int((mask_a | mask_b).sum())
    iou = float((mask_a & mask_b).sum() / union) if union else 0.0

    pal = quantization_palette()
    hist = []
    for arr, mask in ((a, mask_a), (b, mask_b)):
        if not mask.any():
            hist.append(np.zeros(len(pal)))
            continue
        idx = nearest(arr[..., :3][mask].reshape(-1, 3), pal)
        hist.append(np.bincount(idx, minlength=len(pal)) / len(idx))

    # Полное расхождение распределений даёт 1.0, поэтому совпадение — это 1 - d/2
    palette_match = 1.0 - float(np.abs(hist[0] - hist[1]).sum()) / 2.0

    value = 0.5 * iou + 0.5 * palette_match
    ok = value >= 0.55
    return Check(
        "similarity", value, ok, WARN,
        f"похожесть на основу {value:.0%} (силуэт {iou:.0%}, палитра {palette_match:.0%})"
        + ("" if ok else " — на основу не похож, перебирай дальше"),
    )


def _opaque(alpha: np.ndarray) -> Check:
    """Для фонов и тайлов: дыр быть не должно."""
    value = float((alpha > 0).mean())
    ok = value >= 0.999
    return Check(
        "opaque", value, ok, FAIL,
        "фон сплошной" if ok else f"в фоне дыры: непрозрачно {value:.1%}",
    )


def _detail_load(img: Image.Image) -> Check:
    """Насколько фон перегружен деталью.

    Прямое требование GDD §11.1: портретный телефон с ландшафтной плотностью
    деталей превращается в кашу, и ноты в ней тонут. Меряем долей пикселей
    с сильным перепадом к соседу.
    """
    grey = np.array(img.convert("L"), dtype=np.float64)
    gy, gx = np.gradient(grey)
    edges = np.hypot(gx, gy)
    value = float((edges > 24).mean())
    ok = value <= 0.28
    return Check(
        "detail_load", value, ok, WARN,
        f"резких перепадов {value:.0%}"
        + ("" if ok else " — фон слишком дробный, ноты в нём утонут"),
    )


def _tile_seam(img: Image.Image) -> Check:
    """Стыкуется ли тайл сам с собой. Грядка мостится, шов виден сразу."""
    arr = np.array(img.convert("RGB"), dtype=np.float64)
    horizontal = float(np.abs(arr[:, 0] - arr[:, -1]).mean())
    vertical = float(np.abs(arr[0] - arr[-1]).mean())
    value = max(horizontal, vertical)
    ok = value <= 28.0
    return Check(
        "tile_seam", value, ok, WARN,
        f"расхождение краёв {value:.0f}/255"
        + ("" if ok else " — при замощении будет виден шов"),
    )


# ────────────────────────────────── прогон ───────────────────────────────────

def evaluate(img: Image.Image, asset_id: str, variant: str,
             cutout: bool = True, tiling: bool = False,
             reference: Image.Image | None = None,
             world: bool = True) -> Report:
    """Прогнать кандидата через все применимые проверки.

    `reference` — принятая основа для старшего грейда. Если она есть,
    добавляется похожесть, по которой кандидаты потом сортируются.

    `world=False` — ассет бренда: он намеренно вне палитры мира, и проверять
    его на попадание в неё бессмысленно. Требовать от логотипа приглушённости
    значит требовать ровно того, за что его и забраковали.
    """
    img = img.convert("RGBA")
    arr = np.array(img)
    rgb, alpha = arr[..., :3], arr[..., 3]
    solid = alpha > 0

    report = Report(asset_id=asset_id, variant=variant)

    if cutout:
        report.checks += [
            _coverage(alpha),
            _edge_touch(alpha),
            _centering(alpha),
            _fragments(alpha),
            _debris(alpha),
            _specks(alpha),
            _squint(img),
        ]
    else:
        report.checks.append(_opaque(alpha))
        report.checks.append(_detail_load(img))
        if tiling:
            report.checks.append(_tile_seam(img))

    if world:
        report.checks += [
            _palette_leak(rgb, solid),
            _palette_fit(rgb, solid),
        ]
    if cutout:
        report.checks.append(_backdrop_contrast(rgb, solid))
    if reference is not None:
        report.checks.append(similarity(img, reference))

    return report
