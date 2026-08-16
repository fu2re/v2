extends Node

## Магазин: косметика, сундуки, регуляторные рамки.
##
## Аудитория включает детей, а это переводит платный рандом в зону жёсткого
## регулирования (GDD §12.3). Требования встроены в код, а не в инструкцию
## для разработчика: инструкцию можно забыть, инвариант — нет.

signal gold_changed(amount: int)
signal cosmetic_unlocked(cosmetic_id: String)
signal crate_opened(cosmetic_id: String, was_duplicate: bool, pity_hit: bool)
signal purchase_blocked(reason: String)

## Все числа пластинки — цена, шансы, pity, возврат за дубль, регионы —
## живут в drop_tables.json → cosmetic_crate и читаются через Balance.
## Пока они были константами здесь, таблица объявляла себя источником
## истины, но не читалась, и обе копии успели разойтись (SHOP.md §4).

## Шансы выпадения по редкости: индекс грейда -> процент. Публикуются
## в интерфейсе покупки — без этого игру не пропустят ни App Store,
## ни Google Play.
static func crate_odds() -> Dictionary:
	return Balance.crate_odds()


## Гарантированный ценный предмет каждые N открытий. Счётчик виден игроку.
static func pity_threshold() -> int:
	return Balance.crate_pity_threshold()


static func pity_min_rarity() -> int:
	return Balance.crate_pity_min_rarity()


static func crate_price() -> int:
	return Balance.crate_price()


## Дубль конвертируется в Золото: открытие сундука не может пропасть впустую.
static func duplicate_refunds() -> Dictionary:
	var out: Dictionary = {}
	for rarity: int in crate_odds():
		out[rarity] = Balance.crate_duplicate_refund(rarity)
	return out


## Родительский контроль: дневной предел трат в золоте.
const DEFAULT_DAILY_LIMIT := 500

var gold: int = 0
var owned: Array[String] = []
var equipped: Dictionary = {}
var pity_counter: int = 0
var region: String = "XX"

var daily_limit: int = DEFAULT_DAILY_LIMIT
var spent_today: int = 0
var _spend_day: int = -1

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func set_seed(value: int) -> void:
	_rng.seed = value


func reset() -> void:
	gold = 0
	owned.clear()
	equipped.clear()
	pity_counter = 0
	spent_today = 0
	_spend_day = -1
	daily_limit = DEFAULT_DAILY_LIMIT
	region = "XX"


# --- регуляторные рамки ------------------------------------------------------

## Разрешён ли платный рандом в текущем регионе.
func lootboxes_allowed() -> bool:
	return not lootboxes_banned()


func lootboxes_banned() -> bool:
	return Balance.lootbox_banned_regions().has(region.to_upper())


## Сумма шансов. Обязана быть ровно 100 — иначе публикуемые цифры лгут.
static func odds_total() -> float:
	var total := 0.0
	for weight: float in crate_odds().values():
		total += weight
	return total


## Текст для экрана покупки. Показывается ДО оплаты, не после.
func odds_disclosure() -> String:
	var lines: Array[String] = ["Шансы выпадения:"]
	var odds := crate_odds()
	for rarity: int in odds:
		lines.append("  %s — %.1f%%" % [
			MonsterData.rarity_name(rarity), odds[rarity],
		])
	lines.append("")
	lines.append("Гарантированный %s предмет через %d открытий." % [
		MonsterData.rarity_name(pity_min_rarity()).to_lower(),
		pity_threshold() - pity_counter,
	])
	return "\n".join(lines)


# --- валюта и лимиты ---------------------------------------------------------

func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func _today() -> int:
	var d := Time.get_datetime_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


func _roll_day_if_needed() -> void:
	var today := _today()
	if _spend_day != today:
		_spend_day = today
		spent_today = 0


func remaining_today() -> int:
	_roll_day_if_needed()
	return maxi(daily_limit - spent_today, 0)


## Проверка перед списанием. Возвращает пустую строку, если можно.
func _blocking_reason(cost: int) -> String:
	if cost <= 0:
		return "Некорректная цена"
	if gold < cost:
		return "Не хватает золота"
	if remaining_today() < cost:
		return "Дневной лимит трат исчерпан. Загляни завтра."
	return ""


func _spend(cost: int) -> bool:
	var reason := _blocking_reason(cost)
	if not reason.is_empty():
		purchase_blocked.emit(reason)
		return false
	_roll_day_if_needed()
	gold -= cost
	spent_today += cost
	gold_changed.emit(gold)
	return true


