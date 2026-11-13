#!/usr/bin/env bash
# scripts/prepare_props.sh 결과(정리된 소품 FBX)를 Unity 프리팹으로 바꾼다.
#
#   scripts/import_props.sh [정리된 폴더]     (기본: ~/Downloads/allo_3d_props)
#
# 결과: unity/allo_explore/Assets/Resources/Props/P_{ID}.prefab
# 프리팹이 있는 소품은 Unity 가 기존 도형 대신 모델을 쓴다 (Toys.Make, 차 안 인형·쿠션은 장면 빌드 때).
# Unity 에디터가 이 프로젝트를 열고 있으면 실패한다 (배치 모드는 한 번에 하나).
set -euo pipefail

SRC="${1:-$HOME/Downloads/allo_3d_props}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/unity/allo_explore"
DEST="$PROJECT/Assets/Props/Source"
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.0.85f2/Unity.app/Contents/MacOS/Unity}"
IDS="egg egg_top egg_bottom nest plush cushion blanket ball apple shell acorn fishbun"

[ -d "$SRC" ] || { echo "정리된 폴더가 없어요: $SRC" >&2; exit 1; }
mkdir -p "$DEST"
found=0
for id in $IDS; do
  dir="$SRC/$id"
  [ -f "$dir/$id.fbx" ] || continue
  rm -rf "${DEST:?}/$id" "$DEST/$id.meta"
  mkdir -p "$DEST/$id"
  cp "$dir/$id.fbx" "$DEST/$id/"
  find "$dir" \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec cp {} "$DEST/$id/" \;
  echo "복사: $id"
  found=$((found + 1))
done
[ "$found" -gt 0 ] || { echo "가져올 소품이 없어요" >&2; exit 1; }

LOG="$(mktemp -t allo_props).log"
"$UNITY" -batchmode -quit -projectPath "$PROJECT" -executeMethod PropImport.Run -logFile "$LOG" || {
  echo "Unity 실패. 로그: $LOG" >&2; grep -E "error|\[Props\]" "$LOG" >&2 || true; exit 1; }
grep "\[Props\]" "$LOG" || true
echo "장면에 반영(차 안 인형·쿠션): Unity -executeMethod AlloBuild.CreateExploreScene, 확인: AlloBuild.CaptureEgg·CaptureBlanket"
