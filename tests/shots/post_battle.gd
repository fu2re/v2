extends Node

## Снимок карточки «после боя»: ровно тот экран, который игрок прислал
## со сдвоенной подсказкой и мёртвыми кнопками.

func _ready() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()
	FarmState.reset()
	var starter := Registry.monster("disco_sprout")
	GameState.add_friendship("disco_sprout", starter.friendship_threshold())
	GameState.set_guardian("disco_sprout")
	RunManager.set_seed(11)

	var feed := preload("res://scenes/run/RunFeed.tscn").instantiate()
	add_child(feed)
	await _frames(3)

	var guard := 0
	while RunManager.current_glade != null \
			and RunManager.current_glade.type != Glade.Type.BATTLE and guard < 60:
		guard += 1
		feed._next_glade()
		await _frames(1)

	var monster := Registry.monster(RunManager.current_glade.monster_id)
	var state := BattleState.new()
	# Значения берём у забега, а не выдумываем: подставленное здоровье
	# рисует пустую шкалу и выглядит как баг движка
	state.setup(monster, Registry.monster("disco_sprout"), RunManager.health,
		RunManager.current_glade.depth, RunManager.shield)
	# Монстр не побеждён — он убегает, и это худший из двух итогов
	feed._on_battle_finished(false, state)
	await _frames(30)
	print("ЗДОРОВЬЕ: %d/%d  ЩИТ: %d/%d" % [RunManager.health, RunManager.max_health, RunManager.shield, RunManager.max_shield])
	print("ПОДСКАЗКА: [%s]" % feed._hint.text)
	print("КНОПКА ДЕЙСТВИЯ: видна=%s текст=[%s]"
		% [feed._action_button.visible, feed._action_button.text])
	print("КНОПКА ДАЛЬШЕ: видна=%s выключена=%s"
		% [feed._next_button.visible, feed._next_button.disabled])
	# Закрываем итог тем же путём, что и игрок кнопкой
	feed._confirm()
	await _frames(10)
	print("ПОСЛЕ ЗАКРЫТИЯ: подсказка=[%s]" % feed._hint.text)
	print("  действие: видна=%s текст=[%s]" % [feed._action_button.visible, feed._action_button.text])
	print("  дальше: видна=%s выключена=%s" % [feed._next_button.visible, feed._next_button.disabled])
	var depth_before: int = RunManager.depth
	feed._advance()
	await _frames(10)
	print("  переход: %d -> %d" % [depth_before, RunManager.depth])
	await _frames(30)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
