class_name MonsterData
extends Resource

## Вид монстра. Правится в инспекторе как .tres — статы и пороги не хардкодятся,
## иначе баланс требует программиста на каждую правку.

## Стихии вместо стихий-из-учебника: пять природных характеров.
##
## Внутренние имена остались музыкальными (ROCK, DISCO...), потому что за ними
## закреплены аранжировки треков. На экране их видеть не должны: музыкальный
## жаргон ничего не говорит семилетнему. Отображаемые имена — в ELEMENT_NAMES.
enum Genre { ROCK, DISCO, FOLK, ELECTRO, HIPHOP }

const ELEMENT_NAMES := ["Камень", "Солнце", "Листва", "Искра", "Ветер"]

## Грейды монстра. Порядок = сила: чем выше, тем крепче и опаснее.
enum Rarity { COMMON, UNCOMMON, RARE, UNIQUE, EPIC, LEGENDARY }

const RARITY_NAMES := ["Обычный", "Необычный", "Редкий", "Уникальный",
	"Эпический", "Легендарный"]

## Цвета грейдов. Легендарный переливается — он один такой, и это должно
## быть видно с первого взгляда на карточку поляны.
const RARITY_COLORS := [
	Color("F0F0F0"),  # белый
	Color("57C46A"),  # зелёный
	Color("2E9BFF"),  # синий
	Color("B87AFF"),  # фиолетовый
	Color("FFD24D"),  # золотой
	Color("B8860B"),  # тёмно-золотой, переливается в интерфейсе
]

## Насколько крепче и злее монстр каждого следующего грейда.
##
## Растёт заметно, но не отвесно: легендарный обязан быть испытанием,
## а не стеной, в которую упираются навсегда.
const RARITY_VIBE_SCALE := [1.0, 1.25, 1.6, 2.0, 2.6, 3.4]
const RARITY_POWER_SCALE := [1.0, 1.15, 1.35, 1.6, 1.9, 2.3]

## Силуэты соответствуют шаблонам ригов (GDD §11.2). Монстры одного силуэта
## делят библиотеку танцев — без этого сотня монстров недостижима.
enum Silhouette { BIPED, QUADRUPED, FLYER, BLOB, SERPENT }

## Порог дружбы по редкости. Редкость влияет на то, сколько встреч нужно,
## но НЕ на шанс — приручение гарантировано (GDD §6.3).
const FRIENDSHIP_THRESHOLD := {
	Rarity.COMMON: 100,
	Rarity.UNCOMMON: 150,
	Rarity.RARE: 200,
	Rarity.UNIQUE: 250,
	Rarity.EPIC: 300,
	Rarity.LEGENDARY: 400,
}

## Кто кого бьёт. Ветер нейтрален: без преимуществ и слабостей.
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
	return ELEMENT_NAMES[g]


static func rarity_name(r: Rarity) -> String:
	return RARITY_NAMES[r]


static func rarity_color(r: Rarity) -> Color:
	return RARITY_COLORS[r]


## Множитель Настроя по грейду.
static func rarity_vibe_scale(r: Rarity) -> float:
	return RARITY_VIBE_SCALE[r]


## Множитель силы удара монстра по грейду.
static func rarity_power_scale(r: Rarity) -> float:
	return RARITY_POWER_SCALE[r]


## Легендарный переливается: единственный грейд с особой подачей.
static func rarity_shimmers(r: Rarity) -> bool:
	return r == Rarity.LEGENDARY
