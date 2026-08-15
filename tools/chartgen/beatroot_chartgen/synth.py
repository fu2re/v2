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


def _clap(dur: float, vel: float) -> np.ndarray:
    """Три коротких всплеска шума подряд — характерная «пачка» вместо снейра.

    Хлопок держит электро-долю там, где снейр звучал бы слишком по-рóковому.
    """
    n = int(0.22 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    rng = np.random.default_rng(3)
    noise = rng.normal(0, 1, n)
    noise = np.diff(noise, prepend=0.0)

    out = np.zeros(n)
    for i, (delay, amp) in enumerate(((0.0, 0.7), (0.011, 0.9), (0.023, 1.0))):
        start = int(delay * SAMPLE_RATE)
        tail = n - start
        decay = np.exp(-t[:tail] * (55.0 if i == 2 else 190.0))
        out[start:] += noise[:tail] * decay * amp
    return out * 0.4 * vel


def _tom(dur: float, vel: float) -> np.ndarray:
    """Том для филлов. Тот же питч-свип, что у бочки, но выше и длиннее."""
    n = int(0.20 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    freq = 110.0 + 90.0 * np.exp(-t * 18.0)
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    return np.sin(phase) * np.exp(-t * 11.0) * 0.7 * vel


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


# --- тембры для жанровых аранжировок ------------------------------------------
#
# Пять генераторов выше не трогаются: на них рендерятся demo_disco и farm_folk,
# и любая правка изменила бы уже выверенные треки обучения и фермы.


def _guitar(freq: float, dur: float, vel: float) -> np.ndarray:
    """Рок-гитара: нечётные гармоники, продавленные через tanh.

    Перегруз добавляет гармоники сам, поэтому спектр задан скупо — иначе
    после tanh получается каша, а не аккорд.
    """
    raw = _tonal(freq, dur, 1.0, [1.0, 0.0, 0.55, 0.0, 0.3], (0.003, 0.06, 0.72, 0.09))
    return np.tanh(raw * 3.2) * 0.30 * vel


def _pluck(freq: float, dur: float, vel: float) -> np.ndarray:
    """Щипок для фолка: богатый спектр и быстрый спад, без сустейна.

    Спад экспоненциальный поверх огибающей — акустическая струна гаснет
    независимо от того, держат её или нет.
    """
    raw = _tonal(freq, dur, 1.0, [1.0, 0.6, 0.35, 0.22, 0.14, 0.08],
                 (0.002, 0.03, 0.35, 0.12))
    t = np.arange(len(raw)) / SAMPLE_RATE
    return raw * np.exp(-t * 6.5) * 0.34 * vel


def _saw(freq: float, dur: float, vel: float) -> np.ndarray:
    """Пила для электро: гармоники 1/n. Жужжащая, узнаваемо синтетическая."""
    harmonics = [1.0 / i for i in range(1, 13)]
    return _tonal(freq, dur, vel * 0.20, harmonics, (0.004, 0.05, 0.7, 0.08))


def _sub(freq: float, dur: float, vel: float) -> np.ndarray:
    """Саб-бас хип-хопа: почти чистая синусоида с длинным релизом.

    Одна редкая длинная нота держит низ там, где бас восьмыми забил бы
    всё поле — в хип-хопе пауза несёт не меньше, чем нота.
    """
    return _tonal(freq, dur, vel * 0.75, [1.0, 0.07], (0.008, 0.10, 0.85, 0.22))


def _pad(freq: float, dur: float, vel: float) -> np.ndarray:
    """Подложка для меню: медленная атака, длинный хвост, мягкий спектр.

    Инструмент фона, а не переднего плана. В меню музыка обязана быть слышна
    и не мешать — а всё, что имеет резкую атаку, тянет внимание на себя
    и через десять минут в лавке начинает раздражать.

    Лёгкая расстройка второго голоса даёт живое биение вместо стерильной
    синусоиды. Полтона было бы фальшью, три цента — просто «тепло».
    """
    n = max(int(dur * SAMPLE_RATE), 1)
    t = np.arange(n) / SAMPLE_RATE
    voice = np.zeros(n)
    for detune, amp in ((1.0, 1.0), (1.0018, 0.7), (0.9985, 0.7), (2.0, 0.22)):
        voice += amp * np.sin(2 * np.pi * freq * detune * t)
    return voice * _env(n, 0.12, 0.25, 0.75, 0.45) * vel * 0.11


def _bell(freq: float, dur: float, vel: float) -> np.ndarray:
    """Колокольчик для джинглов: неточные обертоны и долгий спад.

    Обертоны намеренно не кратны основному тону — этим колокол и отличается
    от органа. Короткий сигнал должен читаться как «событие», а не как нота.
    """
    n = max(int(dur * SAMPLE_RATE), 1)
    t = np.arange(n) / SAMPLE_RATE
    out = np.zeros(n)
    for ratio, amp, decay in ((1.0, 1.0, 4.5), (2.76, 0.5, 7.0),
                              (5.40, 0.25, 9.5), (8.93, 0.12, 13.0)):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    return out * _env(n, 0.002, 0.02, 0.9, 0.25) * vel * 0.22


_PERC = {"kick": _kick, "snare": _snare, "hat": _hat, "clap": _clap, "tom": _tom}
_TONAL = {"bass": _bass, "lead": _lead, "guitar": _guitar, "pluck": _pluck,
          "saw": _saw, "sub": _sub, "pad": _pad, "bell": _bell}


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


# Качество Vorbis и частота дискретизации выхода.
#
# Треков триста, и на исходных qscale 6 / 44.1 кГц они весят около 105 МБ —
# столько музыки не влезает ни в репозиторий, ни в APK. Здесь qscale 0
# и 32 кГц: те же треки укладываются примерно в 33 МБ.
#
# Настолько сильное сжатие допустимо именно из-за синтеза. Материал —
# чиптюновый: ведущая линия не поднимается выше ~1.1 кГц, двенадцатая
# гармоника пилы упирается в 13 кГц, и всё, что срезает потолок 16 кГц, —
# это шум хэта, который сжатие портит в последнюю очередь. На записанном
# инструменте такие настройки были бы слышны сразу.
OGG_QUALITY = "0"
OGG_SAMPLE_RATE = "32000"


def wav_to_ogg(wav: Path, ogg: Path) -> None:
    """Конвертация через ffmpeg. .ogg — формат музыки в Godot."""
    ogg.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
         "-c:a", "libvorbis", "-qscale:a", OGG_QUALITY,
         "-ar", OGG_SAMPLE_RATE, str(ogg)],
        check=True,
    )
