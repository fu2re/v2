#!/usr/bin/env bash
# Прогон всех тестов. Падает с ненулевым кодом, если хоть один провалился.
set -u
GODOT="${GODOT:-/c/Program Files/Godot_v4.6.2-stable_win64.exe/Godot_v4.6.2-stable_win64_console.exe}"
PROJECT="${PROJECT:-E:/v2}"

total=0; failed=0
for scene in tests/test_*.tscn; do
  name=$(basename "$scene" .tscn)
  line=$("$GODOT" --headless --path "$PROJECT" "$scene" 2>&1 | grep -E "пройдено" | tail -1)
  printf "%-20s %s\n" "$name" "${line:-НЕ ЗАПУСТИЛСЯ}"
  [ -z "$line" ] && { failed=$((failed + 1)); continue; }
  total=$((total + $(echo "$line" | grep -oE "^[0-9]+")))
  failed=$((failed + $(echo "$line" | grep -oE "[0-9]+ провалено" | grep -oE "^[0-9]+")))
done

echo
echo "ИТОГО: $total пройдено, $failed провалено"
[ "$failed" -eq 0 ]
