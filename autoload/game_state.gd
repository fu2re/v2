extends Node

## Постоянный прогресс игрока: коллекция, дружба, инвентарь.
##
## Коллекция хранит ЭКЗЕМПЛЯРЫ (вид + грейд + уровень), а не виды: грейд
## принадлежит существу (GDD §6.3), и обычный Ростик с редким живут рядом
## как разные друзья, каждый со своим снаряжением и уровнем.
##
## Дружба здесь ключевая: она НИКОГДА не сбрасывается — ни при смерти,
## ни между забегами. Худший исход встречи — «стало ближе», а не
## «не получилось» (GDD §6.1). Это главная защита от детской фрустрации.

signal friendship_changed(species_id: String, grade: int, value: int, threshold: int)
signal monster_tamed(instance_key: String)
signal fruits_changed()
signal silver_changed(amount: int)
signal gear_changed()
signal guardian_changed(instance_key: String)

## Схема сейва. Версия 2: коллекция переехала с видов на экземпляры,
## дружба — на пары «вид + грейд». Старые сейвы несовместимы и отбрасываются
## целиком (SaveManager), миграция не пишется: игра в разработке.
const SAVE_VERSION := 2

## Прибавки к дружбе (GDD §6.1). Ноль рандома.
const FRIENDSHIP_WIN := 10
const FRIENDSHIP_PERFECT_WIN := 15
const FRIENDSHIP_FAVORITE_FRUIT := 35
const FRIENDSHIP_OTHER_FRUIT := 10

## Дружба по ПАРЕ «вид + грейд»: ключ экземпляра -> накопленные очки.
##
## Шкалы грейдов независимы (GDD §6.1): дружба 20/100 с обычным Ростиком
## не приближает редкого — тому копить свои 200 с нуля. Иначе игрок фармил бы
## самого безопасного монстра вида и получал легендарного, ни разу
## не встретившись с трудным.
var friendship: Dictionary = {}

## Опыт боёв против ВИДА: species_id -> число встреч.
##
## Ключуется видом, а не экземпляром, и это намеренно: опыт — про изученность
## повадок (GDD §6.4), а повадки у вида одни на все грейды. Дружба говорит,
## насколько существо к тебе расположено, опыт — насколько ты его понял.
var battle_xp: Dictionary = {}

## Приручённые экземпляры: ключ "вид:грейд" -> MonsterInstance.
var instances: Dictionary = {}

## Кого игрок уже победил, ключом «вид:грейд». Отдельно от `instances`:
## приручить можно не всё, что победил, а коллекция обязана помнить встречу
## даже когда экземпляр не достался. Пока пары здесь нет, монстр показан
## силуэтом — это и есть главная приманка коллекции (GDD §7.5).
var defeated: Dictionary = {}

## Фрукты в сумке: "fruit_id:quality" -> количество.
var fruits: Dictionary = {}
## Зелья в сумке: potion_id -> количество.
##
## Отдельно от фруктов: фрукт скармливают монстру ради дружбы, зелье
## выпивают сами ради здоровья. Общее хранилище смешало бы две разные вещи.
var potions: Dictionary = {}
## Заработанная валюта: серебро.
var silver: int = 0

## Снаряжение в сундуке: gear_id -> количество.
var gear_owned: Dictionary = {}
## Надето на экземпляров: ключ экземпляра -> { slot(int) -> gear_id }.
## Снаряжение привязано к конкретному существу, а не к игроку: смена
## гуардиана должна быть настоящим решением, а не сменой скина.
var equipped: Dictionary = {}
## Кого берём в лес — ключ экземпляра.
var active_guardian_key: String = ""

## Пол героя: выбирается один раз перед интро (GDD §15.5).
## Пустая строка — выбора ещё не было, и экран выбора нужно показать.
var hero_gender: String = ""