# --- косметика ---------------------------------------------------------------

func is_owned(cosmetic_id: String) -> bool:
	return owned.has(cosmetic_id)


func unlock(cosmetic_id: String) -> void:
	if is_owned(cosmetic_id):
		return
	owned.append(cosmetic_id)
	cosmetic_unlocked.emit(cosmetic_id)


## Прямая покупка. Доступна для ЛЮБОГО предмета, включая содержимое сундуков.
func buy_direct(cosmetic_id: String) -> bool:
	var item := Registry.cosmetic(cosmetic_id)
	if item == null or is_owned(cosmetic_id):
		return false
	if not _spend(item.price_gold):
		return false
	unlock(cosmetic_id)
	SaveManager.mark_dirty()
	return true


func equip(cosmetic_id: String) -> bool:
	var item := Registry.cosmetic(cosmetic_id)
	if item == null or not is_owned(cosmetic_id):
		return false
	equipped[item.slot] = cosmetic_id
	SaveManager.mark_dirty()
	return true


func equipped_in(slot: CosmeticData.Slot) -> CosmeticData:
	var id: String = equipped.get(slot, "")
	return Registry.cosmetic(id) if not id.is_empty() else null


# --- сундуки -----------------------------------------------------------------

func crate_pool() -> Array[CosmeticData]:
	var out: Array[CosmeticData] = []
	for item in Registry.all_cosmetics():
		if item.in_crates:
			out.append(item)
	return out


## Открыть сундук. Возвращает id выпавшего предмета или пустую строку.
func open_crate() -> String:
	if lootboxes_banned():
		purchase_blocked.emit("В этом регионе сундуки недоступны. Всё есть в прямой продаже.")
		return ""
	if not _spend(crate_price()):
		return ""

	pity_counter += 1
	var pity_hit := pity_counter >= pity_threshold()
	var rarity := pity_min_rarity() if pity_hit else _roll_rarity()
	if pity_hit:
		pity_counter = 0
	elif rarity >= pity_min_rarity():
		# Ценный выпал сам — счётчик честно сбрасывается, а не копится дальше
		pity_counter = 0

	var item := _pick_from(rarity)
	if item == null:
		return ""

	var duplicate := is_owned(item.id)
	if duplicate:
		# Дубль не пропадает: возвращается золотом (GDD §12.3, правило 3)
		add_gold(Balance.crate_duplicate_refund(item.rarity))
	else:
		unlock(item.id)

	SaveManager.mark_dirty()
	crate_opened.emit(item.id, duplicate, pity_hit)
	return item.id


func _roll_rarity() -> MonsterData.Rarity:
	var odds := crate_odds()
	var roll := _rng.randf() * odds_total()
	for rarity: int in odds:
		roll -= float(odds[rarity])
		if roll <= 0.0:
			return rarity as MonsterData.Rarity
	return MonsterData.Rarity.COMMON


## Если предметов нужной редкости нет, спускаемся вниз, а не падаем:
## контент добавляется постепенно, дыра в пуле не должна ломать покупку.
func _pick_from(rarity: MonsterData.Rarity) -> CosmeticData:
	var pool := crate_pool()
	for r in range(rarity, -1, -1):
		var matching: Array[CosmeticData] = []
		for item in pool:
			if item.rarity == r:
				matching.append(item)
		if not matching.is_empty():
			return matching[_rng.randi_range(0, matching.size() - 1)]
	return pool[0] if not pool.is_empty() else null


# --- сериализация ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"owned": owned.duplicate(),
		"equipped": equipped.duplicate(),
		"pity": pity_counter,
		"region": region,
		"daily_limit": daily_limit,
		"spent_today": spent_today,
		"spend_day": _spend_day,
	}


func from_dict(d: Dictionary) -> void:
	gold = int(d.get("gold", 0))
	pity_counter = int(d.get("pity", 0))
	region = d.get("region", "XX")
	daily_limit = int(d.get("daily_limit", DEFAULT_DAILY_LIMIT))
	spent_today = int(d.get("spent_today", 0))
	_spend_day = int(d.get("spend_day", -1))

	owned.clear()
	for id: Variant in d.get("owned", []):
		owned.append(String(id))

	# Ключи слотов приходят из JSON строками
	equipped.clear()
	var raw: Dictionary = d.get("equipped", {})
	for key: Variant in raw:
		equipped[int(key)] = String(raw[key])
