# 차 안·밖 탐험 게임 — 3단계 캐릭터 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 동행 캐릭터와 모은 친구(최대 3)가 3D 차 안의 걷는 면 위를 돌아다니고, 면 사이를 점프하고, 창문에 붙고, 차 신호에 반응한다.

**Architecture:** 판단은 순수 C#(`WalkGraph`, `CritterBrain`)이 하고 EditMode 테스트로 확인한다. 화면은 `CritterView`(2D 빌보드 + 그림자 + 스쿼시·스트레치)가 그린다. 등장 캐릭터는 Flutter `cast` 메시지, 반응은 `scene`·`jolt` 메시지에서 온다. 그림은 D 스프라이트가 APK 안의 Flutter 에셋에 있으면 읽고, 없으면 속성 색의 임시 얼굴을 코드로 만든다.

**Spec:** `docs/superpowers/specs/2026-11-09-car-explore-design.md` 2.3

## Global Constraints

- 캐릭터는 2D 빌보드 (설계 결정). 판정 없음, 표시·놀이 전용
- 걷는 면은 `Cabin.fbx` 의 `Walk_*` 10개 (Task 4). 이름으로 찾는다
- 등장: 동행 1 + 친구 최대 3. 친구 선택 규칙은 Flutter `eligibleFriends`·`castMessage` 한 곳
- 반응 (설계 2.3 표): 급제동·급조향 → 구른다 / 비 → 창문으로 / 터널 → 서로 붙는다 / 밤 → 존다 / 정차 → 더 돌아다닌다

## Review Focus

1. **걷는 면이 없거나 이어지지 않음** — 그래프가 끊겨도 캐릭터는 제자리 놀이를 하고 예외가 없다 → `WalkGraphTests.IsolatedSurfaceHasNoNeighbors`
2. **cast 가 비거나 바뀜** — 친구가 빠지면 그 캐릭터는 사라지고, 같은 캐릭터는 다시 만들지 않는다 → `CastDiffTests`
3. **연속 jolt** — 구르는 중 또 jolt 가 와도 상태가 꼬이지 않는다 → `CritterBrainTests.JoltWhileTumblingRestarts`
4. **면 밖으로 떨어짐** — 걷기 목표점은 항상 면 안이다 → `WalkGraphTests.RandomPointStaysInside`
5. **스프라이트 없음** — 임시 얼굴로 대체, 예외 없음 → 에뮬레이터 확인

---

### Task C1: WalkGraph (걷는 면과 이웃)
- Create `Assets/Scripts/Critters/WalkGraph.cs`, Test `Assets/Tests/EditMode/WalkGraphTests.cs`
- `public readonly struct WalkSurface { string name; Vector3 center; Vector2 size /* x,z */; }`
- `WalkGraph(IReadOnlyList<WalkSurface>, float maxJump = 0.9f, float maxRise = 0.75f)`; `IReadOnlyList<int> Neighbors(int i)`; `Vector3 RandomPoint(int i, System.Random rng)` (가장자리 8cm 안쪽); `int IndexOf(string name)`; `int Nearest(Vector3)`
- 이웃: 두 면 가장자리 사이 수평 거리 ≤ maxJump 이고 높이 차 ≤ maxRise

### Task C2: CritterBrain (상태 기계)
- Create `Assets/Scripts/Critters/CritterBrain.cs`, Test `CritterBrainTests.cs`
- 상태: `Idle, Walk, Jump, Peek, Tumble, Sleep, Huddle`
- `CritterBrain(WalkGraph g, int startSurface, int seed)`; `Tick(float dt, Mood mood)` → 현재 `State`, `Target`(Vector3), `Surface`
- `Mood { bool night; bool rain; bool tunnel; bool moving; }`; `Jolt()` 는 즉시 Tumble 1.2초
- 밤이면 Idle 대신 Sleep, 비면 Peek(창턱 면) 확률↑, 터널이면 Huddle(팔걸이 쪽), 정차면 걷기 간격 절반

### Task C3: CritterView + CritterDirector + 임시 얼굴 + 장면 연결
- `CritterView`: 빌보드 Quad, 발밑 그림자, 걷기 통통·점프 포물선·구르기 회전·잠 Zzz 크기, 카메라 향함
- `CritterDirector`: `cast` 로 등장/퇴장 (id 비교), `scene`→Mood, `jolt`→모두 Jolt
- `PlaceholderFace.Make(attribute)`: 속성 색 둥근 몸 + 눈 텍스처
- 스프라이트: `Application.streamingAssetsPath + "/flutter_assets/assets/" + sprite` 를 읽어 보고 실패하면 임시 얼굴
- `AlloBuild.CreateExploreScene` 에 Director 추가, 에디터 캡처로 확인 후 에뮬레이터

### Task C4: 부족한 부분 보완 — 창밖 최소 3D (다음 단계 전 임시)
- 장면별 하늘색·땅색, 흐르는 가로수·전봇대·건물 상자 (속도에 비례), 밤·비·터널 조명
