# Blender 모델 스크립트

사람이 Blender 를 열지 않고 스크립트로 3D 모델을 만든다. 색은 `palette.py` 한 곳에서 바꾼다.

```bash
# 차 내부: glb 내보내기 + 미리보기 렌더 4장
blender -b -P tools/blender/cabin.py -- --out unity/allo_explore/Assets/Models/Cabin.glb --preview docs/work-results/explore/
# 이름 검사만 (Unity 가 이름으로 찾는 물체 24개 + 걷는 면 10개)
blender -b -P tools/blender/cabin.py -- --check
```

- 좌표: 미터, 원점은 뒷좌석 가운데 바닥, +Z 위, -Y 앞 (`kit.py` 머리말)
- `Walk_*` 판: 캐릭터가 서고 걷는 면. Unity 에서 렌더는 끄고 위치·크기만 쓴다

## 캐릭터 모델 정리 (`character.py`)

이미지→3D 서비스(Tripo 등)에서 받은 FBX 를 Unity 에 넣기 전에 정리한다. 부품은 합치지 않는다.

```bash
# 정리 + 미리보기 3장(정면·옆·비스듬히)
blender -b -P tools/blender/character.py -- --in road_sprout.fbx \
    --out ~/Downloads/allo_3d/road_sprout/road_sprout.fbx --preview /tmp/char_road_sprout.png
# 검사만 (부품 수·삼각형·크기)
blender -b -P tools/blender/character.py -- --in road_sprout.fbx --check
# 그다음 Unity 프리팹으로
scripts/import_characters.sh
```

- 발바닥 가운데가 원점, 앞은 -Y (Unity 에서 +Z). 앞이 다르면 `--yaw`
- 부품 경계 틈: 열린 가장자리 버텍스를 가장 가까운 이웃 부품 표면 0.5mm 안으로 옮긴다 (`--gap`, 기본 15mm 까지)
- 노멀맵은 버린다(`Allo/Toon` 이 안 씀). 색 텍스처는 `--tex`(기본 1024px)로 줄여 FBX 옆에 PNG 로 둔다
- **색 텍스처가 없으면** 경고하고 `--fallback-color` 단색으로 내보낸다. Tripo 의 `*_normal.jpg` 만 있는 FBX 가 그렇다
- 삼각형을 줄이려면 `--max-tris 10000` (부품마다 같은 비율로 데시메이트)
- 실제 크기로 맞추려면 `--size X,Y,Z` (m, 가로·앞뒤·키, 0 은 비율 유지), 앞이 -Y 가 아니면 `--yaw`

## 소품 모델 정리 (`scripts/prepare_props.sh`, `egg.py`)

Tripo 에서 받은 소품 zip(`~/Downloads/{ID}.zip`)을 한 번에 정리하고 Unity 프리팹으로 만든다.

```bash
scripts/prepare_props.sh                 # → ~/Downloads/allo_3d_props/{ID}/{ID}.fbx (+ PNG)
ONLY="cushion" scripts/prepare_props.sh  # 일부만 다시
scripts/import_props.sh                  # → unity/allo_explore/Assets/Resources/Props/P_{ID}.prefab
```

- ID·실제 크기·삼각형 수·텍스처 크기·돌리기는 `prepare_props.sh` 의 표 한 곳에서 정한다. 크기는 Unity 의 기존 도형에 맞췄다
- Tripo HD 모델은 하나에 삼각형 약 200만 개라 소품마다 1,500~3,000 개로 줄인다. metallic·roughness·노멀 텍스처는 버린다
- 알은 `egg.py` 가 지그재그 금(키의 70%, 9갈래)을 따라 윗껍데기(`egg_top`, 원점 = 금 높이)와 아래 껍데기(`egg_bottom`)로 자른다. 잘린 면은 크림색 속껍질
- 프리팹이 있으면 Unity `Toys.Make` 가 도형 대신 모델을 쓰고, 장면 빌드(`AlloBuild.CreateExploreScene`)가 차 안 옆자리 인형·쿠션을 모델로 바꾼다
