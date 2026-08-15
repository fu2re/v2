"""Клиент ComfyUI поверх его HTTP API.

MCP для этого не нужен: у ComfyUI обычный REST — кладём workflow в очередь,
ждём результат, забираем картинку. Заодно сразу гоним её через постобработку,
так что из одной команды получается готовый ассет в палитре проекта.

Зависимости: uv sync --extra comfy
"""

from __future__ import annotations

import io
import json
import time
import uuid
from dataclasses import dataclass, replace
from pathlib import Path

DEFAULT_HOST = "http://127.0.0.1:8188"

# Шаблон промпта. Модель рисует ЖИВОПИСЬ в высоком разрешении — пиксель
# делается постобработкой (GDD §11.3). Просить пиксель-арт у модели нельзя:
# она выдаёт имитацию с рваной сеткой, которую проще перерисовать с нуля.
STYLE_POSITIVE = (
    "detailed painterly game asset, {subject}, "
    "warm earthy color palette, ochre and olive and terracotta tones, "
    "soft volumetric shading, top-down three-quarter view, "
    "centered, full body, isolated on plain flat white background, "
    "cozy storybook illustration, crisp readable silhouette"
)

STYLE_NEGATIVE = (
    "pixel art, 8-bit, dithering, text, watermark, signature, "
    "photorealistic, harsh shadows, cluttered background, scenery, "
    "multiple subjects, cropped, blurry, neon colors, saturated blue, magenta"
)

# Отдельный шаблон для дистиллированных моделей.
#
# ПРИЧИНА: при cfg 1.0, на котором работают Turbo и подобные, негативный промпт
# практически не влияет на результат. Проверено: с обычным шаблоном Turbo
# проигнорировал «cluttered background, scenery» и нарисовал целую лесную сцену,
# после чего вырезать фон стало нечего. Поэтому всё, что критично, вынесено
# в НАЧАЛО позитивного промпта, где вес максимален.
STYLE_POSITIVE_DISTILLED = (
    "plain solid white background, isolated single object, no scenery, "
    "{subject}, "
    "centered full body character, painterly game asset sprite, "
    "warm earthy palette, ochre olive terracotta, soft shading, "
    "cozy storybook illustration"
)


# Шаблоны для фонов. Отдельные, потому что шаблон спрайта на фоне работает
# ровно наоборот: он требует «белый фон, изолированный объект, центрированный
# персонаж во весь рост». Проверено на первом прогоне полян — модель послушалась
# буквально: небо вышло белым (после квантования — кремовым, в палитре мира нет
# неба), а «персонаж» появился на всех пятнадцати кадрах. Для фона, за которым
# бежит настоящий герой, запечённый человек смертелен.
STYLE_SCENE = (
    "detailed painterly game background, {subject}, "
    "warm earthy color palette, ochre and olive and terracotta tones, "
    "simplified silhouetted shapes, low detail, soft hazy depth, "
    "illustration fills the entire frame, empty place with no people and no creatures"
)

STYLE_SCENE_NEGATIVE = (
    "person, people, character, figure, silhouette of a person, animal, creature, "
    "pixel art, 8-bit, text, watermark, signature, photorealistic, "
    "cluttered, busy detail, white background, isolated object, neon colors"
)

# У дистиллятов негативный промпт инертен, поэтому запрет на людей и на открытое
# небо вынесен в НАЧАЛО позитивного — там вес максимален.
STYLE_SCENE_DISTILLED = (
    "completely empty place, no people, no characters, no animals, "
    "background scenery filling the whole frame, {subject}, "
    "painterly game background, warm earthy palette, ochre olive terracotta, "
    "simplified silhouetted shapes, low detail, soft hazy depth"
)


def positive_prompt(subject: str, checkpoint: str, scene: bool = False) -> str:
    """Позитивный промпт. `scene` — фон или тайл, а не объект на прозрачном.

    Разделение обязательно: у фона и у спрайта требования прямо противоположные.
    """
    distilled = is_distilled(checkpoint)
    if scene:
        template = STYLE_SCENE_DISTILLED if distilled else STYLE_SCENE
    else:
        template = STYLE_POSITIVE_DISTILLED if distilled else STYLE_POSITIVE
    return template.format(subject=subject)


def negative_prompt(scene: bool = False) -> str:
    return STYLE_SCENE_NEGATIVE if scene else STYLE_NEGATIVE


