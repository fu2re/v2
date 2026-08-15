"""Манифест графики: что игре нужно нарисовать и каким промптом.

Читает `art/assets.toml` и сверяет его с реальными данными игры. Сверка —
главное здесь: манифест, который расходится с `data/*.tres`, хуже отсутствующего.
Новый монстр в игре без записи об арте превращается в розовый квадрат на экране
игрока, и заметить это на компиляции нельзя.
"""

from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = PROJECT_ROOT / "art" / "assets.toml"

# Какие виды ассетов обязаны один-в-один соответствовать ресурсам игры.
# Ключ — вид из манифеста, значение — каталог с .tres.
DATA_DIRS: dict[str, str] = {
    "monster": "data/monsters",
    "fruit": "data/fruits",
    "gear": "data/gear",
    "cosmetic": "data/cosmetics",
}

_TRES_ID = re.compile(r'^id\s*=\s*"([^"]+)"', re.MULTILINE)
_GLADE_ENUM = re.compile(r"enum\s+Type\s*\{([^}]*)\}")


@dataclass(frozen=True)
class Kind:
    """Общие настройки вида ассета. Стиль задаётся здесь, а не в каждой строке."""

    name: str
    size: int
    variants: int
    gen_width: int
    gen_height: int
    cutout: bool
    style: str
    ## Раскрывать ли ассет в набор грейдов (монстры — да, всё остальное — нет).
    graded: bool = False
    ## Приводить ли к палитре мира. Выключается только для бренда: палитра
    ## приглушена намеренно, и логотип в ней выходит землистым. Всё, что
    ## показывается рядом с нотами, квантуется обязательно.
    quantize: bool = True


@dataclass(frozen=True)
class Grade:
    """Ступень грейда.

    `denoise` — насколько далеко старший грейд имеет право уйти от принятого
    младшего при img2img. У `common` его нет: он рисуется с чистого листа.
    Ноль здесь означал бы «копия», а не «с нуля», поэтому признак — None.
    """

    key: str
    name: str
    modifier: str
    ## Остаток от подхода с img2img. Сейчас не используется: грейды берутся
    ## перебором. Поле сохранено, чтобы вернуть img2img было чем.
    denoise: float | None
    index: int
    ## Ключ грейда-источника. Хранится здесь, а не вычисляется по глобальному
    ## списку: порядок грейдов задан в одном месте и не может разъехаться.
    previous: str | None

    @property
    def is_base(self) -> bool:
        """Базовый — тот, перед которым ничего нет.

        Раньше признаком служил отсутствующий `denoise`, и когда denoise убрали
        вместе с img2img, базовыми молча стали ВСЕ грейды разом: легендарный
        начал перезаписывать sprite_path обычного. Поймал тест.
        """
        return self.previous is None


@dataclass(frozen=True)
class Asset:
    id: str
    kind: Kind
    subject: str
    generated: bool
    note: str
    ## Из какого раздела данных игры ассет родом. Обычно совпадает с видом,
    ## но не всегда: мшистая грядка — косметика по данным и тайл по рисовке.
    data: str
    ## Идентификатор без грейда. Для неградуированных совпадает с id.
    base_id: str = ""
    grade: Grade | None = None

    def __post_init__(self) -> None:
        if not self.base_id:
            object.__setattr__(self, "base_id", self.id)

    def full_subject(self) -> str:
        """Что уходит в промпт: описание, признаки грейда, стиль вида."""
        parts = [self.subject]
        if self.grade and self.grade.modifier:
            parts.append(self.grade.modifier)
        if self.kind.style:
            parts.append(self.kind.style)
        return ", ".join(parts)

    def candidates_dir(self, root: Path = PROJECT_ROOT) -> Path:
        return root / "art" / "candidates" / self.id

    def target_path(self, root: Path = PROJECT_ROOT) -> Path:
        return root / "art" / self.kind.name / f"{self.id}.png"

    def previous_grade_id(self) -> str | None:
        """Ассет, из которого рисуется этот. None — рисуется с чистого листа."""
        if self.grade is None or self.grade.previous is None:
            return None
        return f"{self.base_id}_{self.grade.previous}"


