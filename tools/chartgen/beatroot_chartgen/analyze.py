"""Анализ внешнего аудио: темп, сетка долей, онсеты.

Нужен только для треков, пришедших файлом (сгенерированных нейросетью или найденных).
Для синтезированных песен анализ не используется — там сетка известна точно.

Зависимости ставятся отдельно:  uv sync --extra analyze
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class AudioAnalysis:
    path: Path
    duration: float
    bpm: float
    offset: float  # секунда первой доли
    onsets: list[float]  # секунды атак
    beats: list[float]  # секунды долей

    def onset_beats(self) -> list[float]:
        """Онсеты, пересчитанные в доли относительно offset."""
        spb = 60.0 / self.bpm
        return [round((t - self.offset) / spb, 3) for t in self.onsets]


def _require_librosa():
    try:
        import librosa  # noqa: F401
    except ImportError as e:  # pragma: no cover
        raise SystemExit(
            "Для анализа внешнего аудио нужны доп. зависимости:\n"
            "    uv sync --extra analyze"
        ) from e
    return librosa


def analyze(path: Path, bpm_hint: float | None = None) -> AudioAnalysis:
    librosa = _require_librosa()

    y, sr = librosa.load(str(path), mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    if bpm_hint:
        # Подсказка по BPM резко повышает точность сетки: автодетект
        # регулярно ошибается ровно вдвое на электронных треках.
        tempo = float(bpm_hint)
        _, beat_frames = librosa.beat.beat_track(y=y, sr=sr, bpm=tempo, units="frames")
    else:
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
        tempo = float(tempo)

    beats = [float(t) for t in librosa.frames_to_time(beat_frames, sr=sr)]
    onset_frames = librosa.onset.onset_detect(y=y, sr=sr, backtrack=True)
    onsets = [float(t) for t in librosa.frames_to_time(onset_frames, sr=sr)]

    return AudioAnalysis(
        path=path,
        duration=duration,
        bpm=round(tempo, 2),
        offset=beats[0] if beats else 0.0,
        onsets=onsets,
        beats=beats,
    )


def quantize(beats: list[float], grid: float = 0.5) -> list[float]:
    """Притянуть доли к сетке. grid=0.5 — восьмые, 0.25 — шестнадцатые."""
    return sorted({round(b / grid) * grid for b in beats if b >= 0})