@dataclass(frozen=True)
class Profile:
    """Параметры сэмплера под конкретное семейство моделей.

    Задаются профилем, а не флагами вызова: перепутать cfg 6.5 с cfg 1.0 —
    значит получить либо пересвеченную кашу, либо мыло, и понять это только
    посмотрев на сотню картинок.
    """

    name: str
    steps: int
    cfg: float
    sampler: str
    scheduler: str
    max_side: int
    distilled: bool


# SDXL и обычные модели: полноценный cfg, негативный промпт работает.
SDXL = Profile("sdxl", steps=28, cfg=6.5, sampler="dpmpp_2m",
               scheduler="karras", max_side=1024, distilled=False)

# FLUX schnell — дистиллят на 4 шага. Cfg 1.0 не опечатка: guidance вшит
# в модель, и поднимать его нельзя. Держит нестандартные пропорции лучше SDXL,
# поэтому потолок стороны выше.
FLUX = Profile("flux", steps=4, cfg=1.0, sampler="euler",
               scheduler="simple", max_side=1216, distilled=True)

# Turbo/Lightning/LCM/Hyper: тоже дистилляты, но со своей связкой сэмплера
# и заметной деградацией выше 768.
TURBO = Profile("turbo", steps=4, cfg=1.0, sampler="euler_ancestral",
                scheduler="sgm_uniform", max_side=768, distilled=True)

_MARKERS: tuple[tuple[tuple[str, ...], Profile], ...] = (
    (("flux", "schnell"), FLUX),
    (("turbo", "lightning", "lcm", "hyper"), TURBO),
)


def profile_for(checkpoint: str) -> Profile:
    name = checkpoint.lower()
    for markers, profile in _MARKERS:
        if any(m in name for m in markers):
            return profile
    return SDXL


def is_distilled(checkpoint: str) -> bool:
    """Дистиллят работает на cfg ≈ 1.0, где негативный промпт почти инертен."""
    return profile_for(checkpoint).distilled


@dataclass
class GenerationRequest:
    subject: str
    checkpoint: str
    seed: int = 0
    steps: int = 0  # 0 — взять из профиля модели
    cfg: float = 0.0
    width: int = 1024
    height: int = 1024
    sampler: str = ""
    scheduler: str = ""
    ## Фон или тайл. Меняет шаблон промпта на противоположный по смыслу.
    scene: bool = False
    ## Исходник для img2img: имя файла, уже загруженного в ComfyUI.
    ## Пусто — рисуем с чистого листа.
    init_image: str = ""
    ## Насколько далеко разрешено уйти от исходника. 1.0 равносильно рисованию
    ## с нуля, 0.0 — точной копии.
    denoise: float = 1.0

    def tuned(self) -> "GenerationRequest":
        """Копия с параметрами под тип модели. Явно заданное не перебивается."""
        import math

        p = profile_for(self.checkpoint)
        scale = min(1.0, p.max_side / max(self.width, self.height))

        # При img2img сэмплер проходит только долю denoise от заданных шагов.
        # У дистиллята их четыре, и на denoise 0.6 остаётся два — этого не хватает
        # даже чтобы навесить шнурок с оберегом: первый прогон грейдов вышел
        # неотличимым от исходника. Компенсируем, чтобы модель получала свой
        # полный бюджет РЕАЛЬНОЙ работы, сколько бы её ни съел denoise.
        steps = self.steps or p.steps
        if self.init_image and 0.0 < self.denoise < 1.0:
            steps = math.ceil(steps / self.denoise)

        return replace(
            self,
            steps=steps,
            cfg=self.cfg or p.cfg,
            sampler=self.sampler or p.sampler,
            scheduler=self.scheduler or p.scheduler,
            # Кратность 64 обязательна: латент считается блоками, произвольный
            # размер молча округляется движком и ломает заданные пропорции
            width=int(self.width * scale) // 64 * 64,
            height=int(self.height * scale) // 64 * 64,
        )


