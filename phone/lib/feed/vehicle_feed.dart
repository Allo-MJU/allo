import 'package:allo_core/allo_core.dart';

/// 차량 신호 소스 추상화. Firebase 든 가짜든 화면은 이것만 본다.
/// 이 추상화 덕에 A 의 검증 결과와 무관하게 B 는 끝까지 개발하고, PT 에서 실기 연동이 불안정해도 시연이 된다.
abstract class VehicleFeed {
  /// 세션에 붙는다. 성공하면 meta.paired 를 true 로 바꾼다 (Firebase 구현).
  Future<void> pair(String sessionId, {String? pairCode});

  Stream<VehicleState> watch();

  /// 현재 세션의 마지막 저장값을 읽는다. 새 주행 틱을 만들지 않는다.
  Future<VehicleState?> readLatestVehicle();

  /// 폰이 계산한 게임 상태를 차 화면용으로 올린다. 가짜 구현은 무시한다.
  Future<void> publishGame(GameState state);

  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}});

  /// 차가 보낸 일회성 이벤트 (destinationSuggest, sessionEnd)
  Stream<Map<String, Object?>> events();

  Future<void> dispose();
}
