"""Реестр синтезированных песен.

Чтобы добавить песню: создай модуль рядом с константой SONG и впиши его сюда.
"""

from __future__ import annotations

import importlib
import pkgutil

from ..song import Song

_MODULES = [m.name for m in pkgutil.iter_modules(__path__) if not m.name.startswith("_")]


def all_songs() -> dict[str, Song]:
    songs: dict[str, Song] = {}
    for name in _MODULES:
        mod = importlib.import_module(f"{__name__}.{name}")
        song = getattr(mod, "SONG", None)
        if isinstance(song, Song):
            songs[song.id] = song
    return songs


def get(song_id: str) -> Song:
    songs = all_songs()
    if song_id not in songs:
        known = ", ".join(sorted(songs)) or "—"
        raise KeyError(f"песня '{song_id}' не найдена. Доступны: {known}")
    return songs[song_id]
