extends TestHarness

## Проверки снаряжения.
##
## Под охраной обещание из GDD §9.2 и §12.1: снаряжение живёт на гуардиане
## и покупается за игровую валюту. Ничего, что влияет на бой, не должно
## существовать в контуре реальных денег.
##
## Экипировка ключуется ЭКЗЕМПЛЯРОМ (GDD §6.3): обычный и редкий Ростик носят
## разное, и это главное, что здесь проверяется после переезда модели.

const COMMON := MonsterData.Rarity.COMMON
const SPROUT := "disco_sprout:0"
const BEAR := "bass_bear:0"


func run_tests() -> void:
	GameState.reset()
	_sprout()

	_test_registry()
	_test_equip_unequip()
	_test_bonuses_stack()
	_test_gear_affects_battle()
	_test_shield_never_free()
	_test_gear_is_per_instance()
	_test_guardian_selection()
	_test_save_roundtrip()


## Экземпляры, на которых ставятся опыты. Экипировать можно только того,
## кто действительно в коллекции, — иначе снаряжение уходило бы в никуда.
func _sprout() -> MonsterInstance:
	return GameState.tame("disco_sprout", COMMON)


func _bear() -> MonsterInstance:
	return GameState.tame("bass_bear", COMMON)


func _slime() -> MonsterInstance:
	return MonsterInstance.create("synth_slime", COMMON)


func _test_registry() -> void:
	print("Реестр снаряжения")
	var all := Registry.all_gear()
	check(all.size() >= 9, "снаряжение загрузилось (%d)" % all.size())

	# В каждом слоте должно быть из чего выбирать, иначе слот бессмысленен
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		var pool := Registry.gear_for_slot(slot)
		check(pool.size() >= 2, "%s: есть выбор (%d)" % [GearData.slot_name(slot), pool.size()])

	# Всё снаряжение продаётся за СЕРЕБРО — игровую валюту (GDD §12.1)
	for item in all:
		check(item.price > 0, "%s имеет цену в серебре" % item.id)


func _test_equip_unequip() -> void:
	print("Надеть и снять")
	GameState.reset()
	_sprout()
	GameState.add_gear("soft_slippers")
	check_eq(GameState.gear_count("soft_slippers"), 1, "предмет в сундуке")

	check(GameState.equip(SPROUT, "soft_slippers"), "надето")
	check_eq(GameState.gear_count("soft_slippers"), 0, "из сундука ушло")
	check(GameState.equipped_gear(SPROUT, GearData.Slot.BELT) != null, "слот занят")

	check(not GameState.equip(SPROUT, "soft_slippers"), "второй раз то же самое нельзя")

	check(GameState.unequip(SPROUT, GearData.Slot.BELT), "снято")
	check_eq(GameState.gear_count("soft_slippers"), 1, "вернулось в сундук — экипировка обратима")
	check(GameState.equipped_gear(SPROUT, GearData.Slot.BELT) == null, "слот пуст")
	check(not GameState.unequip(SPROUT, GearData.Slot.BELT), "снимать нечего")

	# Замена в занятом слоте возвращает предыдущее в сундук
	GameState.add_gear("spring_boots")
	GameState.equip(SPROUT, "soft_slippers")
	GameState.equip(SPROUT, "spring_boots")
	check_eq(GameState.gear_count("soft_slippers"), 1, "вытесненное вернулось в сундук")
	check_eq(GameState.equipped_gear(SPROUT, GearData.Slot.BELT).id, "spring_boots",
		"в слоте новое")


func _test_bonuses_stack() -> void:
	print("Суммирование эффектов")
	GameState.reset()
	_sprout()
	var clean := GameState.gear_bonuses(SPROUT)
	check_eq(clean.window_scale, 1.0, "без снаряжения окна обычные")
	check_eq(clean.health_bonus, 0, "без снаряжения здоровье обычное")

	GameState.add_gear("spring_boots")
	GameState.add_gear("brass_bell")
	GameState.add_gear("river_stone")
	GameState.equip(SPROUT, "spring_boots")
	GameState.equip(SPROUT, "brass_bell")
	GameState.equip(SPROUT, "river_stone")

	var full := GameState.gear_bonuses(SPROUT)
	check(full.window_scale > 1.0, "обувь расширила окна")
	check(full.power_bonus > 0.0, "аксессуар усилил удар")
	check(full.health_bonus > 0, "амулет добавил здоровья")
	check(full.shield_reduction > 0.0, "амулет смягчил пропуск щита")


func _test_gear_affects_battle() -> void:
	print("Снаряжение доходит до боя")
	GameState.reset()
	_sprout()
	var bare := BattleState.new()
	bare.setup(_slime(), _sprout(), 100)
	var bare_damage := _clean_attack(bare)
	var bare_health := bare.max_health

	GameState.add_gear("thunder_pick")
	GameState.add_gear("river_stone")
	GameState.equip(SPROUT, "thunder_pick")
	GameState.equip(SPROUT, "river_stone")

	var geared := BattleState.new()
	geared.setup(_slime(), _sprout(), 100)
	check(_clean_attack(geared) > bare_damage, "аксессуар усилил удар в бою")
	check(geared.max_health > bare_health, "амулет поднял максимум здоровья")

	# Обувь расширяет окна: то, что было Good, становится Perfect
	GameState.add_gear("cloud_shoes")
	GameState.equip(SPROUT, "cloud_shoes")
	var shod := BattleState.new()
	shod.setup(_slime(), _sprout(), 100)
	check(shod.window_scale > 1.0, "окна расширены")
	check_eq(Judge.grade(0.070, shod.window_scale), Judge.Grade.PERFECT,
		"с обувью попадание в 70 мс стало идеальным")
	check_eq(Judge.grade(0.070, 1.0), Judge.Grade.GOOD, "без обуви оно же — просто хорошее")