## Спрайты героя. Мальчик достался от первой версии игры и остался
## под своим именем: переименовывать готовый ассет ради симметрии значит
## ломать ссылки там, где он уже используется.
const HERO_SPRITES := {
	"boy": "res://art/hero/hero_kid.png",
	"girl": "res://art/hero/hero_girl.png",
}
const HERO_FALLBACK := "res://art/placeholder/hero.png"


func reset() -> void:
	friendship.clear()
	battle_xp.clear()
	instances.clear()
	defeated.clear()
	fruits.clear()
	potions.clear()
	silver = 0
	gear_owned.clear()
	equipped.clear()
	active_guardian_key = ""
	hero_gender = ""


# --- коллекция ---------------------------------------------------------------

func instance(key: String) -> MonsterInstance:
	return instances.get(key)


func has_instance(species_id: String, grade: int) -> bool:
	return instances.has(MonsterInstance.key_for(species_id, grade))


## Все приручённые, отсортированы по виду и грейду — порядок карточек
## не должен прыгать между запусками.
func all_instances() -> Array[MonsterInstance]:
	var out: Array[MonsterInstance] = []
	var keys: Array = instances.keys()
	keys.sort()
	for key: String in keys:
		out.append(instances[key])
	return out


## Приручить экземпляр. Возвращает его же, даже если он уже был:
## вызывающему нужен объект, а не факт новизны.
func tame(species_id: String, grade: int) -> MonsterInstance:
	var key := MonsterInstance.key_for(species_id, grade)
	if instances.has(key):
		return instances[key]

	var created := MonsterInstance.create(species_id, grade)
	instances[key] = created
	if active_guardian_key.is_empty():
		set_guardian(key)
	monster_tamed.emit(key)
	return created


## Лучший приручённый грейд вида. -1, если вида в коллекции нет.
func best_grade(species_id: String) -> int:
	var best := -1
	for key: String in instances:
		var inst: MonsterInstance = instances[key]
		if inst.species_id == species_id:
			best = maxi(best, inst.grade)
	return best


func is_tamed(species_id: String) -> bool:
	return best_grade(species_id) >= 0


## Приручён ли вид в этом грейде ИЛИ ВЫШЕ.
##
## Это правило пропуска боя (GDD §8.1): мимо можно пройти только там,
## что уже превзойдено. Незнакомый вид и более редкий экземпляр знакомого —
## обязательный бой.
func is_tamed_at_least(species_id: String, grade: int) -> bool:
	return best_grade(species_id) >= grade


## Можно ли вообще приручить экземпляр этого грейда.
##
## Лестница снизу вверх: редкий доступен только тому, у кого уже есть
## необычный, а тот — только после обычного. Перепрыгнуть через ступень
## нельзя, даже если шкала дружбы полна.
##
## Так знакомство с видом идёт по порядку: сначала простой танец, потом
## тот же зверь в более быстром ремиксе, и только потом вершина. Иначе
## удачная встреча с легендарным на глубине отдавала бы игроку сразу
## вершину коллекции, минуя всё, ради чего она собиралась.
func can_tame(species_id: String, grade: int) -> bool:
	if grade <= MonsterData.Rarity.COMMON:
		return true
	return has_instance(species_id, grade - 1)


## Какого грейда не хватает, чтобы открыть этот. -1, если путь открыт.
func missing_step(species_id: String, grade: int) -> int:
	return -1 if can_tame(species_id, grade) else grade - 1


# --- дружба и приручение -----------------------------------------------------

func get_friendship(species_id: String, grade: int) -> int:
	return friendship.get(MonsterInstance.key_for(species_id, grade), 0)


func friendship_threshold(grade: int) -> int:
	return Balance.friendship_threshold(grade)


