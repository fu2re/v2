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
from dataclasses import dataclass
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


def build_workflow(req: GenerationRequest) -> dict:
    """Собрать SDXL txt2img workflow в API-формате ComfyUI.

    Используются только базовые ноды — никаких кастомных зависимостей,
    workflow запустится на чистой установке.
    """
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": req.checkpoint},
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "inputs": {
                "text": STYLE_POSITIVE.format(subject=req.subject),
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
