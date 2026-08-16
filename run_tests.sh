#!/usr/bin/env bash
# Прогон всех тестов. Падает с ненулевым кодом, если хоть один провалился.
set -u
GODOT="${GODOT:-/c/Program Files/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe}"
PROJECT="${PROJECT:-E:/v2}"

total=0; failed=0
for scene in tests/test_*.tscn; do
  name=$(basename "$scene" .tscn)
  out=$("$GODOT" --headless --path "$PROJECT" "$scene" 2>&1)
  line=$(echo "$out" | grep -E "пройдено" | tail -1)
  printf "%-20s %s\n" "$name" "${line:-НЕ ЗАПУСТИЛСЯ}"
  [ -z "$line" ] && { failed=$((failed + 1)); continue; }
  total=$((total + $(echo "$line" | grep -oE "^[0-9]+")))
  failed=$((failed + $(echo "$line" | grep -oE "[0-9]+ провалено" | grep -oE "^[0-9]+")))

  # Ошибка скрипта обрывает тест на середине — оставшиеся проверки просто
  # не выполняются, и набор рапортует «0 провалено». Так уже проехали
  # обращение к удалённому узлу и вызов метода у null: оба видны только
  # этой строкой. Молчащий обрыв считаем провалом
  errors=$(echo "$out" | grep -cE "SCRIPT ERROR")
  if [ "$errors" -gt 0 ]; then
    printf "%-20s ОБОРВАН: %s ошибок скрипта\n" "" "$errors"
    echo "$out" | grep -E "SCRIPT ERROR" -A 1 | head -6 | sed 's/^/    /'
    failed=$((failed + errors))
  fi
done

# Тесты арт-пайплайна живут в Python: ворота меряют картинки, а не сцены,
# и Godot для этого не нужен. Пропускаются, если не поставлен pytest, —
# отсутствие инструмента не должно выглядеть как провал теста.
if (cd tools/artgen && uv run --extra test python -c "import pytest" >/dev/null 2>&1); then
  line=$(cd tools/artgen && uv run --extra test pytest tests -q 2>&1 | tail -1)
  printf "%-20s %s\n" "artgen" "$line"
  total=$((total + $(echo "$line" | grep -oE "[0-9]+ passed" | grep -oE "^[0-9]+" || echo 0)))
  failed=$((failed + $(echo "$line" | grep -oE "[0-9]+ failed" | grep -oE "^[0-9]+" || echo 0)))
else
  printf "%-20s %s\n" "artgen" "пропущен: uv sync --extra test"
fi

# Тесты балансовой админки: формат записи, валидатор, бэкапы, .tres-патч.
if (cd tools/balance_admin && uv run --extra test python -c "import pytest" >/dev/null 2>&1); then
  line=$(cd tools/balance_admin && uv run --extra test pytest tests -q 2>&1 | tail -1)
  printf "%-20s %s\n" "balance_admin" "$line"
  total=$((total + $(echo "$line" | grep -oE "[0-9]+ passed" | grep -oE "^[0-9]+" || echo 0)))
  failed=$((failed + $(echo "$line" | grep -oE "[0-9]+ failed" | grep -oE "^[0-9]+" || echo 0)))
else
  printf "%-20s %s\n" "balance_admin" "пропущен: uv sync --extra test"
fi

echo
echo "ИТОГО: $total пройдено, $failed провалено"
[ "$failed" -eq 0 ]
