import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

VehicleState v({required int ts, double distanceM = 0, int? etaSec}) => VehicleState(
      ts: ts, gear: 'D', speedKph: 60, distanceM: distanceM, harshBrake: 0, harshSteer: 0,
      wiperLevel: 0, headlightOn: false, seatRow2: true, etaSec: etaSec, envTags: const [], capabilities: const [],
    );

void main() {
  test('ETA 60분 → 30분 시점 부화', () {
    final t = HatchTimer(eggTier: EggTier.large);
    t.update(v(ts: 0, etaSec: 3600));
    expect(t.usesEta, isTrue);
    expect(t.hatchAtSec, 1800);
    expect(t.update(v(ts: 15 * 60 * 1000, etaSec: 2700)), closeTo(0.5, 1e-9));
    expect(t.shouldHatch(t.update(v(ts: 30 * 60 * 1000, etaSec: 1800))), isTrue);
  });

  test('ETA null + small 알 → 5km 시점 부화', () {
    final t = HatchTimer(eggTier: EggTier.small);
    expect(t.update(v(ts: 0)), 0);
    expect(t.hatchAtM, 5000);
    expect(t.update(v(ts: 1000, distanceM: 2500)), closeTo(0.5, 1e-9));
    expect(t.shouldHatch(t.update(v(ts: 2000, distanceM: 5000))), isTrue);
  });

  test('3km 에서 세션 종료 → 다음 주행 2km 에서 부화', () {
    final first = HatchTimer(eggTier: EggTier.small);
    first.update(v(ts: 0));
    final p = first.update(v(ts: 1000, distanceM: 3000));
    expect(first.shouldHatch(p), isFalse);
    final carried = first.carryOver(hatched: false);
    expect(carried, 3000);

    final second = HatchTimer(eggTier: EggTier.small, carriedM: carried);
    second.update(v(ts: 0));
    expect(second.shouldHatch(second.update(v(ts: 1000, distanceM: 1999))), isFalse);
    expect(second.shouldHatch(second.update(v(ts: 2000, distanceM: 2000))), isTrue);
  });

  test('주행 중 ETA 가 null → 값으로 바뀌면 ETA 모드로 전환된다', () {
    final t = HatchTimer(eggTier: EggTier.mid);
    t.update(v(ts: 0));
    t.update(v(ts: 60000, distanceM: 1000)); // 거리 진행 4%
    final p = t.update(v(ts: 61000, distanceM: 1010, etaSec: 1200));
    expect(t.usesEta, isTrue);
    expect(t.hatchAtSec, 600);
    expect(p, closeTo(0, 1e-9)); // 전환 직후 0 에서 다시 시작
    expect(t.shouldHatch(t.update(v(ts: 61000 + 600000, distanceM: 20000, etaSec: 600))), isTrue);
  });

  test('거리 진행이 이미 절반을 넘었으면 늦게 들어온 ETA 를 무시한다', () {
    final t = HatchTimer(eggTier: EggTier.small);
    t.update(v(ts: 0));
    t.update(v(ts: 1000, distanceM: 3000)); // 60%
    t.update(v(ts: 2000, distanceM: 3100, etaSec: 3600));
    expect(t.usesEta, isFalse);
  });
}