func _test_shield_never_free() -> void:
	print("Щит нельзя обнулить снаряжением")
	GameState.reset()
	_sprout()

	# Сначала тот же удар БЕЗ амулета. Сравнивать надо с ним, а не с голой
	# константой: урон умножается ещё и на шкалу грейда, и стоило поднять её
	# обычному монстру, как исправный амулет «перестал» смягчать — тест мерил
	# не снаряжение, а лестницу грейдов
	#
	# Урон меряем суммарно: он гасится щитом раньше здоровья, и смотреть
	# только на здоровье значит не увидеть удар вовсе
	var bare := BattleState.new()
	bare.setup(_slime(), _sprout(), 100)
	var bare_before := bare.shield + bare.health
	bare.take_strike()
	var bare_damage := bare_before - (bare.shield + bare.health)

	GameState.add_gear("heartwood_amulet")
	GameState.equip(SPROUT, "heartwood_amulet")

	var s := BattleState.new()
	s.setup(_slime(), _sprout(), 100)
	var before := s.shield + s.health
	s.take_strike()
	var damage := before - (s.shield + s.health)

	check(damage > 0, "пропущенный щит всё равно бьёт — механика обязана остаться")
	check(damage < bare_damage,
		"но амулет смягчил удар (%d против %d без него)" % [damage, bare_damage])

	# Даже при абсурдном снижении урон не уходит в ноль
	s.shield_reduction = 5.0
	var mid := s.shield + s.health
	s.take_strike()
	check(mid - (s.shield + s.health) >= 1, "урон не обнуляется ни при каком снаряжении")


## Снаряжение принадлежит ЭКЗЕМПЛЯРУ.
##
## Проверяется на двух экземплярах ОДНОГО вида: это и есть новый смысл
## правила. Ключуй дружбу или экипировку видом — и редкий Ростик молча
## наденет пояс обычного.
func _test_gear_is_per_instance() -> void:
	print("Снаряжение привязано к экземпляру, а не к виду")
	GameState.reset()
	_sprout()
	var rare := GameState.tame("disco_sprout", MonsterData.Rarity.RARE)

	GameState.add_gear("spring_boots")
	GameState.equip(SPROUT, "spring_boots")

	check(GameState.equipped_gear(SPROUT, GearData.Slot.BELT) != null,
		"на обычном надето")
	check(GameState.equipped_gear(rare.key(), GearData.Slot.BELT) == null,
		"на редком того же вида пусто — это разные существа")
	check_eq(GameState.gear_bonuses(rare.key()).window_scale, 1.0,
		"бонусы не протекают между грейдами одного вида")

	# И между разными видами тоже
	_bear()
	check(GameState.equipped_gear(BEAR, GearData.Slot.BELT) == null,
		"на другом виде пусто — смена гуардиана должна быть решением, а не сменой скина")
	check_eq(GameState.gear_bonuses(BEAR).window_scale, 1.0, "чужие бонусы не протекают")


func _test_guardian_selection() -> void:
	print("Выбор гуардиана")
	GameState.reset()
	check(GameState.guardian() == null, "без коллекции гуардиана нет")
	check_eq(GameState.guardian_key(), "", "ключ пуст")

	var sprout := _sprout()
	check_eq(GameState.guardian_key(), sprout.key(),
		"первый приручённый берётся по умолчанию")

	check(not GameState.set_guardian("beat_serpent:0"), "неприручённого выбрать нельзя")

	var bear := _bear()
	check(GameState.set_guardian(bear.key()), "приручённого выбрать можно")
	check_eq(GameState.guardian_key(), bear.key(), "выбор применился")

	# Разные грейды одного вида — разные кандидаты в гуардианы
	var rare_sprout := GameState.tame("disco_sprout", MonsterData.Rarity.RARE)
	check(GameState.set_guardian(rare_sprout.key()), "редкий экземпляр тоже можно взять")
	check_eq(GameState.guardian_key(), rare_sprout.key(),
		"в лес идёт именно редкий, а не обычный того же вида")


func _test_save_roundtrip() -> void:
	print("Сейв снаряжения")
	GameState.reset()
	var sprout := _sprout()
	GameState.set_guardian(sprout.key())
	GameState.add_gear("cloud_shoes")
	GameState.add_gear("brass_bell", 2)
	GameState.equip(SPROUT, "cloud_shoes")

	# JSON превращает целые ключи слотов в строки — прогоняем через настоящую
	# сериализацию, иначе экипировка молча перестала бы находиться
	var json := JSON.stringify(GameState.to_dict())
	var restored: Dictionary = JSON.parse_string(json)

	GameState.reset()
	GameState.from_dict(restored)

	check_eq(GameState.gear_count("brass_bell"), 2, "сундук восстановился")
	var boots := GameState.equipped_gear(SPROUT, GearData.Slot.BELT)
	check(boots != null, "надетое нашлось после JSON-цикла")
	if boots != null:
		check_eq(boots.id, "cloud_shoes", "именно тот предмет")
	check_eq(GameState.guardian_key(), SPROUT, "выбранный гуардиан восстановился")
	check(GameState.gear_bonuses(SPROUT).window_scale > 1.0, "бонусы снова считаются")


## Провести чистую серию и ударить. Обычные биты урона не наносят,
## поэтому победить можно только так (GDD §4.3).
func _clean_attack(state: BattleState, grade := Judge.Grade.PERFECT) -> int:
	for i in BattleState.min_series_length():
		state.register_hit(Judge.Grade.PERFECT)
	return state.register_attack(grade)
