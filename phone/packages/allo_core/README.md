# allo_core

게임 로직. Flutter 없이 `dart test` 로 돌아간다. C 파트의 작업 공간.

```bash
dart pub get
dart test
```

| 파일 | 역할 |
| --- | --- |
| `models.dart` | VehicleState / GameState / Species / DexEntry. `docs/schema.md` 와 1:1 |
| `rarity_engine.dart` | 주행 품질 → tier, 환경 태그 → attribute |
| `hatch_timer.dart` | ETA 50% 또는 거리 50%. 이어하기 |
| `species_table.dart` | `data/species.json` 로드, 판정 결과 → 종 선택 |

임계값(tier 경계, 케어 상쇄 비율)은 `RarityEngine` 생성자 기본값에 있다. 바꾸면 `docs/schema.md` 비고에도 적는다.
