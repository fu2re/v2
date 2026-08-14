extends Node

## Проверки снаряжения.
##
## Под охраной обещание из GDD §9.2 и §12.1: снаряжение живёт на гуардиане
## и покупается за игровую валюту. Ничего, что влияет на бой, не должно
## существовать в контуре реальных денег.

var _failed := 0
var _passed := 0


func _ready() -> void:
	SaveManager.enter_test_mode()
	GameState.reset()

	_test_registry()
	_test_equip_unequip()
	_test_bonuses_stack()
	_test_gear_affects_battle()
	_test_shield_never_free()
	_test_gear_is_per_monster()
	_test_guardian_selection()
	_test_save_roundtrip()

	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


func check_eq(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s (получено %s, ожидалось %s)" % [description, actual, expected])


func _test_registry() -> void:
	print("Реестр снаряжения")
	var all := Registry.all_gear()
	check(all.size() >= 9, "снаряжение загрузилось (%d)" % all.size())

	# В каждом слоте должно быть из чего выбирать, иначе слот бессмысленен
	for slot in [GearData.Slot.BOOTS, GearData.Slot.ACCESSORY, GearData.Slot.AMULET]:
		var pool := Registry.gear_for_slot(slot)
		check(pool.size() >= 2, "%s: есть выбор (%d)" % [GearData.slot_name(slot), pool.size()])

	# Всё снаряжение продаётся за СЕМЕЧКИ — игровую валюту (GDD §12.1)
	for item in all:
		check(item.price > 0, "%s имеет цену в семечках" % item.id)


func _test_equip_unequip() -> void:
	print("Надеть и снять")
	GameState.reset()
	GameState.add_gear("soft_slippers")
	check_eq(GameState.gear_count("soft_slippers"), 1, "предмет в сундуке")

	check(GameState.equip("disco_sprout", "soft_slippers"), "надето")
	check_eq(GameState.gear_count("soft_slippers"), 0, "из сундука ушло")
	check(GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS) != null, "слот занят")

	check(not GameState.equip("disco_sprout", "soft_slippers"), "второй раз то же самое нельзя")

	check(GameState.unequip("disco_sprout", GearData.Slot.BOOTS), "снято")
	check_eq(GameState.gear_count("soft_slippers"), 1, "вернулось в сундук — экипировка обратима")
	check(GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS) == null, "слот пуст")
	check(not GameState.unequip("disco_sprout", GearData.Slot.BOOTS), "снимать нечего")

	# Замена в занятом слоте возвращает предыдущее в сундук
	GameState.add_gear("spring_boots")
	GameState.equip("disco_sprout", "soft_slippers")
	GameState.equip("disco_sprout", "spring_boots")
	check_eq(GameState.gear_count("soft_slippers"), 1, "вытесненное вернулось в сундук")
	check_eq(GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS).id, "spring_boots",
		"в слоте новое")


func _test_bonuses_stack() -> void:
	print("Суммирование эффектов")
	GameState.reset()
	var clean := GameState.gear_bonuses("disco_sprout")
	check_eq(clean.window_scale, 1.0, "без снаряжения окна обычные")
	check_eq(clean.groove_bonus, 0, "без снаряжения Ритм обычный")

	GameState.add_gear("spring_boots")
	GameState.add_gear("brass_bell")
	GameState.add_gear("river_stone")
	GameState.equip("disco_sprout", "spring_boots")
	GameState.equip("disco_sprout", "brass_bell")
	GameState.equip("disco_sprout", "river_stone")

	var full := GameState.gear_bonuses("disco_sprout")
	check(full.window_scale > 1.0, "обувь расширила окна")
	check(full.power_bonus > 0.0, "аксессуар усилил удар")
	check(full.groove_bonus > 0, "амулет добавил Ритма")
	check(full.shield_reduction > 0.0, "амулет смягчил пропуск щита")


