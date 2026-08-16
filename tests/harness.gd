class_name TestHarness
extends Node

## Общий счётчик проверок для тестовых сцен.
##
## До него `check` и `check_eq` были скопированы в каждый из четырнадцати
## тестов, и любая правка формата вывода требовала четырнадцати правок.
## Формат важен не косметически: `run_tests.sh` ищет в выводе строку
## со словом «пройдено» и суммирует числа из неё регуляркой.
##
## Наследники переопределяют `run_tests()` и ничего не знают про подсчёт.

var _passed := 0
var _failed := 0


func _ready() -> void:
	# Тесты гоняют настоящие автозагрузчики, и без этого прогон затирал бы
	# сохранение игрока
	SaveManager.enter_test_mode()
	# `await` обязателен: часть тестов поднимает сцены и ждёт кадры.
	# Без него отчёт печатался бы раньше, чем такой тест успел упасть
	await run_tests()
	finish()


## Переопределяется наследником.
func run_tests() -> void:
	pass


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  ПРОВАЛ: %s" % description)


func check_eq(actual: Variant, expected: Variant, description: String) -> void:
	check(actual == expected, "%s (получено %s, ожидалось %s)"
		% [description, actual, expected])


## Сравнение дробных с допуском: точное равенство float в тестах баланса
## ломается на первой же смене формулы, ничего не сообщая по сути.
func check_close(actual: float, expected: float, description: String,
		epsilon: float = 0.001) -> void:
	check(absf(actual - expected) <= epsilon, "%s (получено %.4f, ожидалось %.4f)"
		% [description, actual, expected])


## Справочная строка: не проверка, а заметка в отчёте. Нужна там, где
## неполнота данных ожидаема и не должна выглядеть провалом.
func note(text: String) -> void:
	print("  · %s" % text)


func finish() -> void:
	print("\n%d пройдено, %d провалено" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
