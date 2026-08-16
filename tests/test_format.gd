extends TestHarness

## Строки формата: спецификаторов ровно столько же, сколько аргументов.
##
## GDScript при несовпадении НЕ падает — он молча возвращает шаблон как есть.
## Игрок видит «Сначала подружись: %s», а компиляция, подъём сцены и все
## остальные тесты при этом зелёные: строка собралась, просто не та.
## Так уже проехало в живую игру, и поймать это можно только чтением кода.
##
## Тем же классом поломок был `%g`, которого в GDScript нет вовсе
## (см. CLAUDE.md): неверный спецификатор тоже оставляет шаблон.

## Спецификаторы, которые GDScript действительно понимает.
## `%g` сюда не входит намеренно — он и есть отдельный сторож ниже.
const KNOWN := "sdfxXoec"

## Каталоги, которые не читаем: там нет игрового кода.
const SKIP := ["res://.godot", "res://addons"]


func run_tests() -> void:
	var files := _all_scripts("res://")
	check(files.size() > 20, "скрипты нашлись (%d)" % files.size())
	_test_specifier_count_matches_args(files)
	_test_no_unsupported_specifiers(files)


func _all_scripts(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(root.path_join(name))
	for name in dir.get_directories():
		var sub := root.path_join(name)
		if SKIP.has(sub):
			continue
		out.append_array(_all_scripts(sub))
	return out


## Сколько спецификаторов в строке. `%%` — экранированный процент, не считаем.
func _count_specifiers(text: String) -> int:
	var count := 0
	var i := 0
	while i < text.length() - 1:
		if text[i] != "%":
			i += 1
			continue
		var j := i + 1
		if text[j] == "%":
			i += 2
			continue
		# Пропускаем флаги, ширину и точность
		while j < text.length() and "-+ #0123456789.*".contains(text[j]):
			j += 1
		if j < text.length() and KNOWN.contains(text[j]):
			count += 1
		i = j + 1
	return count


## Аргументы вызова после `%`. Массив — считаем запятые верхнего уровня,
## одиночное выражение — один аргумент. Возвращает -1, если это не формат.
func _count_arguments(source: String, from: int) -> int:
	var i := from
	while i < source.length() and (source[i] == " " or source[i] == "\t"):
		i += 1
	if i >= source.length():
		return -1
	if source[i] != "[":
		# Одиночный аргумент: `"%s" % value`. Считаем за один — распознать
		# массив в переменной статически нельзя, и гадать здесь вреднее,
		# чем пропустить
		return 1

	var depth := 0
	var args := 1
	var seen := false
	# Висячая запятая перед `]` — обычное дело в многострочных массивах,
	# и без этого флага она считалась лишним аргументом: тест краснел
	# на двадцати девяти исправных строках подряд
	var after_comma := false
	var quote := ""
	while i < source.length():
		var ch := source[i]
		if not quote.is_empty():
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				quote = ""
			after_comma = true
		elif ch == "\"" or ch == "'":
			quote = ch
			seen = true
			after_comma = true
		elif "([{".contains(ch):
			depth += 1
			if depth > 1:
				seen = true
				after_comma = true
		elif ")]}".contains(ch):
			depth -= 1
			if depth == 0:
				if not seen:
					return 0
				return args - 1 if not after_comma else args
			seen = true
			after_comma = true
		elif ch == "," and depth == 1:
			args += 1
			after_comma = false
		elif not ch.strip_edges().is_empty():
			seen = true
			after_comma = true
		i += 1
	return -1


## Найти литералы вида `"…" %`. Ищем вручную, а не регуляркой: строка может
## содержать экранированные кавычки, и `RegEx` на них спотыкается.
func _format_calls(source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < source.length():
		if source[i] == "#":
			# Комментарий до конца строки: там бывают примеры с %s
			while i < source.length() and source[i] != "\n":
				i += 1
			continue
		if source[i] != "\"":
			i += 1
			continue

		var start := i
		i += 1
		while i < source.length() and source[i] != "\"":
			if source[i] == "\\":
				i += 1
			i += 1
		if i >= source.length():
			break
		var literal := source.substr(start + 1, i - start - 1)
		i += 1

		# Оператор `%` сразу за литералом — это форматирование
		var j := i
		while j < source.length() and (source[j] == " " or source[j] == "\t"):
			j += 1
		if j < source.length() and source[j] == "%":
			out.append({
				"text": literal,
				"args_at": j + 1,
				"line": source.substr(0, start).count("\n") + 1,
			})
	return out


func _test_specifier_count_matches_args(files: PackedStringArray) -> void:
	print("Спецификаторов столько же, сколько аргументов")
	var checked := 0
	for path: String in files:
		var source := FileAccess.get_file_as_string(path)
		for call: Dictionary in _format_calls(source):
			var text: String = call["text"]
			var specs := _count_specifiers(text)
			if specs == 0:
				continue
			var args := _count_arguments(source, int(call["args_at"]))
			if args < 0:
				continue
			checked += 1
			check(specs == args,
				"%s:%d — спецификаторов %d, аргументов %d: «%s»" % [
					path.get_file(), int(call["line"]), specs, args,
					text.substr(0, 48),
				])
	check(checked > 30, "проверено вызовов форматирования: %d" % checked)


## `%g` в GDScript не поддерживается: он не падает, а оставляет шаблон.
func _test_no_unsupported_specifiers(files: PackedStringArray) -> void:
	print("Неподдерживаемых спецификаторов нет")
	for path: String in files:
		var source := FileAccess.get_file_as_string(path)
		for call: Dictionary in _format_calls(source):
			# `%%` — экранированный процент, и «%%g» это просто текст «%g».
			# Без этого тест ловил собственное сообщение об ошибке
			var text: String = String(call["text"]).replace("%%", "")
			check(not text.contains("%g"),
				"%s:%d — %%g не поддерживается GDScript: «%s»" % [
					path.get_file(), int(call["line"]), text.substr(0, 48),
				])
