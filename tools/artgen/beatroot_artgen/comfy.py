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


def positive_prompt(subject: str, checkpoint: str) -> str:
    template = STYLE_POSITIVE_DISTILLED if is_distilled(checkpoint) else STYLE_POSITIVE
    return template.format(subject=subject)


# Модели-дистилляты (Turbo, Lightning, LCM, Hyper) рассчитаны на 1-4 шага
# при cfg около 1.0. Обычные 28 шагов с cfg 6.5 дают на них пересвеченную кашу,
# поэтому параметры подбираются по имени чекпойнта, а не задаются вслепую.
_TURBO_MARKERS = ("turbo", "lightning", "lcm", "hyper")


def is_distilled(checkpoint: str) -> bool:
    name = checkpoint.lower()
    return any(marker in name for marker in _TURBO_MARKERS)


@dataclass
class GenerationRequest:
    subject: str
    checkpoint: str
    seed: int = 0
    steps: int = 28
    cfg: float = 6.5
    width: int = 1024
    height: int = 1024
    sampler: str = "dpmpp_2m"
    scheduler: str = "karras"

    def tuned(self) -> "GenerationRequest":
        """Копия с параметрами под тип модели."""
        if not is_distilled(self.checkpoint):
            return self
        return replace(
            self,
            steps=min(self.steps, 6) if self.steps <= 6 else 4,
            cfg=1.0,
            sampler="euler_ancestral",
            scheduler="sgm_uniform",
            width=min(self.width, 768),
            height=min(self.height, 768),
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
                "text": positive_prompt(req.subject, req.checkpoint),
                "clip": ["1", 1],
            },
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": STYLE_NEGATIVE, "clip": ["1", 1]},
        },
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": req.width, "height": req.height, "batch_size": 1},
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": req.seed,
                "steps": req.steps,
                "cfg": req.cfg,
                "sampler_name": req.sampler,
                "scheduler": req.scheduler,
                "denoise": 1.0,
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
    }


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
