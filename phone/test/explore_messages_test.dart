import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/explore/explore_messages.dart';
import 'package:allo_phone/scene/window_scene.dart';
import 'package:flutter_test/flutter_test.dart';

VehicleState v({int brake = 0, int steer = 0}) => VehicleState(
      ts: 1,
      gear: 'D',
      speedKph: 50,
      distanceM: 0,
      harshBrake: brake,
      harshSteer: steer,
      wiperLevel: 0,
      headlightOn: false,
      seatRow2: true,
      etaSec: null,
      envTags: const [],
      capabilities: const [],
    );

Species sp(String id) => Species(
      id: id,
      nameEn: id,
      nameKo: id,
      attribute: Attribute.water,
      tier: 1,
      requiredTags: const [],
      maxHarsh: null,
      hint: '',
      sprite: 'species/$id.png',
    );

Map<String, dynamic> dec(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  test('scene 메시지는 WindowScene 을 그대로 옮긴다', () {
    final m = dec(sceneMessage(
        const WindowScene(kind: SceneKind.coast, rainLevel: 2, speedKph: 62)));
    expect(m, {
      'v': 1,
      'type': 'scene',
      'kind': 'coast',
      'night': false,
      'highway': false,
      'rain': 2,
      'speedKph': 62.0,
      'moving': true,
    });
  });

  test('cast 는 친구 최대 3, 동행 캐릭터는 친구에서 뺀다', () {
    final a = sp('a');
    final m = dec(castMessage(
        companion: a, friends: [a, sp('b'), sp('c'), sp('d'), sp('e')]));
    expect(m['v'], 1);
    expect(m['type'], 'cast');
    expect(m['companion'],
        {'id': 'a', 'sprite': 'species/a.png', 'attribute': 'water'});
    expect([for (final f in m['friends'] as List) (f as Map)['id']],
        ['b', 'c', 'd']);
  });

  test('cast 는 동행 캐릭터가 없으면 null', () {
    final m = dec(castMessage(companion: null, friends: const []));
    expect(m['companion'], isNull);
    expect(m['friends'], isEmpty);
  });

  test('jolt·settings 메시지 형식', () {
    expect(
        dec(joltMessage('brake')), {'v': 1, 'type': 'jolt', 'kind': 'brake'});
    expect(dec(settingsMessage(gyro: true, reducedMotion: false)), {
      'v': 1,
      'type': 'settings',
      'gyro': true,
      'reducedMotion': false,
      'canEndTrip': false,
    });
    expect(
        dec(settingsMessage(
            gyro: false, reducedMotion: true, canEndTrip: true))['canEndTrip'],
        isTrue);
  });

  test('toast 메시지는 글과 번호를 담고, 발견 문구는 받침에 맞는 조사를 고른다', () {
    expect(dec(toastMessage('맛있게 먹었어요!', 3)),
        {'v': 1, 'type': 'toast', 'text': '맛있게 먹었어요!', 'seq': 3});
    expect(spottedToast('타이드키퍼'), '타이드키퍼를 봤어!');
    expect(spottedToast('퍼들핍'), '퍼들핍을 봤어!');
    expect(spottedToast(null), '봤어!');
  });

  test('jolt 는 누적값이 늘 때만 한 번', () {
    final d = JoltDetector();
    expect(d.update(v()), isEmpty);
    expect(d.update(v(brake: 1)), ['brake']);
    expect(d.update(v(brake: 1)), isEmpty); // 같은 값 반복
    expect(d.update(v(brake: 1, steer: 2)), ['steer']);
    expect(d.update(v(brake: 3, steer: 3)), ['brake', 'steer']);
  });

  test('jolt: 첫 스냅샷이 이미 누적값을 갖고 있어도 보내지 않는다 (재구독)', () {
    final d = JoltDetector();
    expect(d.update(v(brake: 5, steer: 2)), isEmpty);
    expect(d.update(v(brake: 5, steer: 2)), isEmpty);
  });
}
