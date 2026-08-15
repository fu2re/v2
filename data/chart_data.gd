class_name ChartData
extends Resource

## Карта нот одного боя.
##
## Ноты хранятся параллельными пакованными массивами, а не массивом объектов:
## в бою до 8 нот в секунду, и объект на ноту дал бы лишние аллокации
## и промахи кеша на слабых телефонах.

## Типы нот.
##
## ATTACK — единственный источник урона по Настрою. Обычные биты его
## не наносят: они собирают серию, а бьёт только атака в её конце,
## и только если серия прошла без промахов (GDD §4.3).
enum NoteType { BEAT, SKILL, SHIELD, SNACK, ATTACK }

const TYPE_NAMES := {
	"beat": NoteType.BEAT,
	"skill": NoteType.SKILL,
	"shield": NoteType.SHIELD,
	"snack": NoteType.SNACK,
	"attack": NoteType.ATTACK,
}

@export var id: String = ""
@export var genre: String = ""
@export var difficulty: String = "normal"
@export var bpm: float = 120.0
## Секунда первой доли в аудиофайле. Для синтезированных треков всегда 0.
@export var offset: float = 0.0
@export var duration: float = 0.0
@export var beats_per_bar: int = 4
@export var audio_path: String = ""

## Доли, на которых стоят ноты. Отсортированы по возрастанию.
@export var note_beats: PackedFloat32Array = PackedFloat32Array()
## Типы нот, индексы совпадают с note_beats.
@export var note_types: PackedByteArray = PackedByteArray()

## Танец монстра: доли и действия (windup, strike).
@export var pattern_beats: PackedFloat32Array = PackedFloat32Array()
@export var pattern_actions: PackedStringArray = PackedStringArray()

var _audio: AudioStream = null


func note_count() -> int:
	return note_beats.size()


func sec_per_beat() -> float:
	return 60.0 / bpm if bpm > 0.0 else 0.5


## Перевод доли в секунду трека. Единственное место, где это делается.
func beat_to_time(beat: float) -> float:
	return offset + beat * sec_per_beat()


func time_to_beat(time: float) -> float:
	return (time - offset) / sec_per_beat()


func total_beats() -> float:
	return time_to_beat(duration)


## Аудио грузится лениво: чарт может понадобиться и без звука,
## например в headless-тестах.
func audio() -> AudioStream:
	if _audio == null and not audio_path.is_empty():
		_audio = load(audio_path) as AudioStream
	return _audio


## Отпустить кешированный поток. Вызывается при смене чарта, чтобы
## предыдущий Ogg не висел в памяти весь забег.
func release_audio() -> void:
	_audio = null
