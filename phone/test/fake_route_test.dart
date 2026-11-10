import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/explore/explore_messages.dart';
import 'package:allo_phone/feed/fake_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = FakeScenario.sceneTour;

  test('출발하면 가까운 회전 3개를 남은 거리로 준다', () {
    expect(s.turnsAt(0), const [Turn('right', 220), Turn('left', 560), Turn('uturn', 900)]);
  });

  test('지난 회전은 빠지고 다음 바퀴 회전이 이어진다', () {
    expect(s.turnsAt(1400), const [Turn('left', 100), Turn('right', 620), Turn('left', 960)]);
  });

  test('가짜 차는 교차로 앞에서 서서히 줄이고 지나면 서서히 올린다', () {
    expect(s.speedAt(0), 70); // 교차로가 멀면 원래 속도
    expect(s.speedAt(220), closeTo(20, 0.01));
    expect(s.speedAt(180), greaterThan(s.speedAt(200)));
    expect(s.speedAt(240), greaterThan(20));
    expect(FakeScenario.rainyHighway.speedAt(100), 90);
  });

  test('경로가 없는 시나리오는 빈 목록', () {
    expect(FakeScenario.rainyHighway.turnsAt(500), isEmpty);
  });

  test('route 메시지', () {
    expect(routeMessage(const [Turn('left', 30)]), '{"v":1,"type":"route","turns":[{"type":"left","inM":30}],"heading":-1.0}');
    expect(routeMessage(const [], headingDeg: 87.54), '{"v":1,"type":"route","turns":[],"heading":87.5}');
  });

  test('가짜 진행 방향은 지난 회전 각도를 더한다', () {
    expect(s.headingAt(0), closeTo(0, 0.01));
    // 우회전(220m)을 지나면 90도 언저리 (굽은 길 ±12도)
    expect(s.headingAt(300)!, inInclusiveRange(78, 102));
    // 좌회전(560m)을 지나면 다시 0도 언저리
    final h = s.headingAt(600)!;
    expect(h < 12.1 || h > 347.9, isTrue);
    expect(FakeScenario.rainyHighway.headingAt(100), isNull);
  });
}
