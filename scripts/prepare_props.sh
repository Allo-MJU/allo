#!/usr/bin/env bash
# 이미지→3D 서비스(Tripo)에서 받은 소품 zip 을 Blender 로 정리해 Unity 가져오기 폴더에 둔다.
#
#   scripts/prepare_props.sh [zip 폴더] [결과 폴더]     (기본: ~/Downloads, ~/Downloads/allo_3d_props)
#   ONLY="cushion ball" scripts/prepare_props.sh         (일부만 다시)
#
# zip 이름이 소품 ID 다: egg.zip nest.zip plush.zip … (아래 표). 없는 것은 건너뛴다.
# 결과: {결과 폴더}/{ID}/{ID}.fbx + 색 텍스처 PNG. 알은 egg_top·egg_bottom 도 만든다 (tools/blender/egg.py).
# 그다음 scripts/import_props.sh 로 Unity 프리팹(Resources/Props/P_{ID})을 만든다.
set -euo pipefail

SRC="${1:-$HOME/Downloads}"
OUT="${2:-$HOME/Downloads/allo_3d_props}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLENDER="${BLENDER:-blender}"

# ID | 실제 크기 X,Y,Z m (가로, 앞뒤, 키 / 0 = 비율 유지) | 삼각형 | 텍스처 px | 돌리기(도, 앞이 -Y 가 되게)
# 크기는 Unity 의 기존 도형(Toys.Make·Cabin.glb)에 맞춘다. 둥지는 Unity 가 1.3 배로 키운다
PROPS="
egg      0,0,0.125        3000 1024 0
nest     0.17,0.17,0.06   3000 1024 0
plush    0,0,0.30         3000 1024 0
cushion  0.30,0,0         3000 1024 0
blanket  0.34,0.27,0.10   3000 1024 0
ball     0,0,0.08         1500 512  0
apple    0,0,0.075        1500 512  0
shell    0.075,0,0        1500 512  0
acorn    0,0,0.08         1500 512  0
fishbun  0.11,0,0         1500 512  0
"

WORK="$(mktemp -d -t allo_props)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
echo "$PROPS" | while read -r id size tris tex yaw; do
  [ -n "$id" ] || continue
  [ -z "${ONLY:-}" ] || case " $ONLY " in *" $id "*) ;; *) continue ;; esac
  zip="$SRC/$id.zip"
  [ -f "$zip" ] || { echo "건너뜀: $id ($zip 없음)"; continue; }
  mkdir -p "$WORK/$id"
  unzip -q -o "$zip" -d "$WORK/$id"
  fbx="$(find "$WORK/$id" -iname '*.fbx' | head -1)"
  [ -n "$fbx" ] || { echo "건너뜀: $id (zip 에 FBX 없음)"; continue; }
  rm -rf "${OUT:?}/$id"
  "$BLENDER" -b -P "$ROOT/tools/blender/character.py" -- --in "$fbx" --out "$OUT/$id/$id.fbx" \
    --size "$size" --max-tris "$tris" --tex "$tex" --yaw "$yaw" 2>&1 | grep -E "\[character\]|Error|Traceback" | sed "s/^/$id: /"
  if [ "$id" = egg ]; then
    rm -rf "$OUT/egg_top" "$OUT/egg_bottom"
    "$BLENDER" -b -P "$ROOT/tools/blender/egg.py" -- --in "$OUT/egg/egg.fbx" --out "$OUT" 2>&1 \
      | grep -E "\[egg\]|Error|Traceback" | sed "s/^/egg: /"
  fi
done
echo "다음: scripts/import_props.sh $OUT"
