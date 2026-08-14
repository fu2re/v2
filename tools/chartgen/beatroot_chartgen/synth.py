"""Рендер Song в аудио. Чистый numpy, без внешних синтезаторов."""

from __future__ import annotations

import subprocess
import wave
from pathlib import Path

import numpy as np

from .song import Song, Track

SAMPLE_RATE = 44100


def midi_to_freq(midi: int) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def _env(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """ADSR-огибающая длиной n сэмплов. Времена в секундах."""
    a = min(int(attack * SAMPLE_RATE), n)
    d = min(int(decay * SAMPLE_RATE), max(n - a, 0))
    r = min(int(release * SAMPLE_RATE), max(n - a - d, 0))
    s = max(n - a - d - r, 0)
    return np.concatenate([
        np.linspace(0.0, 1.0, a, endpoint=False),
        np.linspace(1.0, sustain, d, endpoint=False),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r),
    ])[:n]


def _kick(dur: float, vel: float) -> np.ndarray:
    n = int(0.28 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    # Питч-свип вниз даёт удар с телом, а не просто щелчок
    freq = 45.0 + 95.0 * np.exp(-t * 32.0)
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    body = np.sin(phase) * np.exp(-t * 9.0)
    click = np.random.default_rng(0).normal(0, 1, n) * np.exp(-t * 320.0) * 0.18
    return (body + click) * vel


def _snare(dur: float, vel: float) -> np.ndarray:
    n = int(0.18 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    rng = np.random.default_rng(1)
    noise = rng.normal(0, 1, n) * np.exp(-t * 26.0)
    tone = np.sin(2 * np.pi * 190.0 * t) * np.exp(-t * 34.0) * 0.5
    return (noise * 0.7 + tone) * vel


def _hat(dur: float, vel: float) -> np.ndarray:
    n = int(0.05 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    rng = np.random.default_rng(2)
    noise = rng.normal(0, 1, n)
    # Грубый хайпасс через разность соседних сэмплов
    noise = np.diff(noise, prepend=0.0)
    return noise * np.exp(-t * 90.0) * 0.35 * vel


def _tonal(freq: float, dur: float, vel: float, harmonics: list[float], env: tuple) -> np.ndarray:
    n = max(int(dur * SAMPLE_RATE), 1)
    t = np.arange(n) / SAMPLE_RATE
    wave_out = np.zeros(n)
    for i, amp in enumerate(harmonics, start=1):
        wave_out += amp * np.sin(2 * np.pi * freq * i * t)
    return wave_out * _env(n, *env) * vel


def _bass(freq: float, dur: float, vel: float) -> np.ndarray:
    return _tonal(freq, dur, vel * 0.55, [1.0, 0.35, 0.12], (0.004, 0.05, 0.7, 0.06))


def _lead(freq: float, dur: float, vel: float) -> np.ndarray:
    # Нечётные гармоники — мягкий «квадрат», чиптюновый, но не режущий уши
    return _tonal(freq, dur, vel * 0.34, [1.0, 0.0, 0.42, 0.0, 0.2, 0.0, 0.1],
                  (0.006, 0.08, 0.65, 0.10))


_PERC = {"kick": _kick, "snare": _snare, "hat": _hat}
_TONAL = {"bass": _bass, "lead": _lead}


def render_track(track: Track, song: Song, buf: np.ndarray) -> None:
    spb = song.sec_per_beat
    for note in track.notes:
        start = int(note.beat * spb * SAMPLE_RATE)
        if start >= len(buf):
            continue
        dur = note.length * spb
        if track.instrument in _PERC:
            sample = _PERC[track.instrument](dur, note.velocity)
        elif track.instrument in _TONAL:
            if note.pitch is None:
                continue
            sample = _TONAL[track.instrument](midi_to_freq(note.pitch), dur, note.velocity)
        else:
            raise ValueError(f"неизвестный инструмент: {track.instrument}")
        end = min(start + len(sample), len(buf))
        buf[start:end] += sample[: end - start] * track.gain


def render(song: Song, tail: float = 0.0) -> np.ndarray:
    """Отрендерить песню в моно-массив float32 в диапазоне [-1, 1]."""
    n = int((song.duration + tail) * SAMPLE_RATE)
    buf = np.zeros(n, dtype=np.float64)
    for track in song.tracks:
        render_track(track, song, buf)

    # Мягкое ограничение вместо жёсткого клиппинга — иначе на пиках слышен треск
    buf = np.tanh(buf * 0.9)
    peak = np.max(np.abs(buf))
    if peak > 0:
        buf = buf / peak * 0.89
    return buf.astype(np.float32)


def write_wav(samples: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())


def wav_to_ogg(wav: Path, ogg: Path) -> None:
    """Конвертация через ffmpeg. .ogg — формат музыки в Godot."""
    ogg.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
         "-c:a", "libvorbis", "-qscale:a", "6", str(ogg)],
        check=True,
    )
