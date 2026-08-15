class_name MerchantStock
extends RefCounted

## Ассортимент торговца (GDD §8.2.2).
##
## Два прилавка живут по разным правилам, и это не случайность:
##
##   в лесу — три товара, набор жёстко привязан к глубине. Игрок, увидевший
##   товар и решивший сначала добить бой, обязан застать его на месте;
##
##   в усадьбе — витрина, которая обновляется раз в десять минут. Это НЕ
##   таймер давления (GDD §2.4): базовые семена продаются всегда, ничего
##   не исчезает навсегда, и опоздать невозможно — меняются только
##   те несколько строк, ради которых интересно заглянуть ещё раз.

const ROTATION_SECONDS := 600

## Сколько чего лежит на витрине усадьбы сверх постоянных семян.
const FARM_POTION_SLOTS := 2
const FARM_GEAR_SLOTS := 2

## Сколько товаров у лесного торговца.
const FOREST_SLOTS := 3


## Номер текущей витрины. Он же зерно: перезаход в игру витрину
## не перебрасывает, потому что считается от часов, а не от рандома.
static func rotation_index(now_seconds: int = -1) -> int:
	var stamp := now_seconds if now_seconds >= 0 else int(Time.get_unix_time_from_system())
	return stamp / ROTATION_SECONDS


## Сколько секунд до следующей витрины — для подписи «обновится через…».
static func seconds_until_rotation(now_seconds: int = -1) -> int:
	var stamp := now_seconds if now_seconds >= 0 else int(Time.get_unix_time_from_system())
	return ROTATION_SECONDS - (stamp % ROTATION_SECONDS)


## Витрина усадьбы: семена всегда плюс несколько зелий и вещей по ротации.
##
## Возвращает массив ресурсов (FruitData — это семя, PotionData, GearData).
static func farm_stock(rotation: int = -1) -> Array:
	var index := rotation if rotation >= 0 else rotation_index()
	var out: Array = []

	# Базовые семена в продаже ВСЕГДА: без них новая ферма — пустой экран,
	# и «опоздал к витрине» превратилось бы в «не могу играть»
	for fruit in Registry.all_fruits():
		out.append(fruit)

	out.append_array(_rotate(Registry.all_potions(), index, FARM_POTION_SLOTS))
	out.append_array(_rotate(Registry.all_gear(), index + 7, FARM_GEAR_SLOTS))
	return out


## Товар лесного торговца. Зависит от глубины, а не от времени: витрина
## обязана быть одной и той же, пока игрок на этой поляне.
static func forest_stock(depth: int) -> Array:
	var pool: Array = []
	for item in Registry.all_gear():
		pool.append(item)
	for item in Registry.all_potions():
		pool.append(item)
	if pool.is_empty():
		return []

	var out: Array = []
	for i in FOREST_SLOTS:
		out.append(pool[(depth * 7 + i * 3) % pool.size()])
	return out


## Выбрать `count` подряд идущих позиций, начиная со сдвига по номеру витрины.
##
## Ход по кругу, а не случайная выборка: так за несколько ротаций игрок
## увидит весь ассортимент, а не будет ждать, пока рандом покажет нужное.
static func _rotate(pool: Array, index: int, count: int) -> Array:
	var out: Array = []
	if pool.is_empty():
		return out
	for i in mini(count, pool.size()):
		out.append(pool[(index + i) % pool.size()])
	return out


## Цена товара. У семени своей цены нет — она задана тиром в merchant.json.
static func price_of(item: Resource) -> int:
	if item is FruitData:
		return Balance.seed_price(item.tier)
	return int(item.price)


## Что игрок получит: семя сажают, зелье пьют, снаряжение надевают.
static func describe(item: Resource) -> String:
	if item is FruitData:
		return "семя · зреет %s" % _grow_time(item)
	if item is PotionData:
		return item.effect_text()
	return item.effect_text()


static func _grow_time(fruit: FruitData) -> String:
	var seconds := fruit.grow_seconds()
	if seconds >= 3600:
		return "%d ч" % (seconds / 3600)
	if seconds >= 60:
		return "%d мин" % (seconds / 60)
	return "%d сек" % seconds


## Купить за постоянное серебро игрока. Возвращает, вышло ли.
static func buy(item: Resource) -> bool:
	var price := price_of(item)
	if price <= 0 or GameState.silver < price:
		return false

	GameState.add_silver(-price)
	if item is FruitData:
		FarmState.add_seed(item.id, 1)
	elif item is PotionData:
		GameState.add_potion(item.id)
	else:
		GameState.add_gear(item.id)
	SaveManager.mark_dirty()
	return true
