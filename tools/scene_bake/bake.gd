extends Node

## Запекание сцен: из кода в редактируемый .tscn.
##
## Раскладка годами жила в _build_ui(), и в редакторе Godot сцены выглядели
## пустыми — увидеть экран можно было только запустив игру (GDD §13.2.1).
## Переписывать раскладку в .tscn руками значило бы сверять сотни координат
## глазами, поэтому дерево строит ТОТ ЖЕ код, а инструмент лишь сохраняет
## результат. После запекания _build_ui() удаляется, а скрипт берёт узлы
## по именам.
##
## Инструмент одноразовый по смыслу, но лежит в репозитории: если раскладку
## снова придётся пересобрать из кода, повторить надо будет ровно это.

## Что печём: скрипт -> куда сохранить сцену.
const TARGETS := {
	"res://scenes/farm/farm.gd": "res://scenes/farm/Farm.tscn",
	"res://scenes/run/run_feed.gd": "res://scenes/run/RunFeed.tscn",
	"res://scenes/collection/collection.gd": "res://scenes/collection/Collection.tscn",
	"res://scenes/shop/shop.gd": "res://scenes/shop/Shop.tscn",
	"res://scenes/inventory/inventory.gd": "res://scenes/inventory/Inventory.tscn",
	"res://scenes/battle/dance_battle.gd": "res://scenes/battle/DanceBattle.tscn",
}

## Метод сборки. У сцены боя это не интерфейс, а сцена целиком.
const BUILDERS := {
	"res://scenes/battle/dance_battle.gd": "_build_stage",
}


func _ready() -> void:
	var failed := 0
	for script_path: String in TARGETS:
		var scene_path: String = TARGETS[script_path]
		if not _bake(script_path, scene_path):
			failed += 1
	print("\nЗапечено: %d, ошибок: %d" % [TARGETS.size() - failed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _bake(script_path: String, scene_path: String) -> bool:
	var script: GDScript = load(script_path)
	if script == null:
		printerr("не загрузился скрипт %s" % script_path)
		return false

	# Узел создаём ВНЕ дерева: тогда _ready() не срабатывает и вместе
	# с раскладкой не запускается игровая логика — забег, автосейв, музыка
	var root: Node = script.new()
	var builder: String = BUILDERS.get(script_path, "_build_ui")
	if not root.has_method(builder):
		# Скрипт уже переведён на .tscn — печь нечего, и это не ошибка
		print("%s уже собран в редакторе, пропуск" % script_path.get_file())
		root.free()
		return true
	root.call(builder)
	_attach_extras(script_path, root)

	root.name = scene_path.get_file().get_basename()
	var named := _name_children(root, {})
	_own(root, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		printerr("pack(%s) вернул %d" % [scene_path, err])
		root.free()
		return false

	err = ResourceSaver.save(packed, scene_path)
	root.free()
	if err != OK:
		printerr("save(%s) вернул %d" % [scene_path, err])
		return false

	print("%s -> %s  (узлов: %d)" % [script_path.get_file(), scene_path, named])
	return true


## Узлы, которые в сцене уже были и которых сборочный код не знает.
##
## Оверлей замеров лежал в DanceBattle.tscn руками и при перезаписи сцены
## пропал бы вместе с настроенным battle_path.
func _attach_extras(script_path: String, root: Node) -> void:
	if script_path != "res://scenes/battle/dance_battle.gd":
		return
	var overlay := CanvasLayer.new()
	overlay.name = "TimingOverlay"
	overlay.visible = false
	overlay.set_script(load("res://scenes/debug/timing_overlay.gd"))
	overlay.set("battle_path", NodePath(".."))
	root.add_child(overlay)


## Имя узла — это то, чем скрипт будет его искать после запекания,
## поэтому безымянных быть не должно.
func _name_children(node: Node, seen: Dictionary) -> int:
	var count := 0
	for child in node.get_children():
		if child.name.begins_with("@"):
			printerr("  безымянный узел: %s (%s), родитель %s" % [child.name, child.get_class(), node.name])
		count += 1 + _name_children(child, seen)
	return count


## PackedScene сохраняет только узлы, у которых выставлен owner.
func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)