def load_grades(path: Path = MANIFEST_PATH) -> list[Grade]:
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    grades: list[Grade] = []
    previous: str | None = None
    for i, (key, cfg) in enumerate(raw.get("grade", {}).items()):
        denoise = cfg.get("denoise")
        grades.append(Grade(
            key=key,
            name=str(cfg.get("name", key)),
            modifier=str(cfg.get("modifier", "")),
            denoise=None if denoise is None else float(denoise),
            index=i,
            previous=previous,
        ))
        previous = key
    return grades


def load(path: Path = MANIFEST_PATH) -> list[Asset]:
    raw = tomllib.loads(path.read_text(encoding="utf-8"))
    grades = load_grades(path)

    kinds: dict[str, Kind] = {}
    for name, cfg in raw.get("kind", {}).items():
        kinds[name] = Kind(
            name=name,
            size=int(cfg["size"]),
            variants=int(cfg["variants"]),
            gen_width=int(cfg["gen_width"]),
            gen_height=int(cfg["gen_height"]),
            cutout=bool(cfg["cutout"]),
            style=str(cfg.get("style", "")),
            graded=bool(cfg.get("graded", False)),
            quantize=bool(cfg.get("quantize", True)),
        )

    assets: list[Asset] = []
    seen: set[str] = set()
    for entry in raw.get("asset", []):
        base_id = str(entry["id"])
        kind_name = str(entry["kind"])
        if kind_name not in kinds:
            raise ValueError(f"{base_id}: вид '{kind_name}' не описан в [kind.*]")

        kind = kinds[kind_name]
        generated = bool(entry.get("generated", True))
        subject = str(entry.get("subject", ""))
        if generated and not subject:
            raise ValueError(f"{base_id}: нет промпта, хотя ассет генерируется")

        # Градуированный вид раскрывается в набор ассетов по числу грейдов.
        # Неградуированный остаётся один, и grade у него None — так проверки
        # «есть ли грейд» не приходится делать через сравнение со строкой.
        expansion = [(f"{base_id}_{g.key}", g) for g in grades] if (
            kind.graded and generated) else [(base_id, None)]

        for aid, grade in expansion:
            if aid in seen:
                raise ValueError(f"{aid}: дубль в манифесте")
            seen.add(aid)
            assets.append(Asset(
                id=aid,
                kind=kind,
                subject=subject,
                generated=generated,
                note=str(entry.get("note", "")),
                data=str(entry.get("data", kind_name)),
                base_id=base_id,
                grade=grade,
            ))

    return assets


def generated(assets: list[Asset]) -> list[Asset]:
    return [a for a in assets if a.generated]


def by_id(assets: list[Asset]) -> dict[str, Asset]:
    return {a.id: a for a in assets}


def _tres_ids(directory: Path) -> set[str]:
    ids: set[str] = set()
    for f in sorted(directory.glob("*.tres")):
        m = _TRES_ID.search(f.read_text(encoding="utf-8"))
        # Ресурс без поля id — сам по себе поломка данных, а не повод промолчать
        ids.add(m.group(1) if m else f"<{f.name}: нет поля id>")
    return ids


def display_names(root: Path = PROJECT_ROOT) -> dict[str, str]:
    """id -> русское имя из .tres. Ревью идёт по именам, которые видит игрок:
    `brass_bell` в данных — это «Тёплый плащ» на экране, и судить надо плащ."""
    names: dict[str, str] = {}
    for rel in DATA_DIRS.values():
        for f in sorted((root / rel).glob("*.tres")):
            text = f.read_text(encoding="utf-8")
            ident = _TRES_ID.search(text)
            title = re.search(r'^display_name\s*=\s*"([^"]*)"', text, re.MULTILINE)
            if ident and title:
                names[ident.group(1)] = title.group(1)
    return names


def _glade_ids(root: Path) -> set[str]:
    """Типы полян из enum в data/glade.gd — фон нужен каждому."""
    src = (root / "data" / "glade.gd").read_text(encoding="utf-8")
    m = _GLADE_ENUM.search(src)
    if m is None:
        return set()
    names = [n.strip() for n in m.group(1).split(",") if n.strip()]
    return {f"glade_{n.lower()}" for n in names}