func _test_gear_affects_battle() -> void:
	print("Снаряжение доходит до боя")
	GameState.reset()
	var bare := BattleState.new()
	bare.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100)
	var bare_damage := bare.register_hit(Judge.Grade.PERFECT)
	var bare_groove := bare.max_groove

	GameState.add_gear("thunder_pick")
	GameState.add_gear("river_stone")
	GameState.equip("disco_sprout", "thunder_pick")
	GameState.equip("disco_sprout", "river_stone")

	var geared := BattleState.new()
	geared.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100)
	check(geared.register_hit(Judge.Grade.PERFECT) > bare_damage, "аксессуар усилил удар в бою")
	check(geared.max_groove > bare_groove, "амулет поднял максимум Ритма")

	# Обувь расширяет окна: то, что было Good, становится Perfect
	GameState.add_gear("cloud_shoes")
	GameState.equip("disco_sprout", "cloud_shoes")
	var shod := BattleState.new()
	shod.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100)
	check(shod.window_scale > 1.0, "окна расширены")
	check_eq(Judge.grade(0.070, shod.window_scale), Judge.Grade.PERFECT,
		"с обувью попадание в 70 мс стало идеальным")
	check_eq(Judge.grade(0.070, 1.0), Judge.Grade.GOOD, "без обуви оно же — просто хорошее")


func _test_shield_never_free() -> void:
	print("Щит нельзя обнулить снаряжением")
	GameState.reset()
	GameState.add_gear("heartwood_amulet")
	GameState.equip("disco_sprout", "heartwood_amulet")

	var s := BattleState.new()
	s.setup(Registry.monster("synth_slime"), Registry.monster("disco_sprout"), 100)
	var before := s.groove
	s.take_strike()
	var damage := before - s.groove

	check(damage > 0, "пропущенный щит всё равно бьёт — механика обязана остаться")
	check(damage < BattleState.STRIKE_DAMAGE, "но амулет смягчил удар")

	# Даже при абсурдном снижении урон не уходит в ноль
	s.shield_reduction = 5.0
	var mid := s.groove
	s.take_strike()
	check(mid - s.groove >= 1, "урон не обнуляется ни при каком снаряжении")


func _test_gear_is_per_monster() -> void:
	print("Снаряжение привязано к существу, а не к игроку")
	GameState.reset()
	GameState.add_gear("spring_boots")
	GameState.equip("disco_sprout", "spring_boots")

	check(GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS) != null,
		"на первом надето")
	check(GameState.equipped_gear("bass_bear", GearData.Slot.BOOTS) == null,
		"на втором пусто — смена гуардиана должна быть решением, а не сменой скина")

	var other := GameState.gear_bonuses("bass_bear")
	check_eq(other.window_scale, 1.0, "чужие бонусы не протекают")


func _test_guardian_selection() -> void:
	print("Выбор гуардиана")
	GameState.reset()
	check_eq(GameState.guardian_id(), "", "без коллекции гуардиана нет")

	GameState.add_friendship("disco_sprout", 100)
	check_eq(GameState.guardian_id(), "disco_sprout", "первый приручённый берётся по умолчанию")

	check(not GameState.set_guardian("beat_serpent"), "неприручённого выбрать нельзя")

	GameState.add_friendship("bass_bear", 999)
	check(GameState.set_guardian("bass_bear"), "приручённого выбрать можно")
	check_eq(GameState.guardian_id(), "bass_bear", "выбор применился")


func _test_save_roundtrip() -> void:
	print("Сейв снаряжения")
	GameState.reset()
	GameState.add_friendship("disco_sprout", 999)
	GameState.set_guardian("disco_sprout")
	GameState.add_gear("cloud_shoes")
	GameState.add_gear("brass_bell", 2)
	GameState.equip("disco_sprout", "cloud_shoes")

	# JSON превращает целые ключи слотов в строки — прогоняем через настоящую
	# сериализацию, иначе экипировка молча перестала бы находиться
	var json := JSON.stringify(GameState.to_dict())
	var restored: Dictionary = JSON.parse_string(json)

	GameState.reset()
	GameState.from_dict(restored)

	check_eq(GameState.gear_count("brass_bell"), 2, "сундук восстановился")
	var boots := GameState.equipped_gear("disco_sprout", GearData.Slot.BOOTS)
	check(boots != null, "надетое нашлось после JSON-цикла")
	if boots != null:
		check_eq(boots.id, "cloud_shoes", "именно тот предмет")
	check_eq(GameState.guardian_id(), "disco_sprout", "выбранный гуардиан восстановился")
	check(GameState.gear_bonuses("disco_sprout").window_scale > 1.0, "бонусы снова считаются")
