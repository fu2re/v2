class_name NotePool
extends Node2D

## Пул нот. Узлы создаются один раз при входе в бой и дальше только
## показываются и прячутся.
##
## Размер с запасом: при 8 нотах/сек и подлёте в 2 доли одновременно
## на экране бывает до ~16, но всплеск на высокой сложности берём с полем.

const POOL_SIZE := 64

var _all: Array[Note] = []
var _free: Array[Note] = []


func _ready() -> void:
	for i in POOL_SIZE:
		var note := Note.new()
		note.visible = false
		add_child(note)
		_all.append(note)
		_free.append(note)


## Выдать ноту из пула. null, если пул исчерпан — это означает ошибку
## в чарте или в размере пула, и молчать об этом нельзя.
func acquire(beat: float, type: int) -> Note:
	if _free.is_empty():
		push_warning("Пул нот исчерпан (%d). Чарт слишком плотный или пул мал." % POOL_SIZE)
		return null
	var note: Note = _free.pop_back()
	note.setup(beat, type)
	return note


func release(note: Note) -> void:
	if note == null or _free.has(note):
		return
	note.release()
	_free.append(note)


func release_all() -> void:
	for note in _all:
		note.release()
	_free = _all.duplicate()


func active_count() -> int:
	return _all.size() - _free.size()
