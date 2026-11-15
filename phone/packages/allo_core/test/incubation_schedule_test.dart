import 'package:test/test.dart';
import 'package:allo_core/src/incubation_schedule.dart';

void main() {
  test('확정 예시의 각 품기와 동행 시간', () {
    final cases = <int, List<int>>{
      11: [5, 6],
      80: [40, 40],
      81: [40, 41],
      90: [40, 50],
      150: [40, 110],
      151: [40, 111],
      300: [40, 260],
    };
    for (final entry in cases.entries) {
      final rounds = incubationSchedule(entry.key * 60);
      final durations = [
        for (final round in rounds) ...[
          (round.hatchEndSec - round.eggGrantedSec) ~/ 60,
          (round.companionEndSec - round.hatchEndSec) ~/ 60,
        ],
      ];
      expect(durations, entry.value, reason: '${entry.key}분');
      expect(rounds.last.companionEndSec, entry.key * 60);
      expect(rounds.map((r) => r.grantsNextEgg),
          [...List.filled(rounds.length - 1, true), false]);
    }
    expect(incubationSchedule(300 * 60).map((r) => r.eggGrantedSec),
        [0]);
  });

  test('80분 경계 전후에서 초를 보존한다', () {
    final before = incubationRound(4799);
    expect([before.hatchEndSec, before.companionEndSec, before.grantsNextEgg],
        [39 * 60, 4799, false]);
    final exact = incubationRound(4800);
    expect([exact.hatchEndSec, exact.companionEndSec, exact.grantsNextEgg],
        [40 * 60, 4800, false]);
    final after = incubationSchedule(4801);
    expect(
        after.map((r) => [
              r.eggGrantedSec,
              r.hatchEndSec,
              r.companionEndSec,
              r.grantsNextEgg
            ]),
        [
          [0, 2400, 4801, false],
        ]);
  });

  test('초 단위 ETA의 절반을 분 단위로 내린다', () {
    final round = incubationRound(11 * 60 + 59);
    expect(round.remainingEtaSec, 719);
    expect(round.hatchEndSec, 5 * 60);
    expect(round.companionEndSec, 719);
  });

  test('2분 미만은 지원하지 않는다', () {
    for (final seconds in [-1, 0, 119]) {
      expect(() => incubationRound(seconds), throwsRangeError);
      expect(() => incubationSchedule(seconds), throwsRangeError);
    }
    expect(incubationRound(120).hatchEndSec, 60);
  });

  test('반복 일정은 수정할 수 없다', () {
    expect(() => incubationSchedule(660).clear(), throwsUnsupportedError);
  });
}
