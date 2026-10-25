#!/bin/bash
# Pi side: what the guard and the agy helper did since a time, to read after every test.
#   ~/deepidle/agy-report.sh "2026-10-25 11:00:00"
D=$HOME/deepidle; S=${1:-1970-01-01 00:00:00}
echo "== guard.log since $S"; awk -v s="$S" '$1" "$2 >= s' "$D/guard.log" 2>/dev/null
echo "== agy-ready.log since $S"; awk -v s="$S" '$1" "$2 >= s' "$D/rescue/agy-ready.log" 2>/dev/null
echo "== rescue reports since $S"; find "$D/rescue" -name '2*.md' -newermt "$S" 2>/dev/null | while read -r f; do echo "-- $f"; cat "$f"; done
echo "== agy-last.txt (tail 30)"; tail -30 "$D/rescue/agy-last.txt" 2>/dev/null
