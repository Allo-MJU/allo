/// 알 품기·동행 화면을 차 안 화면만 꽉 채워 보여 줄지 (2026-11-09 팀장 결정: 버튼·문구는 일단 숨김).
///
/// 끄면 예전 화면(제목·진행 막대·버튼)으로 돌아간다. 기존 흐름 테스트는 끈 상태로 돈다.
/// 화면이 꽉 차도 알 탭 = 감싸기, 알 길게 누르기 = 노래, 동행 캐릭터 탭 = 놀아주기는 된다.
/// 개발 중 예전 화면이 필요하면 `--dart-define=CLASSIC_UI=true` 로 실행한다.
bool fullscreenCabin = !const bool.fromEnvironment('CLASSIC_UI');

/// 부화 뒤 "같이 가자"를 누르면 동행 화면을 거치지 않고 바로 Unity 차 안으로 들어갈지.
/// Unity 내보내기 결과가 있는 빌드(`--dart-define=EXPLORE_UNITY=true`)에서만 켠다.
bool autoEnterExplore =
    fullscreenCabin && const bool.fromEnvironment('EXPLORE_UNITY');
