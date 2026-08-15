class_name MonsterData
extends Resource

## Вид монстра. Правится в инспекторе как .tres — статы и пороги не хардкодятся,
## иначе баланс требует программиста на каждую правку.

## Жанры вместо стихий (GDD §5). Трек боя играет в жанре монстра, поэтому
## один мотив в пяти аранжировках даёт пять боевых треков.
enum Genre { ROCK, DISCO, FOLK, ELECTRO, HIPHOP }

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Силуэты соответствуют шаблонам ригов (GDD §11.2). Монстры одного силуэта
## делят библиотеку танцев — без этого сотня монстров недостижима.
enum Silhouette { BIPED, QUADRUPED, FLYER, BLOB, SERPENT }

## Порог дружбы по редкости. Редкость влияет на то, сколько встреч нужно,
## но НЕ на шанс — приручение гарантировано (GDD §6.3).
const FRIENDSHIP_THRESHOLD := {
	Rarity.COMMON: 100,
	Rarity.UNCOMMON: 150,
	Rarity.RARE: 200,
	Rarity.EPIC: 300,
	Rarity.LEGENDARY: 400,
}

## Кто кого бьёт. Хип-хоп нейтрален: без преимуществ и слабостей.
const BEATS := {
	Genre.ROCK: Genre.DISCO,
	Genre.DISCO: Genre.FOLK,
	Genre.FOLK: Genre.ELECTRO,
	Genre.ELECTRO: Genre.ROCK,
}

const ADVANTAGE_MULTIPLIER := 1.4
const DISADVANTAGE_MULTIPLIER := 0.7

@export var id: String = ""
@export var display_name: String = ""
@export var genre: Genre = Genre.DISCO
@export var rarity: Rarity = Rarity.COMMON
@export var silhouette: Silhouette = Silhouette.BLOB

## Что монстр просит. Показывается над ним ещё на поляне, до боя —
## игрок решает, стоит ли останавливаться (GDD §6.2).
@export var favorite_fruit_id: String = ""

@export var base_vibe: int = 100
@export var base_health: int = 100
## Урон по Настрою за идеальное попадание.
@export var base_power: float = 4.0

@export var sprite_path: String = ""

var _sprite: Texture2D = null


func friendship_threshold() -> int:
	return FRIENDSHIP_THRESHOLD.get(rarity, 100)


## Множитель урона против другого жанра.
static func genre_multiplier(attacker: Genre, defender: Genre) -> float:
	if BEATS.get(attacker, -1) == defender:
		return ADVANTAGE_MULTIPLIER
	if BEATS.get(defender, -1) == attacker:
		return DISADVANTAGE_MULTIPLIER
	return 1.0


func sprite() -> Texture2D:
	if _sprite == null and not sprite_path.is_empty():
		_sprite = load(sprite_path) as Texture2D
	return _sprite


static func genre_name(g: Genre) -> String:
	return ["Рок", "Диско", "Фолк", "Электро", "Хип-хоп"][g]


static func rarity_name(r: Rarity) -> String:
	return ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный"][r]


static func rarity_color(r: Rarity) -> Color:
	return [
		Color("ADA99F"),  # серый
		Color("578744"),  # зелёный
		Color("2E9BFF"),  # синий
		Color("B87AFF"),  # фиолетовый
		Color("FFD24D"),  # золотой
	][r]