def build_workflow(raw: GenerationRequest) -> dict:
    """Собрать SDXL txt2img workflow в API-формате ComfyUI.

    Используются только базовые ноды — никаких кастомных зависимостей,
    workflow запустится на чистой установке.
    """
    req = raw.tuned()
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": req.checkpoint},
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": positive_prompt(req.subject, req.checkpoint, req.scene),
                "clip": ["1", 1],
            },
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative_prompt(req.scene), "clip": ["1", 1]},
        },
        # Пустой латент или закодированный исходник — узел один и тот же номер,
        # чтобы KSampler не пришлось перепроводить в зависимости от режима
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": req.width, "height": req.height, "batch_size": 1},
        } if not req.init_image else {
            "class_type": "VAEEncode",
            "inputs": {"pixels": ["8", 0], "vae": ["1", 2]},
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": req.seed,
                "steps": req.steps,
                "cfg": req.cfg,
                "sampler_name": req.sampler,
                "scheduler": req.scheduler,
                "denoise": req.denoise if req.init_image else 1.0,
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0],
            },
        },
        "6": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["5", 0], "vae": ["1", 2]},
        },
        "7": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "beatroot", "images": ["6", 0]},
        },
    } | ({
        "8": {
            "class_type": "LoadImage",
            "inputs": {"image": req.init_image},
        },
    } if req.init_image else {})


class ComfyClient:
    def __init__(self, host: str = DEFAULT_HOST) -> None:
        try:
            import requests
        except ImportError as e:
            raise SystemExit(
                "Для работы с ComfyUI нужны доп. зависимости:\n"
                "    uv sync --extra comfy"
            ) from e
        self._requests = requests
        self.host = host.rstrip("/")
        self.client_id = str(uuid.uuid4())

    def is_up(self) -> bool:
        try:
            r = self._requests.get(f"{self.host}/system_stats", timeout=3)
            return r.status_code == 200
        except Exception:
            return False

    def checkpoints(self) -> list[str]:
        """Список установленных чекпойнтов — чтобы не гадать с именем модели."""
        r = self._requests.get(f"{self.host}/object_info/CheckpointLoaderSimple", timeout=10)
        r.raise_for_status()
        info = r.json()["CheckpointLoaderSimple"]["input"]["required"]["ckpt_name"]
        return list(info[0])

    def upload(self, path: Path) -> str:
        """Положить исходник в input ComfyUI и вернуть имя для LoadImage.

        LoadImage читает только из своего каталога input, произвольный путь
        с диска он не берёт — поэтому файл сначала надо отдать по HTTP.
        """
        with path.open("rb") as f:
            r = self._requests.post(
                f"{self.host}/upload/image",
                files={"image": (path.name, f, "image/png")},
                data={"overwrite": "true"},
                timeout=60,
            )
        r.raise_for_status()
        info = r.json()
        name = info["name"]
        subfolder = info.get("subfolder", "")
        return f"{subfolder}/{name}" if subfolder else name

    def submit(self, workflow: dict) -> str:
        r = self._requests.post(
            f"{self.host}/prompt",
            json={"prompt": workflow, "client_id": self.client_id},
            timeout=30,
        )
        if r.status_code != 200:
            raise RuntimeError(f"ComfyUI отверг workflow: {r.status_code} {r.text[:400]}")
        return r.json()["prompt_id"]

    def wait(self, prompt_id: str, timeout: float = 600.0, poll: float = 1.5) -> dict:
        deadline = time.time() + timeout
        while time.time() < deadline:
            r = self._requests.get(f"{self.host}/history/{prompt_id}", timeout=10)
            r.raise_for_status()
            hist = r.json()
            if prompt_id in hist:
                entry = hist[prompt_id]
                status = entry.get("status", {})
                if status.get("status_str") == "error":
                    raise RuntimeError(f"ComfyUI вернул ошибку: {json.dumps(status)[:600]}")
                if entry.get("outputs"):
                    return entry
            time.sleep(poll)
        raise TimeoutError(f"ComfyUI не ответил за {timeout:.0f} сек")

    def fetch(self, image_ref: dict):
        from PIL import Image

        r = self._requests.get(
            f"{self.host}/view",
            params={
                "filename": image_ref["filename"],
                "subfolder": image_ref.get("subfolder", ""),
                "type": image_ref.get("type", "output"),
            },
            timeout=60,
        )
        r.raise_for_status()
        return Image.open(io.BytesIO(r.content))

    def generate(self, req: GenerationRequest):
        """Полный цикл: очередь -> ожидание -> первая картинка."""
        entry = self.wait(self.submit(build_workflow(req)))
        for out in entry["outputs"].values():
            for ref in out.get("images", []):
                return self.fetch(ref)
        raise RuntimeError("ComfyUI не вернул ни одной картинки")


def save_workflow(req: GenerationRequest, path: Path) -> None:
    """Выгрузить workflow файлом — можно открыть в ComfyUI и покрутить руками."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(build_workflow(req), indent=2), encoding="utf-8")