## Начислить дружбу конкретной паре «вид + грейд».
##
## Возвращает true, если экземпляр только что присоединился. Прибавка
## не требует броска кубика: заполнилась шкала — монстр твой, гарантированно.
func add_friendship(species_id: String, grade: int, amount: int) -> bool:
	if Registry.monster(species_id) == null:
		push_error("Неизвестный монстр: %s" % species_id)
		return false

	var key := MonsterInstance.key_for(species_id, grade)

	# Дружба НЕ копится там, где приручать пока нельзя.
	#
	# Раньше она копилась «про запас»: шкала росла, фрукты тратились,
	# а приручение всё равно не наступало, пока не пройдена ступень ниже.
	# Копить в закрытую шкалу — то же самое, что выбрасывать фрукты:
	# полоска движется, а сделать с ней ничего нельзя. Лучше честно
	# не принимать вклад и сказать, чего не хватает.
	if not can_tame(species_id, grade):
		return false

	# С тем, кто уже в коллекции, дружиться заново не с кем
	if instances.has(key):
		return false

	var threshold := friendship_threshold(grade)
	var value: int = mini(get_friendship(species_id, grade) + amount, threshold)
	friendship[key] = value
	friendship_changed.emit(species_id, grade, value, threshold)

	if value >= threshold and not instances.has(key) and can_tame(species_id, grade):
		tame(species_id, grade)
		return true
	return false


## Сколько дружбы даст угощение этим фруктом. Считается отдельно от начисления,
## чтобы интерфейс мог показать цифру ДО подтверждения.
func friendship_from_fruit(species_id: String, fruit_id: String,
		quality: FruitData.Quality) -> int:
	var data := Registry.monster(species_id)
	if data == null:
		return 0
	var base := FRIENDSHIP_FAVORITE_FRUIT if data.favorite_fruit_id == fruit_id \
		else FRIENDSHIP_OTHER_FRUIT

	# Щедрость плода задаёт ТИР, а не качество: качеств три, а тиров четыре,
	# и на трёх ступенях два соседних тира давали поровну — редкий инжир рос
	# вчетверо дольше сливки и стоил вдвое дороже ровно за ту же прибавку
	var fruit := Registry.fruit(fruit_id)
	var scale := FruitData.tier_friendship_scale(fruit.tier) if fruit != null else 1.0
	return int(round(base * scale))


## Сколько опыта даст угощение этим фруктом (GDD §6.5).
##
## Любимый фрукт вдвое ценнее, качество умножает — те же правила, что
## и у дружбы. Одно угощение, один язык: дружишь — угощаешь.
func feeding_xp(species_id: String, fruit_id: String,
		quality: FruitData.Quality) -> int:
	var fruit := Registry.fruit(fruit_id)
	if fruit == null:
		return 0

	var base := Balance.feeding_xp_for_tier(fruit.tier)
	# Опыт уже считается от тира — второй множитель по качеству накручивал бы
	# тир дважды
	var multiplier := 1.0

	var species := Registry.monster(species_id)
	if species != null and species.favorite_fruit_id == fruit_id:
		multiplier *= Balance.feeding_favorite_multiplier()
	return int(round(base * multiplier))


## Угостить экземпляр. Возвращает начисленный опыт (0 — не вышло).
func feed(instance_key: String, fruit_id: String,
		quality: FruitData.Quality) -> int:
	var friend := instance(instance_key)
	if friend == null or friend.is_max_level():
		return 0
	if not consume_fruit(fruit_id, quality):
		return 0

	var gained := feeding_xp(friend.species_id, fruit_id, quality)
	friend.add_xp(gained)
	return gained


# --- опыт боёв ---------------------------------------------------------------

## Прибавка к урону за каждую встречу с видом.
static func xp_damage_step() -> float:
	return Balance.species_xp_step()


## Потолок прибавки. Без него сотая встреча превращала бы бой в формальность,
## а редкие виды обесценивались бы у того, кто их фармит.
static func xp_damage_cap() -> float:
	return Balance.species_xp_cap()


func battle_experience(species_id: String) -> int:
	return battle_xp.get(species_id, 0)


func add_battle_experience(species_id: String) -> void:
	battle_xp[species_id] = battle_experience(species_id) + 1


