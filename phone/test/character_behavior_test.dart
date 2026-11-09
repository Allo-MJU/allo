import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/character/character_behavior.dart';
import 'package:flutter_test/flutter_test.dart';

VehicleState sample(int ts,
        {String gear = 'D', double speed = 50, int brake = 0, int steer = 0}) =>
    VehicleState.fromJson({
      'ts': ts,
      'gear': gear,
      'speedKph': speed,
      'harshBrake': brake,
      'harshSteer': steer,
    });

void main() {
  test('최초 샘플 누적 횟수는 과거 사건을 재생하지 않는다', () {
    final b = CharacterBehavior();
    b.observe(sample(10, brake: 7, steer: 9), 0);
    expect(b.pose, CharacterPose.move);
    expect(b.event, isNull);
    b.observe(sample(11, brake: 8, steer: 9), 100);
    expect(b.event, CharacterEvent.brake);
    expect(b.pose, CharacterPose.surprised);
    expect(b.nextDeadlineMs, 1600);
  });

  test('중복·역순 신호는 카운터와 반응을 되감지 않는다', () {
    final b = CharacterBehavior()..observe(sample(10), 0);
    final revision = b.revision;
    b.observe(sample(10, brake: 3), 100);
    b.observe(sample(9, steer: 3), 200);
    expect(b.revision, revision);
    expect(b.event, isNull);
    b.observe(sample(11, brake: 1), 300);
    expect(b.event, CharacterEvent.brake);
  });

  test('카운터 감소는 전체 기준을 새로 잡고 놀람을 만들지 않는다', () {
    final b = CharacterBehavior()..observe(sample(10, brake: 5, steer: 4), 0);
    b.observe(sample(11, brake: 0, steer: 5), 100);
    expect(b.event, isNull);
    b.observe(sample(12, brake: 0, steer: 6), 200);
    expect(b.event, CharacterEvent.steer);
  });

  test('출발·정차는 속도 히스테리시스와 P 신호를 따른다', () {
    final b = CharacterBehavior()..observe(sample(1, gear: 'P'), 0);
    expect(b.pose, CharacterPose.idle);
    b.observe(sample(2, speed: 2), 100);
    expect(b.event, isNull);
    b.observe(sample(3, speed: 3), 200);
    expect(b.event, CharacterEvent.depart);
    b.advance(1100);
    b.observe(sample(4, speed: 1), 1200);
    expect(b.pose, CharacterPose.move);
    b.observe(sample(5, speed: .5), 1300);
    expect(b.event, CharacterEvent.stop);
    b.advance(2200);
    expect(b.pose, CharacterPose.idle);
    b.observe(sample(6, speed: 5), 2300);
    b.observe(sample(7, gear: 'P', speed: 20), 3300);
    expect(b.event, CharacterEvent.stop);
  });

  test('정차 8초 뒤 휴식하며 사용자 반응이 끝나면 휴식으로 돌아간다', () {
    final b = CharacterBehavior()..observe(sample(1, speed: 0), 100);
    expect(b.nextDeadlineMs, 8100);
    b.advance(8099);
    expect(b.pose, CharacterPose.idle);
    b.advance(8100);
    expect(b.pose, CharacterPose.sleep);
    expect(b.nextDeadlineMs, isNull);
    b.interact(CharacterEvent.tap, 8200);
    expect(b.pose, CharacterPose.happy);
    b.advance(9100);
    expect(b.pose, CharacterPose.sleep);
  });

  test('급제동이 급조향보다 우선하고 낮은 입력은 큐에 남지 않는다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.interact(CharacterEvent.play, 100);
    b.observe(sample(2, brake: 1, steer: 1), 200);
    expect(b.event, CharacterEvent.brake);
    expect(b.interact(CharacterEvent.tap, 300), isFalse);
    b.advance(1700);
    expect(b.event, isNull);
    expect(b.pose, CharacterPose.move);
  });

  test('동일 급변은 지속시간을 연장하지 않고 기준 카운터는 소비한다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.observe(sample(2, brake: 1), 100);
    b.observe(sample(3, brake: 2), 1000);
    expect(b.nextDeadlineMs, 1600);
    b.advance(1600);
    b.observe(sample(4, brake: 2), 1700);
    expect(b.event, isNull);
    b.observe(sample(5, brake: 3), 1800);
    expect(b.event, CharacterEvent.brake);
  });

  test('급조향 중 급제동은 메시지만 우선하고 기존 만료를 보존한다', () {
    final b = CharacterBehavior();
    b.interact(CharacterEvent.steer, 100);
    b.interact(CharacterEvent.brake, 500);
    expect(b.event, CharacterEvent.brake);
    expect(b.nextDeadlineMs, 1600);
    expect(b.interact(CharacterEvent.steer, 600), isFalse);
  });

  test('탭 재입력은 400ms를 기다리며 거부된 입력은 연장하지 않는다', () {
    final b = CharacterBehavior();
    expect(b.interact(CharacterEvent.tap, 0), isTrue);
    final revision = b.revision;
    expect(b.interact(CharacterEvent.tap, 399), isFalse);
    expect(b.revision, revision);
    expect(b.nextDeadlineMs, 900);
    expect(b.interact(CharacterEvent.tap, 400), isTrue);
    expect(b.revision, greaterThan(revision));
    expect(b.nextDeadlineMs, 1300);
  });

  test('드래그는 만료되지 않고 놓으면 반응 후 기본 상태로 돌아간다', () {
    final b = CharacterBehavior();
    expect(b.interact(CharacterEvent.dragStart, 0), isTrue);
    b.advance(5000);
    expect(b.event, CharacterEvent.dragStart);
    expect(b.nextDeadlineMs, isNull);
    expect(b.interact(CharacterEvent.feed, 5000), isFalse);
    expect(b.interact(CharacterEvent.dragEnd, 5100), isTrue);
    expect(b.nextDeadlineMs, 5700);
    b.advance(5700);
    expect(b.pose, CharacterPose.idle);
    expect(b.interact(CharacterEvent.dragEnd, 6000), isFalse);
  });

  test('차량 급변이 드래그를 중단하면 뒤늦은 놓기를 무시한다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.interact(CharacterEvent.dragStart, 100);
    b.observe(sample(2, steer: 1), 200);
    expect(b.event, CharacterEvent.steer);
    expect(b.interact(CharacterEvent.dragEnd, 300), isFalse);
    expect(b.interact(CharacterEvent.dragStart, 500), isFalse);
    b.advance(1700);
    expect(b.pose, CharacterPose.move);
  });

  test('빠른 연속 드래그의 놓기는 입력 제한으로 막지 않는다', () {
    final b = CharacterBehavior();
    b.interact(CharacterEvent.dragStart, 0);
    b.interact(CharacterEvent.dragEnd, 390);
    expect(b.interact(CharacterEvent.dragStart, 400), isTrue);
    expect(b.interact(CharacterEvent.dragEnd, 410), isTrue);
    b.advance(1010);
    expect(b.event, isNull);
    expect(b.pose, CharacterPose.idle);
  });

  test('사건 만료와 휴식 중 빠른 시각을 다음 기한으로 알린다', () {
    final b = CharacterBehavior()..observe(sample(1, speed: 0), 0);
    b.interact(CharacterEvent.feed, 7500);
    expect(b.nextDeadlineMs, 8000);
    b.advance(8000);
    expect(b.pose, CharacterPose.happy);
    expect(b.nextDeadlineMs, 8700);
    b.advance(8700);
    expect(b.pose, CharacterPose.sleep);
    expect(b.nextDeadlineMs, isNull);
  });

  test('신호 없음은 idle로 돌아가며 재수신 누적값은 기준만 잡는다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.observe(sample(2, brake: 1), 100);
    b.observe(null, 200);
    expect(b.pose, CharacterPose.idle);
    expect(b.event, isNull);
    expect(b.nextDeadlineMs, isNull);
    b.observe(sample(3, brake: 20), 500);
    expect(b.pose, CharacterPose.move);
    expect(b.event, isNull);
  });

  test('reset은 회차·세션 기준과 이벤트·입력제한을 모두 정리한다', () {
    final b = CharacterBehavior()..observe(sample(100, brake: 5), 0);
    b.interact(CharacterEvent.tap, 100);
    final revision = b.revision;
    b.reset();
    expect(b.revision, greaterThan(revision));
    expect(b.pose, CharacterPose.idle);
    expect(b.event, isNull);
    expect(b.nextDeadlineMs, isNull);
    expect(b.interact(CharacterEvent.tap, 101), isTrue);
    b.reset();
    b.observe(sample(1, brake: 20), 0);
    expect(b.event, isNull);
  });

  test('반응 대사는 50자 이내이고 기본 상태에는 대사가 없다', () {
    final b = CharacterBehavior();
    expect(b.message, isNull);
    for (final e in CharacterEvent.values) {
      b.reset();
      if (e == CharacterEvent.dragEnd) b.interact(CharacterEvent.dragStart, 0);
      expect(b.interact(e, 1000), isTrue);
      expect(b.message!.length, lessThanOrEqualTo(50));
    }
  });

  test('비 시작은 창문에 붙고 2400ms 뒤 기본 위치로 돌아온다', () {
    for (final rainy in [
      sample(2).copyWith(envTags: ['rain']),
      sample(2).copyWith(wiperLevel: 1),
    ]) {
      final b = CharacterBehavior()..observe(sample(1), 0);
      b.observe(rainy, 100);
      expect(b.event, CharacterEvent.windowCling);
      expect(b.attachment, CharacterAttachment.window);
      expect(b.pose, CharacterPose.happy);
      expect(b.message, '창문에 붙어서 구경할래!');
      expect(b.nextDeadlineMs, 2500);
      b.advance(2500);
      expect(b.pose, CharacterPose.move);
      expect(b.attachment, CharacterAttachment.none);
    }
  });

  test('첫 환경 샘플과 역순·중복·카운터 초기화는 풍경 사건을 재생하지 않는다', () {
    final b = CharacterBehavior()
      ..observe(sample(10, brake: 5).copyWith(envTags: ['coast', 'rain']), 0);
    expect(b.event, isNull);
    b.observe(sample(10, brake: 5).copyWith(envTags: ['mountain']), 100);
    b.observe(sample(9, brake: 5).copyWith(envTags: ['mountain']), 200);
    b.observe(sample(11, brake: 5).copyWith(envTags: ['coast', 'rain']), 300);
    expect(b.event, isNull);
    b.observe(sample(12).copyWith(envTags: ['mountain']), 400);
    b.observe(sample(13).copyWith(envTags: ['mountain']), 500);
    expect(b.event, isNull);
    b.observe(sample(14).copyWith(envTags: ['coast']), 600);
    expect(b.event, CharacterEvent.windowCling);
  });

  test('풍경과 날씨는 8초 제한을 공유하고 제한 중 사건도 소비한다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.observe(sample(2).copyWith(envTags: ['coast']), 100);
    b.observe(sample(3).copyWith(envTags: ['mountain', 'rain']), 1000);
    expect(b.nextDeadlineMs, 2500);
    b.advance(8100);
    b.observe(sample(4).copyWith(envTags: ['mountain', 'rain']), 8100);
    expect(b.event, isNull);
    b.observe(sample(5).copyWith(envTags: ['coast', 'rain']), 8200);
    expect(b.event, CharacterEvent.windowCling);
  });

  test('비의 강도 변화와 익숙한 풍경은 반복 반응하지 않는다', () {
    final b = CharacterBehavior()
      ..observe(sample(1).copyWith(envTags: ['mountain', 'rain']), 0);
    b.observe(
        sample(2).copyWith(envTags: ['mountain', 'rain'], wiperLevel: 3), 9000);
    expect(b.event, isNull);
    b.observe(sample(3).copyWith(envTags: ['city']), 10000);
    expect(b.event, isNull);
    b.observe(sample(4).copyWith(envTags: ['mountain']), 11000);
    expect(b.event, CharacterEvent.windowCling);
  });

  test('급변은 창문 사건보다 우선하며 거부된 풍경을 나중에 재생하지 않는다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.observe(sample(2, brake: 1).copyWith(envTags: ['coast', 'rain']), 100);
    expect(b.event, CharacterEvent.brake);
    expect(b.attachment, CharacterAttachment.seat);
    b.advance(1600);
    b.observe(sample(3, brake: 1).copyWith(envTags: ['coast', 'rain']), 2000);
    expect(b.event, isNull);
    b.interact(CharacterEvent.steer, 2100);
    expect(b.attachment, CharacterAttachment.seat);
  });

  test('터치와 드래그는 창문 반응을 중단하며 드래그 중 풍경은 소비한다', () {
    for (final input in [CharacterEvent.tap, CharacterEvent.dragStart]) {
      final b = CharacterBehavior()..observe(sample(1), 0);
      b.observe(sample(2).copyWith(envTags: ['coast']), 100);
      expect(b.interact(input, 200), isTrue);
      expect(b.attachment, CharacterAttachment.none);
    }
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.interact(CharacterEvent.dragStart, 100);
    b.observe(sample(2).copyWith(envTags: ['mountain']), 200);
    expect(b.event, CharacterEvent.dragStart);
    b.interact(CharacterEvent.dragEnd, 300);
    b.observe(sample(3).copyWith(envTags: ['mountain']), 1000);
    expect(b.event, isNull);
  });

  test('신호 복귀는 환경 기준만 잡고 reset은 환경과 제한을 모두 지운다', () {
    final b = CharacterBehavior()..observe(sample(1), 0);
    b.observe(sample(2).copyWith(envTags: ['coast']), 100);
    b.observe(null, 200);
    expect(b.attachment, CharacterAttachment.none);
    b.observe(sample(3).copyWith(envTags: ['mountain', 'rain']), 9000);
    expect(b.event, isNull);
    b.reset();
    b.observe(sample(1), 0);
    b.observe(sample(2).copyWith(envTags: ['coast']), 100);
    expect(b.event, CharacterEvent.windowCling);
  });
}