def check(assets: list[Asset], root: Path = PROJECT_ROOT) -> list[str]:
    """Сверить манифест с данными игры. Пустой список — расхождений нет."""
    problems: list[str] = []
    known = by_id(assets)

    for kind_name, rel in DATA_DIRS.items():
        directory = root / rel
        if not directory.is_dir():
            problems.append(f"нет каталога {rel} — сверять не с чем")
            continue

        data_ids = _tres_ids(directory)
        # Сверяем по base_id: в игре монстр один, а ассетов у него шесть
        manifest_ids = {a.base_id for a in assets if a.data == kind_name}

        # Косметика бывает не спрайтом (эмоут, эффект нот) — она в манифесте
        # с generated=false и всё равно обязана быть перечислена
        for missing in sorted(data_ids - manifest_ids):
            problems.append(
                f"{rel}/{missing}.tres есть в игре, но не описан в манифесте — "
                f"игрок увидит пустое место"
            )
        for extra in sorted(manifest_ids - data_ids):
            problems.append(
                f"манифест описывает {kind_name} '{extra}', которого нет в {rel} — "
                f"генерация уйдёт впустую"
            )

    for glade in sorted(_glade_ids(root)):
        if glade not in known:
            problems.append(f"тип поляны {glade} без фона в манифесте")

    problems += _check_grades(root)
    return problems


_RARITY_ENUM = re.compile(r"enum\s+Rarity\s*\{([^}]*)\}")


def _check_grades(root: Path) -> list[str]:
    """Грейды манифеста обязаны совпадать с MonsterData.Rarity по составу
    и по порядку. Порядок здесь — это сила: по нему строится цепочка img2img,
    и перепутанный порядок молча породил бы легендарного из обычного."""
    src = (root / "data" / "monster_data.gd").read_text(encoding="utf-8")
    m = _RARITY_ENUM.search(src)
    if m is None:
        return ["в data/monster_data.gd не найден enum Rarity — грейды сверить не с чем"]

    in_game = [n.strip().lower() for n in m.group(1).split(",") if n.strip()]
    in_manifest = [g.key for g in load_grades()]
    if in_game != in_manifest:
        return [
            f"грейды разошлись с MonsterData.Rarity: "
            f"в игре {in_game}, в манифесте {in_manifest}"
        ]
    return []


# Обороты, на которых промпты уже проваливались. Список не выдуман: каждый
# оборот стоил от трёх до семи попыток, пока сущность не назвали прямо.
# Это предупреждения, а не запреты — бывает, что оборот уместен и работает.
_RISKY: tuple[tuple[str, str], ...] = (
    ("creature built of", "сущность описана материалом, а не названа — Топотун стоил семи попыток"),
    ("creature made of", "то же самое: назови зверя, потом материал"),
    ("body is made of", "модель не собирает существо из материала, а подставляет знакомое"),
    ("blob", "«blob» не вещь, а отсутствие формы — Кисель вышел бежевым колобком"),
    ("circlet", "«circlet» модель понимает кольцом: три попытки давали бублик"),
    ("abstract", "абстракция не рисуется, рисуется предмет"),
    ("shape of", "форма чего-то — это не предмет"),
)


def lint(assets: list[Asset]) -> list[str]:
    """Предупредить о промптах, написанных так, как уже не срабатывало."""
    warnings: list[str] = []
    for asset in assets:
        if not asset.generated:
            continue
        low = asset.subject.lower()
        for phrase, reason in _RISKY:
            if phrase in low:
                warnings.append(f"{asset.id}: «{phrase}» — {reason}")
    return warnings


def report(assets: list[Asset]) -> str:
    """Сводка по составу графики."""
    lines = [f"{'вид':10} {'всего':>6} {'генерится':>10} {'вручную':>9} {'кандидатов':>11}"]
    kinds = sorted({a.kind.name for a in assets})
    for kind_name in kinds:
        group = [a for a in assets if a.kind.name == kind_name]
        gen = [a for a in group if a.generated]
        variants = sum(a.kind.variants for a in gen)
        lines.append(
            f"{kind_name:10} {len(group):6} {len(gen):10} "
            f"{len(group) - len(gen):9} {variants:11}"
        )
    total_gen = [a for a in assets if a.generated]
    lines.append(
        f"{'ИТОГО':10} {len(assets):6} {len(total_gen):10} "
        f"{len(assets) - len(total_gen):9} "
        f"{sum(a.kind.variants for a in total_gen):11}"
    )
    return "\n".join(lines)