## Множитель урона по этому виду. Растёт от встреч и упирается в потолок.
func experience_multiplier(species_id: String) -> float:
	return 1.0 + minf(battle_experience(species_id) * xp_damage_step(), xp_damage_cap())


# --- инвентарь фруктов -------------------------------------------------------

static func fruit_key(fruit_id: String, quality: FruitData.Quality) -> String:
	return "%s:%d" % [fruit_id, quality]


func add_fruit(fruit_id: String, quality: FruitData.Quality, count: int = 1) -> void:
	var key := fruit_key(fruit_id, quality)
	fruits[key] = fruits.get(key, 0) + count
	fruits_changed.emit()


func fruit_count(fruit_id: String, quality: FruitData.Quality) -> int:
	return fruits.get(fruit_key(fruit_id, quality), 0)


func total_fruit_count(fruit_id: String) -> int:
	var total := 0
	for quality in [FruitData.Quality.PLAIN, FruitData.Quality.JUICY, FruitData.Quality.PERFECT]:
		total += fruit_count(fruit_id, quality)
	return total


func consume_fruit(fruit_id: String, quality: FruitData.Quality) -> bool:
	var key := fruit_key(fruit_id, quality)
	var have: int = fruits.get(key, 0)
	if have <= 0:
		return false
	if have == 1:
		fruits.erase(key)
	else:
		fruits[key] = have - 1
	fruits_changed.emit()
	return true


func add_silver(amount: int) -> void:
	silver = maxi(silver + amount, 0)
	silver_changed.emit(silver)


# --- зелья -------------------------------------------------------------------

## Сколько зелий помещается в сумку.
##
## Предел, а не место под склад: с тремя глотками бой остаётся боем.
## Без предела достаточно накопить два десятка отваров, и любая встреча
## выигрывается перепиванием, а ритм перестаёт что-либо решать.
const MAX_POTIONS := 3


## Положить зелье в сумку. Возвращает, сколько влезло: сверх предела
## не берём, и покупка сверх него не должна молча съедать серебро.
func add_potion(potion_id: String, count: int = 1) -> int:
	if Registry.potion(potion_id) == null:
		push_error("Неизвестное зелье: %s" % potion_id)
		return 0
	var room := MAX_POTIONS - total_potions()
	var taken := mini(count, maxi(room, 0))
	if taken <= 0:
		return 0
	potions[potion_id] = potions.get(potion_id, 0) + taken
	fruits_changed.emit()
	return taken


## Влезет ли ещё хоть одно. Спрашивают лавка и сундук — до того,
## как взять деньги.
func has_potion_room() -> bool:
	return total_potions() < MAX_POTIONS


func potion_count(potion_id: String) -> int:
	return potions.get(potion_id, 0)


func total_potions() -> int:
	var total := 0
	for count: int in potions.values():
		total += count
	return total


## Есть ли что пить. От этого зависит, ставится ли нота-зелье в бой:
## игра никогда не предлагает нажать то, что не сработает (GDD §4.2.3).
func has_any_potion() -> bool:
	return total_potions() > 0


## Какое зелье выпьется следующим.
##
## Зелье в игре одно, и выбирать не из чего — это намеренно: выбор посреди
## ритмической фразы игрок всё равно сделать не успевает, а два похожих
## пузырька в сумке только заставляли жадничать. Перебор остался на случай
## будущих зелий и берёт слабейшее.
func next_potion() -> PotionData:
	var best: PotionData = null
	for potion_id: String in potions:
		if potions[potion_id] <= 0:
			continue
		var item := Registry.potion(potion_id)
		if item == null:
			continue
		if best == null or item.restore_health < best.restore_health:
			best = item
	return best


## Выпить зелье. Возвращает, сколько здоровья оно вернуло (0 — нечего пить).
func consume_potion() -> int:
	var item := next_potion()
	if item == null:
		return 0

	var left := potion_count(item.id) - 1
	if left <= 0:
		potions.erase(item.id)
	else:
		potions[item.id] = left
	fruits_changed.emit()
	return item.restore_health


