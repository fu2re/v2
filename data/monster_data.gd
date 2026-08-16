class_name MonsterData
extends Resource

## Вид монстра. Правится в инспекторе как .tres — статы и пороги не хардкодятся,
## иначе баланс требует программиста на каждую правку.

## Стихии вместо стихий-из-учебника: пять природных характеров.
##
## Внутренние имена остались музыкальными (ROCK, DISCO...), потому что за ними
## закреплены аранжировки треков. На экране их видеть не должны: музыкальный
## жаргон ничего не говорит семилетнему. Отображаемые имена — в ELEMENT_NAMES.
## Ветер — латина, а не хип-хоп: на синтезе, которым делаются треки,
## хип-хоп звучал почти пустым (разреженный бит и длинный саб), а «почти
## пустой» для ритм-игры означает «не по чему попадать». Обоснование
## живёт в `tools/chartgen/beatroot_chartgen/arrange.py`.
enum Genre { ROCK, DISCO, FOLK, ELECTRO, LATIN }

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

## Насколько крепче и злее монстр каждого следующего грейда — берётся
## из таблицы (`data/progression.json`), а не из константы в коде.
##
## Раньше числа жили здесь и разошлись с таблицей: 1.7 в коде против 2.0
## в JSON, который объявлял себя источником истины. Держать их в двух местах
## бессмысленно — расхождение обязательно вернётся.

## Порог дружбы по грейду живёт в таблице (`Balance.friendship_threshold`).
## Грейд влияет на то, сколько встреч нужно, но НЕ на шанс — приручение
## гарантировано (GDD §6.3), и у каждого грейда своя шкала (GDD §6.1).

## Кто кого бьёт. Ветер нейтрален: без преимуществ и слабостей.
const BEATS := {
	Genre.ROCK: Genre.DISCO,
	Genre.DISCO: Genre.FOLK,
	Genre.FOLK: Genre.ELECTRO,
	Genre.ELECTRO: Genre.ROCK,
}

const ADVANTAGE_MULTIPLIER := 1.4
const DISADVANTAGE_MULTIPLIER := 0.7

## Грейд НЕ здесь: он принадлежит экземпляру, а не виду (GDD §6.3) —
## любой вид может встретиться в любом грейде. Поле rarity у вида было
## легаси той эпохи, когда легендарным мог быть лишь тот, кого таким
## нарисовали.
@export var id: String = ""
@export var display_name: String = ""
@export var genre: Genre = Genre.DISCO

## Что монстр просит. Показывается над ним ещё на поляне, до боя —
## игрок решает, стоит ли останавливаться (GDD §6.2).
@export var favorite_fruit_id: String = ""

## Мелодический мотив монстра. Вместе со стихией и грейдом задаёт трек боя:
## `charts/<жанр>_<мотив>_<грейд>_<bpm>.json` (GDD §10.1.1). Один мотив звучит
## в пяти аранжировках и шести темпах, поэтому монстру достаточно назвать его.
@export var motif_id: String = ""

@export var base_vibe: int = 100
@export var base_health: int = 100
## Урон по Настрою за идеальное попадание.
@export var base_power: float = 4.0

@export var sprite_path: String = ""

var _sprite: Texture2D = null


## Порог дружбы для конкретного грейда ЭТОЙ встречи.
##
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


## Каталог спрайтов по грейдам: `art/monster/<вид>_<грейд>.png`.
const SPRITE_DIR := "res://art/monster"

## Разобранные пути, общие на все экземпляры вида: id -> {грейд -> путь}.
## Скан по файловой системе на каждую отрисовку обошёлся бы в кадры.
static var _grade_sprites: Dictionary = {}


## Спрайт для конкретного грейда.
##
## Пока грейд не нарисован, показывается МАКСИМАЛЬНЫЙ доступный спрайт вида:
## сначала ищем точное совпадение, потом ближайший меньший грейд, потом любой
## имеющийся. Игра остаётся играбельной на неполном арте, а картинка сама
## становится точнее по мере рисования — без единой правки кода.
func sprite_for_grade(grade: int) -> Texture2D:
	var available := _sprites_for_species(id)

	if available.has(grade):
		return load(available[grade]) as Texture2D

	# Ближайший снизу: легендарный, которого ещё не нарисовали, выглядит
	# как самый старший из готовых, а не как пустое место
	for lower in range(grade - 1, -1, -1):
		if available.has(lower):
			return load(available[lower]) as Texture2D

	var grades: Array = available.keys()
	if not grades.is_empty():
		grades.sort()
		return load(available[grades[grades.size() - 1]]) as Texture2D

	return sprite()


static func _sprites_for_species(species_id: String) -> Dictionary:
	if _grade_sprites.has(species_id):
		return _grade_sprites[species_id]

	var found: Dictionary = {}
	for grade in RARITY_NAMES.size():
		var key := Balance.grade_key(grade)
		var path := "%s/%s_%s.png" % [SPRITE_DIR, species_id, key]
		# ResourceLoader, а не FileAccess: в экспортированной сборке текстуры
		# лежат как .import/.remap, и проверка по имени файла соврала бы
		if ResourceLoader.exists(path):
			found[grade] = path
	_grade_sprites[species_id] = found
	return found


## Сбросить кеш путей. Нужен тестам и редактору: арт добавляется на ходу.
static func forget_sprite_paths() -> void:
	_grade_sprites.clear()


static func genre_name(g: Genre) -> String:
	return ELEMENT_NAMES[g]


static func rarity_name(r: Rarity) -> String:
	return RARITY_NAMES[r]


static func rarity_color(r: Rarity) -> Color:
	return RARITY_COLORS[r]
