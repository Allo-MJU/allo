#!/usr/bin/env bash
# 이미지→3D 서비스(Meshy 등)에서 받은 캐릭터 모델을 Unity 프리팹으로 바꾼다.
#
#   scripts/import_characters.sh [받은 폴더]     (기본: ~/Downloads/allo_3d)
#
# 받은 폴더 구조: {종 ID}/*.fbx (+ 텍스처 png/jpg). 예) ~/Downloads/allo_3d/sea_mist/sea_mist.fbx
# 결과: unity/allo_explore/Assets/Resources/Characters/C_{종 ID}.prefab
# 모델이 있는 종은 차 안·창밖에서 3D 로, 없는 종은 D 의 2D 그림으로 나온다.
# Unity 에디터가 이 프로젝트를 열고 있으면 실패한다 (배치 모드는 한 번에 하나).
set -euo pipefail

SRC="${1:-$HOME/Downloads/allo_3d}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/unity/allo_explore"
DEST="$PROJECT/Assets/Characters/Source"
UNITY="${UNITY:-/Applications/Unity/Hub/Editor/6000.0.85f2/Unity.app/Contents/MacOS/Unity}"
IDS="road_sprout puddle_pip lamp_moth storm_lantern highway_comet sea_mist"

[ -d "$SRC" ] || { echo "받은 폴더가 없어요: $SRC" >&2; exit 1; }
mkdir -p "$DEST"
found=0
for dir in "$SRC"/*/; do
  id="$(basename "$dir")"
  case " $IDS " in *" $id "*) ;; *) echo "건너뜀: $id (종 ID 가 아니에요)"; continue ;; esac
  fbx="$(find "$dir" -iname '*.fbx' | head -1)"
  [ -n "$fbx" ] || { echo "건너뜀: $id (FBX 없음)"; continue; }
  rm -rf "$DEST/$id" "$DEST/$id.meta"
  mkdir -p "$DEST/$id"
  cp "$fbx" "$DEST/$id/$id.fbx"
  find "$dir" \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec cp {} "$DEST/$id/" \;
  echo "복사: $id ← $fbx"
  found=$((found + 1))
done
[ "$found" -gt 0 ] || { echo "가져올 모델이 없어요" >&2; exit 1; }

LOG="$(mktemp -t allo_characters).log"
"$UNITY" -batchmode -quit -projectPath "$PROJECT" -executeMethod CharacterImport.Run -logFile "$LOG" || {
  echo "Unity 실패. 로그: $LOG" >&2; grep -E "error|\[Characters\]" "$LOG" >&2 || true; exit 1; }
grep "\[Characters\]" "$LOG" || true
echo "확인 캡처: Unity -executeMethod AlloBuild.CaptureViews → docs/work-results/explore/unity_*.png"