# --- снаряжение --------------------------------------------------------------

func add_gear(gear_id: String, count: int = 1) -> void:
	if Registry.gear(gear_id) == null:
		push_error("Неизвестное снаряжение: %s" % gear_id)
		return
	gear_owned[gear_id] = gear_owned.get(gear_id, 0) + count
	gear_changed.emit()


func gear_count(gear_id: String) -> int:
	return gear_owned.get(gear_id, 0)


func owned_gear_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in gear_owned:
		if gear_owned[id] > 0:
			out.append(id)
	out.sort()
	return out


## Надеть предмет на ЭКЗЕМПЛЯР. Снятый возвращается в сундук — экипировка
## обратима, иначе игрок боится экспериментировать.
func equip(instance_key: String, gear_id: String) -> bool:
	var item := Registry.gear(gear_id)
	if item == null or gear_count(gear_id) <= 0:
		return false
	if not instances.has(instance_key):
		return false

	var slots: Dictionary = equipped.get(instance_key, {})
	var previous: String = slots.get(item.slot, "")
	if previous == gear_id:
		return false
	if not previous.is_empty():
		gear_owned[previous] = gear_count(previous) + 1

	gear_owned[gear_id] = gear_count(gear_id) - 1
	if gear_owned[gear_id] <= 0:
		gear_owned.erase(gear_id)

	slots[item.slot] = gear_id
	equipped[instance_key] = slots
	gear_changed.emit()
	return true


func unequip(instance_key: String, slot: GearData.Slot) -> bool:
	var slots: Dictionary = equipped.get(instance_key, {})
	var gear_id: String = slots.get(slot, "")
	if gear_id.is_empty():
		return false
	slots.erase(slot)
	equipped[instance_key] = slots
	gear_owned[gear_id] = gear_count(gear_id) + 1
	gear_changed.emit()
	return true


func equipped_gear(instance_key: String, slot: GearData.Slot) -> GearData:
	var slots: Dictionary = equipped.get(instance_key, {})
	var gear_id: String = slots.get(slot, "")
	return Registry.gear(gear_id) if not gear_id.is_empty() else null


func equipped_slots(instance_key: String) -> Dictionary:
	return equipped.get(instance_key, {})


## Суммарный эффект надетого. Считается в одном месте, чтобы бой и интерфейс
## не разъехались в трактовке одних и тех же чисел.
func gear_bonuses(instance_key: String) -> Dictionary:
	var total := {
		"window_scale": 1.0,
		"power_bonus": 0.0,
		"health_bonus": 0,
		"shield_reduction": 0.0,
	}
	for slot in [GearData.Slot.BELT, GearData.Slot.CLOAK, GearData.Slot.HEADWEAR]:
		var item := equipped_gear(instance_key, slot)
		if item == null:
			continue
		# Окна перемножаются, остальное складывается: так два предмета
		# на окна не дают линейного взрыва прощения промахов
		total.window_scale *= item.window_scale
		total.power_bonus += item.power_bonus
		total.health_bonus += item.health_bonus
		total.shield_reduction = minf(total.shield_reduction + item.shield_reduction, 0.75)
	return total


# --- гуардиан ----------------------------------------------------------------

## Кто пойдёт в лес. Если выбранный недоступен, берём первого приручённого.
func guardian() -> MonsterInstance:
	if instances.has(active_guardian_key):
		return instances[active_guardian_key]
	var all := all_instances()
	return all[0] if not all.is_empty() else null


## Ключ активного гуардиана или пустая строка, если коллекция пуста.
func guardian_key() -> String:
	var current := guardian()
	return current.key() if current != null else ""


# --- герой -------------------------------------------------------------------

func set_hero_gender(gender: String) -> void:
	if not HERO_SPRITES.has(gender):
		push_error("Неизвестный герой: %s" % gender)
		return
	hero_gender = gender
	SaveManager.mark_dirty()


