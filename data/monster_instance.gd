class_name MonsterInstance
extends RefCounted

## Конкретный приручённый монстр: вид + грейд + уровень.
##
## Грейд принадлежит ЭКЗЕМПЛЯРУ, а не виду (GDD §6.3): один и тот же Ростик
## на поляне может оказаться и обычным, и легендарным, и в коллекции они
## живут отдельными существами — со своим уровнем и своим снаряжением.
##
## Ключ композитный, «вид:грейд». Счётчик-uid не нужен: два экземпляра одного
## вида И грейда коллекции ничего не дают, а такой ключ сам по себе не даёт
## завести дубль, сериализуется строкой и превращает правило «приручён в этом
## грейде или выше» в перебор грейдов, а не в поиск по массиву.

var species_id: String = ""
var grade: int = MonsterData.Rarity.COMMON
## Уровень 1..Balance.max_level(). Растёт от побед и от угощений (GDD §6.5).
var level: int = 1
var xp: int = 0


static func create(new_species_id: String, new_grade: int) -> MonsterInstance:
	var out := MonsterInstance.new()
	out.species_id = new_species_id
	out.grade = new_grade
	return out


static func key_for(new_species_id: String, new_grade: int) -> String:
	return "%s:%d" % [new_species_id, new_grade]


static func from_key(key: String) -> MonsterInstance:
	var parts := key.split(":")
	if parts.size() != 2:
		push_error("Испорченный ключ экземпляра: %s" % key)
		return null
	return create(parts[0], int(parts[1]))


func key() -> String:
	return key_for(species_id, grade)


func data() -> MonsterData:
	return Registry.monster(species_id)


func display_name() -> String:
	var d := data()
	return d.display_name if d != null else species_id


func grade_name() -> String:
	return MonsterData.rarity_name(grade)


func grade_color() -> Color:
	return MonsterData.rarity_color(grade)


## Спрайт с учётом грейда. Пока грейд не нарисован, показывается
## максимальный доступный (GDD §6.3).
func sprite() -> Texture2D:
	var d := data()
	return d.sprite_for_grade(grade) if d != null else null


## Общий множитель статов: грейд и уровень вместе.
##
## Обе части — про «насколько это существо крепче базового», поэтому
## перемножаются, а не складываются: легендарный десятого уровня обязан
## ощущаться как вершина, а не как обычный с прибавкой.
func stat_scale() -> float:
	var by_grade := Balance.grade_stat_scale(grade)
	var by_level := 1.0 + Balance.level_stat_bonus() * float(level - 1)
	return by_grade * by_level


## Насколько больно бьёт ЭТОТ экземпляр как противник.
##
## Отдельно от `stat_scale`: крепость и злость растут по разным кривым
## (GDD §6.3). Уровень входит и сюда — приручённый монстр в бою не участвует
## как враг, но правило одно на всех.
func strike_scale() -> float:
	var by_grade := Balance.grade_strike_scale(grade)
	var by_level := 1.0 + Balance.level_stat_bonus() * float(level - 1)
	return by_grade * by_level


func max_health() -> int:
	var d := data()
	return int(round(float(d.base_health if d != null else 100) * stat_scale()))


func power() -> float:
	var d := data()
	return (d.base_power if d != null else 4.0) * stat_scale()


func vibe() -> int:
	var d := data()
	return int(round(float(d.base_vibe if d != null else 100) * stat_scale()))


func genre() -> int:
	var d := data()
	return d.genre if d != null else MonsterData.Genre.DISCO


# --- уровень -----------------------------------------------------------------

func is_max_level() -> bool:
	return level >= Balance.max_level()


## Начислить опыт. Возвращает, сколько уровней взято за раз: несколько
## уровней подряд — законный случай при угощении редким фруктом.
func add_xp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	xp += amount
	var gained := 0
	while not is_max_level() and xp >= Balance.xp_for_level(level + 1):
		level += 1
		gained += 1
	if is_max_level():
		# На потолке опыт больше не копится: иначе полоска росла бы в никуда
		xp = Balance.xp_for_level(level)
	return gained


## Сколько опыта нужно до следующего уровня и сколько уже есть — для полоски.
func xp_progress() -> Vector2i:
	if is_max_level():
		return Vector2i(1, 1)
	var current := Balance.xp_for_level(level)
	var next := Balance.xp_for_level(level + 1)
	return Vector2i(xp - current, maxi(next - current, 1))


# --- сериализация ------------------------------------------------------------

## Вид и грейд лежат в ключе словаря, поэтому здесь не дублируются.
func to_dict() -> Dictionary:
	return {"level": level, "xp": xp}


static func from_dict(key: String, d: Dictionary) -> MonsterInstance:
	var out := from_key(key)
	if out == null:
		return null
	out.level = clampi(int(d.get("level", 1)), 1, Balance.max_level())
	out.xp = maxi(int(d.get("xp", 0)), 0)
	return out
