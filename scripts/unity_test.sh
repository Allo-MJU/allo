#!/usr/bin/env bash
# Unity EditMode 테스트를 명령줄로 돌린다. 결과: Passed/Failed 와 실패한 테스트 이름
set -uo pipefail
cd "$(dirname "$0")/.."
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.0.85f2/Unity.app/Contents/MacOS/Unity}"
OUT="${TMPDIR:-/tmp}/allo_unity_editmode.xml"
LOG="${TMPDIR:-/tmp}/allo_unity_test.log"
rm -f "$OUT"
"$UNITY" -batchmode -projectPath "$PWD/unity/allo_explore" -runTests -testPlatform EditMode \
  -testResults "$OUT" -logFile "$LOG"
if [ ! -f "$OUT" ]; then echo "NO RESULTS (compile error?)"; grep -E "error CS|Error" "$LOG" | head -20; exit 1; fi
grep -o 'test-run [^>]*' "$OUT" | grep -oE '(result|total|passed|failed)="[^"]*"' | tr '\n' ' '; echo
grep -oE 'name="[^"]*"[^>]*result="Failed"' "$OUT" | head
grep -q 'result="Passed"' <(grep -o 'test-run [^>]*' "$OUT")