func has_chosen_hero() -> bool:
	return HERO_SPRITES.has(hero_gender)


## Спрайт героя. Пока выбора нет — плейсхолдер: игра обязана рисоваться
## и до экрана выбора, иначе любой тест сцены упрётся в пустую текстуру.
func hero_sprite() -> Texture2D:
	var path: String = HERO_SPRITES.get(hero_gender, HERO_FALLBACK)
	if not ResourceLoader.exists(path):
		path = HERO_FALLBACK
	return load(path) as Texture2D


func set_guardian(instance_key: String) -> bool:
	if not instances.has(instance_key):
		return false
	active_guardian_key = instance_key
	guardian_changed.emit(instance_key)
	return true


# --- сериализация ------------------------------------------------------------

func to_dict() -> Dictionary:
	var serialized_instances: Dictionary = {}
	for key: String in instances:
		var inst: MonsterInstance = instances[key]
		serialized_instances[key] = inst.to_dict()

	return {
		"version": SAVE_VERSION,
		"friendship": friendship.duplicate(),
		"battle_xp": battle_xp.duplicate(),
		"instances": serialized_instances,
		"defeated": defeated.duplicate(),
		"fruits": fruits.duplicate(),
		"potions": potions.duplicate(),
		"silver": silver,
		"gear_owned": gear_owned.duplicate(),
		"equipped": equipped.duplicate(true),
		"active_guardian": active_guardian_key,
		"hero_gender": hero_gender,
	}


func from_dict(d: Dictionary) -> void:
	# Совместимость версий проверяется в SaveManager ДО этого вызова:
	# несовместимый сейв не должен доходить сюда даже частично
	friendship = d.get("friendship", {})
	battle_xp = d.get("battle_xp", {})
	defeated = d.get("defeated", {})
	fruits = d.get("fruits", {})
	potions = d.get("potions", {})
	silver = int(d.get("silver", 0))
	gear_owned = d.get("gear_owned", {})
	active_guardian_key = d.get("active_guardian", "")
	hero_gender = d.get("hero_gender", "")

	instances.clear()
	var raw_instances: Dictionary = d.get("instances", {})
	for key: String in raw_instances:
		var entry: Dictionary = raw_instances[key]
		var restored := MonsterInstance.from_dict(key, entry)
		if restored != null:
			instances[key] = restored

	# JSON не различает целые ключи: слоты возвращаются строками
	# и без обратного приведения экипировка молча перестала бы находиться
	equipped.clear()
	var raw: Dictionary = d.get("equipped", {})
	for instance_key: String in raw:
		var slots: Dictionary = {}
		for slot_key: Variant in raw[instance_key]:
			slots[int(slot_key)] = String(raw[instance_key][slot_key])
		equipped[instance_key] = slots


# --- журнал встреч -----------------------------------------------------------

## Записать победу над экземпляром. Коллекция помнит её навсегда, даже если
## приручить не вышло: увидел — значит открыл.
func mark_defeated(species_id: String, grade: int) -> void:
	var key := MonsterInstance.key_for(species_id, grade)
	if defeated.has(key):
		return
	defeated[key] = true
	SaveManager.mark_dirty()


## Открыт ли монстр в коллекции. Приручённый открыт всегда — иначе сейв
## старой игры показал бы силуэт того, кто уже ходит с игроком в лес.
func is_revealed(species_id: String, grade: int) -> bool:
	var key := MonsterInstance.key_for(species_id, grade)
	return defeated.has(key) or instances.has(key)


## Сколько клеток коллекции открыто и сколько всего. Для строки прогресса:
## собирателю нужно видеть, сколько осталось.
func collection_progress() -> Vector2i:
	var total := Registry.all_monsters().size() * MonsterData.Rarity.size()
	var open := 0
	for species in Registry.all_monsters():
		for grade in range(MonsterData.Rarity.size()):
			if is_revealed(species.id, grade):
				open += 1
	return Vector2i(open, total)
