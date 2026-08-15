"""Манифест, сиды и перенос в игру.

Проверяется наблюдаемый результат, а не промежуточные поля: не «в словаре
решений появился ключ», а «файл лежит там, где его ищет игра, и .tres на него
показывает» (CLAUDE.md).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest
from PIL import Image

from beatroot_artgen import batch, manifest, promote, review

PROJECT_ROOT = Path(__file__).resolve().parents[3]


# ─────────────────────────────── манифест ───────────────────────────────────

def test_манифест_проекта_сходится_с_данными():
    assets = manifest.load()
    assert manifest.check(assets, PROJECT_ROOT) == []


def test_пропавший_из_манифеста_монстр_виден():
    """Мутация: монстр есть в игре, записи об арте нет."""
    assets = [a for a in manifest.load() if a.base_id != "bass_bear"]
    problems = manifest.check(assets, PROJECT_ROOT)
    assert any("bass_bear" in p for p in problems)


def test_лишний_в_манифесте_ассет_виден():
    """Мутация: промпт есть, ресурса в игре нет — генерация уйдёт впустую."""
    import dataclasses

    assets = manifest.load()
    assets.append(dataclasses.replace(assets[0], id="привидение", base_id="привидение"))
    problems = manifest.check(assets, PROJECT_ROOT)
    assert any("привидение" in p for p in problems)


def test_ручная_отрисовка_не_попадает_в_генерацию():
    """Ноты и индикаторы генерации не отдаются никогда (GDD §11.3)."""
    assets = manifest.load()
    ids = {a.id for a in manifest.generated(assets)}
    assert "ui_note_beat" not in ids
    assert "sparkle_notes" not in ids


def test_промпт_собирается_из_описания_и_стиля_вида():
    asset = manifest.by_id(manifest.load())["drum_berry"]
    assert asset.subject in asset.full_subject()
    assert asset.kind.style in asset.full_subject()


# ──────────────────────────────── сиды ──────────────────────────────────────

def test_сид_детерминирован():
    assert batch.seed_for("bass_bear", 1) == batch.seed_for("bass_bear", 1)


def test_варианты_одного_ассета_различаются():
    seeds = {batch.seed_for("bass_bear", i) for i in range(4)}
    assert len(seeds) == 4


def test_новая_попытка_даёт_другие_картинки():
    """Иначе «перегенерировать отклонённое» возвращало бы тот же брак."""
    assert batch.seed_for("bass_bear", 0, attempt=0) != batch.seed_for("bass_bear", 0, attempt=1)


# ───────────────────────────────── грейды ───────────────────────────────────

def test_монстр_раскрывается_в_шесть_грейдов():
    assets = manifest.load()
    bear = [a for a in assets if a.base_id == "bass_bear"]
    assert len(bear) == 6
    assert [a.grade.key for a in bear] == [g.key for g in manifest.load_grades()]


def test_неградуированное_не_раскрывается():
    """Грейд есть у монстра. У груши грейда нет, и раздувать её в шесть
    файлов значит генерировать пять лишних картинок на каждый фрукт."""
    ids = {a.id for a in manifest.load()}
    assert "echo_pear" in ids
    assert "echo_pear_common" not in ids


def test_имя_файла_содержит_грейд():
    """Требование к именованию: {name}_{grade}."""
    asset = manifest.by_id(manifest.load())["bass_bear_epic"]
    assert asset.target_path().name == "bass_bear_epic.png"


def test_базовый_грейд_рисуется_с_нуля():
    base = manifest.by_id(manifest.load())["bass_bear_common"]
    assert base.previous_grade_id() is None
    assert base.grade.is_base


def test_каждый_старший_грейд_опирается_на_предыдущий():
    """Цепочка, а не всё из common: иначе «на основе прошлых грейдов»
    превращается в шесть независимых генераций одного зверя."""
    assets = manifest.by_id(manifest.load())
    assert assets["bass_bear_uncommon"].previous_grade_id() == "bass_bear_common"
    assert assets["bass_bear_rare"].previous_grade_id() == "bass_bear_uncommon"
    assert assets["bass_bear_legendary"].previous_grade_id() == "bass_bear_epic"


def test_шаги_компенсируют_denoise():
    """При img2img сэмплер проходит только долю denoise от заданных шагов.
    У дистиллята их четыре, и на denoise 0.6 остаётся два — первый прогон
    грейдов вышел неотличимым от исходника именно поэтому."""
    from beatroot_artgen.comfy import GenerationRequest, profile_for

    ckpt = "flux1-schnell-fp8.safetensors"
    base = profile_for(ckpt).steps

    scratch = GenerationRequest(subject="x", checkpoint=ckpt).tuned()
    assert scratch.steps == base, "рисование с нуля шаги менять не должно"

    partial = GenerationRequest(subject="x", checkpoint=ckpt,
                                init_image="src.png", denoise=0.6).tuned()
    assert partial.steps > base
    assert partial.steps * 0.6 >= base, "реальной работы всё ещё меньше бюджета"


def test_если_denoise_вернут_он_обязан_расти():
    """img2img сейчас выключен, но поле осталось — вернуть его будет чем.
    Если однажды вернут, свобода обязана расти с грейдом, иначе старшие
    ступени нечем отличить от младших."""
    values = [g.denoise for g in manifest.load_grades() if not g.is_base]
    if any(v is not None for v in values):
        assert all(v is not None for v in values), "denoise задан не всем грейдам"
        assert values == sorted(values), f"denoise не монотонен: {values}"
        assert all(0.0 < v < 1.0 for v in values), "denoise 1.0 — это рисование с нуля"


def test_младшие_грейды_рисуются_тем_же_промптом():
    """Обычный и необычный различать на картинке не нужно — разницу несёт
    метка редкости в интерфейсе. Ступени тратятся только там, где видно."""
    assets = manifest.by_id(manifest.load())
    base = assets["bass_bear_common"].full_subject()
    assert assets["bass_bear_uncommon"].full_subject() == base
    assert assets["bass_bear_rare"].full_subject() == base


def test_с_уникального_монстр_выглядит_сильнее():
    assets = manifest.by_id(manifest.load())
    base = assets["bass_bear_common"].full_subject()
    for key in ("unique", "epic", "legendary"):
        assert assets[f"bass_bear_{key}"].full_subject() != base, f"{key} ничем не отличается"


def test_модификаторы_не_называют_частей_тела():
    """«Наплечник» подразумевает плечи — и модель дорисовала змее лапы,
    четверо кандидатов из восьми вышли ящерицами. Силуэт определяет библиотеку
    танцев, и такая подмена ломает её молча. Монстры бывают змеями и желе.

    Ищем ЦЕЛЫЕ слова, а не подстроки: «charm» (амулет) содержит «arm»,
    но руки не подразумевает, и подстрочная проверка запрещала бы
    совершенно безобидные украшения."""
    forbidden = ("shoulder", "pauldron", "arm", "leg", "hand", "waist", "neck")
    pattern = re.compile(r"\b(" + "|".join(forbidden) + r")s?\b")
    for grade in manifest.load_grades():
        found = pattern.findall(grade.modifier.lower())
        assert not found, f"грейд {grade.key} называет части тела: {found}"


def test_проверка_частей_тела_ловит_настоящее_нарушение():
    """Мутация: проверку легко «починить» до бессмысленной, ослабив шаблон.
    Здесь она обязана поймать ту самую формулировку, что дорисовала змее лапы,
    и обязана пропустить безобидный оберег."""
    pattern = re.compile(r"\b(shoulder|pauldron|arm|leg|hand|waist|neck)s?\b")
    assert pattern.findall("wearing a pauldron on one shoulder")
    assert not pattern.findall("a carved wooden charm, warm earthy colors")


def test_у_легендарного_обязательно_золото():
    """Требование дизайна: у каждого легендарного монстра золотой предмет."""
    for grade in manifest.load_grades():
        if grade.key == "legendary":
            assert "gold" in grade.modifier.lower()
            break
    else:
        raise AssertionError("грейда legendary нет вовсе")


def test_в_палитре_есть_золото():
    """Без рампы золота любое золото квантуется в охру и читается латунью."""
    from beatroot_artgen.palette import ENVIRONMENT, check

    assert "gold" in ENVIRONMENT
    assert check() == [], "рампа золота нарушила правило разделения палитр"


def test_золото_только_легендарному():
    """Как только рампа попала в общий набор, к ней потянулись все тёплые
    светлые пиксели: подсолнух и мотылёк пожелтели целиком. Золото обязано
    оставаться приметой легендарного."""
    from beatroot_artgen.palette import quantization_palette

    assert len(quantization_palette(gold=True)) > len(quantization_palette())


def test_обычный_монстр_квантуется_без_золота():
    """Проверяется наблюдаемый результат: в наборе, которым красят обычного
    монстра, золотых цветов нет вовсе."""
    import numpy as np

    from beatroot_artgen.color import hex_to_rgb
    from beatroot_artgen.palette import ENVIRONMENT, quantization_palette

    plain = {tuple(c) for c in quantization_palette()}
    for hex_c in ENVIRONMENT["gold"]:
        assert hex_to_rgb(hex_c) not in plain


def test_базовым_считается_только_первый_грейд():
    """Признак базового — что перед ним ничего нет.

    Пока он выводился из `denoise`, снятие img2img молча сделало базовыми все
    грейды разом, и легендарный получил право перезаписать sprite_path обычного.
    """
    grades = manifest.load_grades()
    assert [g.is_base for g in grades] == [True] + [False] * (len(grades) - 1)


def test_перебор_даёт_больше_бросков():
    """Четырёх кандидатов мало, чтобы среди них нашёлся похожий на основу."""
    from beatroot_artgen.batch import BRUTE_FORCE_VARIANTS

    assert BRUTE_FORCE_VARIANTS > manifest.by_id(manifest.load())["bass_bear_epic"].kind.variants


def test_грейды_сверяются_с_enum_игры():
    """Порядок грейдов — это сила. Разъехавшись с MonsterData.Rarity,
    он молча построил бы легендарного из обычного."""
    assert manifest.check(manifest.load(), PROJECT_ROOT) == []

    keys = [g.key for g in manifest.load_grades()]
    src = (PROJECT_ROOT / "data" / "monster_data.gd").read_text(encoding="utf-8")
    in_game = re.search(r"enum\s+Rarity\s*\{([^}]*)\}", src).group(1)
    assert [n.strip().lower() for n in in_game.split(",") if n.strip()] == keys


# ──────────────────────────── линтер промптов ───────────────────────────────

def test_линтер_ловит_описание_материалом():
    """Оборот, стоивший Топотуну семи попыток, не должен пройти молча."""
    import dataclasses

    assets = manifest.load()
    broken = dataclasses.replace(
        assets[0], subject="four-legged creature built of mossy river stones")
    warnings = manifest.lint([broken])
    assert warnings and "creature built of" in warnings[0]


def test_текущие_промпты_чисты():
    assert manifest.lint(manifest.load()) == []


# ──────────────────────────── шаблоны промптов ──────────────────────────────
#
# Первый прогон полян ушёл в мусор целиком: к фону применялся шаблон спрайта,
# и модель послушалась буквально — «plain solid white background» дало небо
# цвета пергамента, а «centered full body character» поставило человека
# на все пятнадцать кадров. Для фона, за которым бежит герой, это смертельно.

@pytest.mark.parametrize("checkpoint", ["sd_xl_base_1.0.safetensors",
                                        "flux1-schnell-fp8.safetensors"])
def test_фон_не_просит_белого_фона_и_персонажа(checkpoint):
    from beatroot_artgen.comfy import positive_prompt

    prompt = positive_prompt("лесная поляна", checkpoint, scene=True).lower()
    assert "white background" not in prompt
    assert "isolated" not in prompt
    assert "full body character" not in prompt


@pytest.mark.parametrize("checkpoint", ["sd_xl_base_1.0.safetensors",
                                        "flux1-schnell-fp8.safetensors"])
def test_фон_прямо_запрещает_людей(checkpoint):
    from beatroot_artgen.comfy import positive_prompt

    assert "no people" in positive_prompt("поляна", checkpoint, scene=True).lower()


def test_дистиллят_ставит_запрет_в_начало():
    """У дистиллята cfg 1.0, негативный промпт инертен. Всё критичное обязано
    стоять в начале позитивного, иначе не сработает."""
    from beatroot_artgen.comfy import positive_prompt

    prompt = positive_prompt("поляна", "flux1-schnell-fp8.safetensors", scene=True)
    assert prompt.lower().index("no people") < prompt.index("поляна")


def test_спрайт_по_прежнему_просит_белый_фон():
    """Разделение шаблонов не должно сломать спрайты: им белый фон нужен,
    именно от него отрезается объект."""
    from beatroot_artgen.comfy import positive_prompt

    prompt = positive_prompt("медвежонок", "sd_xl_base_1.0.safetensors").lower()
    assert "white background" in prompt


def test_вид_ассета_сам_определяет_шаблон():
    """Признак один: у фона нечего вырезать. Отдельного флага в манифесте нет —
    рассогласовать их было бы нечем."""
    from beatroot_artgen.comfy import positive_prompt

    assets = manifest.by_id(manifest.load())
    glade, monster = assets["glade_battle"], assets["bass_bear_common"]
    assert not glade.kind.cutout and monster.kind.cutout

    scene = positive_prompt(glade.full_subject(), "flux1-schnell-fp8.safetensors",
                            scene=not glade.kind.cutout).lower()
    sprite = positive_prompt(monster.full_subject(), "flux1-schnell-fp8.safetensors",
                             scene=not monster.kind.cutout).lower()
    assert "no people" in scene and "white background" not in scene
    assert "white background" in sprite


# ───────────────────────── вписывание в кадр ────────────────────────────────

def test_мелкий_предмет_занимает_кадр_целиком():
    """Модель рисует предмет тем размером, каким захочет.

    На первом прогоне жёлудь занял 5% кадра: из 64 пикселей ассета на сам
    жёлудь пришлось четырнадцать. Вписывание чинит это до постобработки —
    иначе ворота ловят следствие, а не причину, и лечится всё подкруткой порога.
    """
    from beatroot_artgen.pixelize import fit_subject

    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (40, 40), (120, 100, 80, 255)), (100, 60))

    import numpy as np

    fitted = fit_subject(canvas)
    filled = float((np.array(fitted)[..., 3] > 0).mean())
    assert filled > 0.5, f"объект занял {filled:.0%} кадра — вписывание не сработало"


def test_вписывание_оставляет_поля():
    """Объект, упирающийся в рамку, читается как обрезанный — и ворота
    правильно валят его по edge_touch."""
    from beatroot_artgen.pixelize import fit_subject

    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (50, 50), (120, 100, 80, 255)), (30, 30))

    import numpy as np

    alpha = np.array(fit_subject(canvas))[..., 3]
    assert alpha[0].max() == 0, "объект достаёт до самого края кадра"


def test_вписывание_центрирует():
    from beatroot_artgen.pixelize import fit_subject

    canvas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    canvas.paste(Image.new("RGBA", (30, 30), (120, 100, 80, 255)), (10, 200))

    report = __import__("beatroot_artgen.metrics", fromlist=["metrics"]).evaluate(
        fit_subject(canvas).resize((96, 96), Image.BOX), "проба", "00")
    assert "centering" not in {c.name for c in report.checks if not c.ok}


def test_пустой_кадр_вписывание_не_роняет():
    from beatroot_artgen.pixelize import fit_subject

    empty = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    assert fit_subject(empty).size == (64, 64)


# ───────────────────────────── перенос в игру ───────────────────────────────

@pytest.fixture
def fake_project(tmp_path: Path) -> Path:
    """Маленький проект: один монстр с кандидатами, ресурс и ASSETS.md."""
    (tmp_path / "data" / "monsters").mkdir(parents=True)
    (tmp_path / "data" / "monsters" / "bass_bear.tres").write_text(
        '[resource]\nid = "bass_bear"\ndisplay_name = "Топотун"\n'
        'sprite_path = "res://art/placeholder/monster_bass_bear.png"\n',
        encoding="utf-8",
    )
    (tmp_path / "ASSETS.md").write_text("# Происхождение ассетов\n\n## Графика\n",
                                        encoding="utf-8")

    candidates = tmp_path / "art" / "candidates" / "bass_bear_common"
    candidates.mkdir(parents=True)
    for name in ("00", "01"):
        Image.new("RGBA", (96, 96), (120, 100, 80, 255)).save(candidates / f"{name}.png")
    return tmp_path


@pytest.fixture
def bass_bear():
    return manifest.by_id(manifest.load())["bass_bear_common"]


def test_img2img_ждёт_принятого_младшего_грейда(fake_project):
    """Старший грейд строится из принятого младшего. Пока младший не принят,
    строить не на чем — и молча рисовать с нуля нельзя: получится другой зверь."""
    from beatroot_artgen.batch import source_for_grade

    uncommon = manifest.by_id(manifest.load())["bass_bear_uncommon"]
    assert source_for_grade(uncommon, fake_project) is None


def test_img2img_берёт_исходник_в_полном_разрешении(fake_project):
    """Именно raw, а не готовый пиксель-ассет: 96×96 после квантования модель
    разберёт как мусор, и вместо того же зверя выйдет новое существо."""
    from beatroot_artgen.batch import source_for_grade

    assets = manifest.by_id(manifest.load())
    common, uncommon = assets["bass_bear_common"], assets["bass_bear_uncommon"]

    directory = fake_project / "art" / "candidates" / "bass_bear_common"
    directory.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (96, 96), (120, 100, 80, 255)).save(directory / "00.png")
    Image.new("RGBA", (1024, 1024), (120, 100, 80, 255)).save(directory / "00.raw.png")
    promote.promote([common], {"bass_bear_common": "00"}, [], fake_project)

    source = source_for_grade(uncommon, fake_project)
    assert source is not None and source.name == "00.raw.png"
    assert Image.open(source).width == 1024


def test_в_ревью_видна_основа(fake_project):
    """Без принятого младшего рядом «тот же зверь или уже другой» решается
    на глаз без опоры."""
    assets = manifest.by_id(manifest.load())
    common, uncommon = assets["bass_bear_common"], assets["bass_bear_uncommon"]

    assert review.reference_image(uncommon, fake_project) is None

    directory = fake_project / "art" / "candidates" / "bass_bear_common"
    directory.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (96, 96), (120, 100, 80, 255)).save(directory / "00.png")
    promote.promote([common], {"bass_bear_common": "00"}, [], fake_project)

    assert review.reference_image(uncommon, fake_project) is not None


def test_путь_спрайта_пишется_только_базовым_грейдом(fake_project):
    """В MonsterData поле спрайта одно, а грейдов шесть. Старший грейд не имеет
    права его перезаписать — иначе обычный монстр вдруг станет легендарным."""
    assets = manifest.by_id(manifest.load())
    directory = fake_project / "art" / "candidates" / "bass_bear_epic"
    directory.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (96, 96), (120, 100, 80, 255)).save(directory / "00.png")

    result = promote.promote([assets["bass_bear_epic"]],
                             {"bass_bear_epic": "00"}, [], fake_project)
    assert (fake_project / "art" / "monster" / "bass_bear_epic.png").exists()
    assert "bass_bear_epic" in result.unwired

    tres = (fake_project / "data" / "monsters" / "bass_bear.tres").read_text(encoding="utf-8")
    assert "bass_bear_epic.png" not in tres


def test_принятый_кандидат_оказывается_там_где_его_ищет_игра(fake_project, bass_bear):
    result = promote.promote([bass_bear], {"bass_bear_common": "01"}, [], fake_project, "модель")

    assert result.problems == []
    target = fake_project / "art" / "monster" / "bass_bear_common.png"
    assert target.exists(), "файл не появился на своём месте"

    tres = (fake_project / "data" / "monsters" / "bass_bear.tres").read_text(encoding="utf-8")
    assert 'sprite_path = "res://art/monster/bass_bear_common.png"' in tres, \
        "ресурс всё ещё показывает на плейсхолдер — в игре ничего не изменится"


def test_перенос_записывает_происхождение(fake_project, bass_bear):
    promote.promote([bass_bear], {"bass_bear_common": "00"}, [], fake_project, "sd_xl_base_1.0")
    md = (fake_project / "ASSETS.md").read_text(encoding="utf-8")
    assert "art/monster/bass_bear_common.png" in md
    assert "sd_xl_base_1.0" in md, "не записано, чем сгенерировано"


def test_происхождение_берётся_по_каждому_ассету(fake_project, bass_bear):
    """Часть ассетов сделана другой моделью. Записать один чекпойнт на всю
    команду значит соврать в таблице происхождения коммерческой игры."""
    directory = fake_project / "art" / "candidates" / "bass_bear_common"
    (directory / "report.json").write_text(
        json.dumps({"asset_id": "bass_bear_common", "checkpoint": "настоящая_модель",
                    "variants": []}, ensure_ascii=False), encoding="utf-8")

    promote.promote([bass_bear], {"bass_bear_common": "00"}, [], fake_project,
                    "модель_из_команды")
    md = (fake_project / "ASSETS.md").read_text(encoding="utf-8")
    assert "настоящая_модель" in md
    assert "модель_из_команды" not in md


def test_повторный_перенос_не_плодит_блоки(fake_project, bass_bear):
    promote.promote([bass_bear], {"bass_bear_common": "00"}, [], fake_project, "модель")
    promote.promote([bass_bear], {"bass_bear_common": "01"}, [], fake_project, "модель")
    md = (fake_project / "ASSETS.md").read_text(encoding="utf-8")
    assert md.count(promote.ASSETS_MD_BEGIN) == 1
    assert md.count("art/monster/bass_bear_common.png") == 1


def test_несуществующий_вариант_не_ломает_прогон(fake_project, bass_bear):
    result = promote.promote([bass_bear], {"bass_bear_common": "99"}, [], fake_project)
    assert result.problems, "молча пропущенный несуществующий вариант"
    assert not (fake_project / "art" / "monster" / "bass_bear_common.png").exists()


def test_отклонение_двигает_попытку(fake_project, bass_bear):
    assert promote.attempt_of("bass_bear_common", fake_project) == 0
    promote.promote([bass_bear], {}, ["bass_bear_common"], fake_project)
    assert promote.attempt_of("bass_bear_common", fake_project) == 1
    promote.promote([bass_bear], {}, ["bass_bear_common"], fake_project)
    assert promote.attempt_of("bass_bear_common", fake_project) == 2


def test_решение_человека_не_затирается_вердиктом_клода(fake_project, bass_bear):
    """Два файла намеренно: повторный прогон ревью не имеет права отменять то,
    что человек уже решил глазами."""
    promote.promote([bass_bear], {"bass_bear_common": "00"}, [], fake_project)
    review.record("bass_bear_common", "01", review.REJECT, "передумал", fake_project)

    decisions = promote.load_decisions(fake_project)
    assert decisions["bass_bear_common"]["status"] == "принят"
    assert decisions["bass_bear_common"]["variant"] == "00"


def test_вердикт_с_неизвестным_статусом_не_записывается(fake_project):
    with pytest.raises(ValueError):
        review.record("bass_bear_common", "00", "может быть", "", fake_project)
    assert review.load_verdicts(fake_project) == {}


def test_снаряжение_без_поля_спрайта_названо_вслух(fake_project):
    """Иконка ляжет на диск, но в игру не попадёт: в GearData нет поля.
    Промолчать здесь — значит потерять ассет незаметно."""
    gear = manifest.by_id(manifest.load())["brass_bell"]
    candidates = fake_project / "art" / "candidates" / "brass_bell"
    candidates.mkdir(parents=True)
    Image.new("RGBA", (64, 64), (120, 100, 80, 255)).save(candidates / "00.png")

    result = promote.promote([gear], {"brass_bell": "00"}, [], fake_project)
    assert (fake_project / "art" / "gear" / "brass_bell.png").exists()
    assert "brass_bell" in result.unwired
    assert "brass_bell" in result.as_text()


# ─────────────────────────────── очередь ревью ──────────────────────────────

def _write_report(root: Path, asset_id: str, variants: list[str]) -> None:
    (root / "art" / "candidates" / asset_id).mkdir(parents=True, exist_ok=True)
    (root / "art" / "candidates" / asset_id / "report.json").write_text(
        json.dumps({
            "asset_id": asset_id, "kind": "monster", "prompt": "проба",
            "variants": [{"variant": v, "passed": True, "checks": [],
                          "image": f"{v}.png", "raw": f"{v}.raw.png", "seed": 1}
                         for v in variants],
        }, ensure_ascii=False), encoding="utf-8")


def test_отсмотренное_уходит_из_очереди(fake_project, bass_bear):
    _write_report(fake_project, "bass_bear_common", ["00"])

    assert len(review.queue([bass_bear], fake_project)) == 1
    review.record("bass_bear_common", "00", review.ACCEPT, "годится", fake_project)
    assert review.queue([bass_bear], fake_project) == []
    assert len(review.queue([bass_bear], fake_project, include_reviewed=True)) == 1


def test_перегенерация_возвращает_ассет_в_очередь(fake_project, bass_bear):
    """Отклонённый уходит на новую попытку, и файлы становятся другими.

    Без этого очередь отвечала бы «пусто», хотя свежих кандидатов никто
    не видел, — на этом уже один раз пришлось звать ревью вручную.
    """
    _write_report(fake_project, "bass_bear_common", ["00", "01"])
    review.record("bass_bear_common", "00", review.REJECT, "не то", fake_project)
    assert review.queue([bass_bear], fake_project) == []

    _write_report(fake_project, "bass_bear_common", ["1-00", "1-01"])
    assert len(review.queue([bass_bear], fake_project)) == 1, \
        "свежие кандидаты остались неотсмотренными"


def test_принятое_человеком_в_очередь_не_возвращается(fake_project, bass_bear):
    """Одобренное лежит в игре. Предлагать его на каждом круге — значит
    заставлять пересматривать одно и то же."""
    _write_report(fake_project, "bass_bear_common", ["00"])
    promote.promote([bass_bear], {"bass_bear_common": "00"}, [], fake_project)

    # Вердикта Клода нет вовсе, и всё равно ассет закрыт решением человека
    assert review.load_verdicts(fake_project) == {}
    assert review.queue([bass_bear], fake_project) == []


def test_отклонённое_человеком_остаётся_в_работе(fake_project, bass_bear):
    """Отклонение — не решение, а заявка на новую попытку."""
    _write_report(fake_project, "bass_bear_common", ["00"])
    promote.promote([bass_bear], {}, ["bass_bear_common"], fake_project)
    assert len(review.queue([bass_bear], fake_project)) == 1
