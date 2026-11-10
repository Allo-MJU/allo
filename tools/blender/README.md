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
