import 'dart:convert';

import 'package:allo_core/allo_core.dart';

import '../scene/window_scene.dart';

/// Flutter → Unity 탐험 화면 메시지 (v1). 설계: docs/superpowers/specs/2026-11-09-car-explore-design.md 3.1
///
/// Unity 는 표시 전용이다. 판정 결과나 좌표는 보내지 않고, 장면·등장 캐릭터·흔들림·안내 글만 보낸다.
/// Unity → Flutter 는 의도만 온다: ready · close · tap{id} · feed · endTrip · spotted{id}
const exploreMessageVersion = 1;

/// 함께 보일 수 있는 친구 수 (동행 캐릭터 제외)
const maxExploreFriends = 3;

String _msg(String type, Map<String, Object?> body) =>
    jsonEncode({'v': exploreMessageVersion, 'type': type, ...body});

String sceneMessage(WindowScene s) => _msg('scene', {
      'kind': s.kind.name,
      'night': s.night,
      'highway': s.highway,
      'rain': s.rainLevel,
      'speedKph': s.speedKph.toDouble(),
      'moving': s.moving,
    });

/// 내비 경로의 다음 회전들과 진행 방향. Unity 가 교차로·회전·유턴을 그 거리에 놓고,
/// 진행 방향이 바뀌는 만큼 앞길을 휘게 한다 (schema.md 3.3 `turns`·`headingDeg`). 방향을 모르면 -1
String routeMessage(List<Turn> turns, {double? headingDeg}) => _msg('route', {
      'turns': [for (final t in turns) t.toJson()],
      'heading': headingDeg == null ? -1.0 : (headingDeg * 10).roundToDouble() / 10,
    });

Map<String, Object?> _member(Species s) =>
    {'id': s.id, 'sprite': s.sprite, 'attribute': s.attribute.name};

String castMessage({Species? companion, required List<Species> friends}) =>
    _msg('cast', {
      'companion': companion == null ? null : _member(companion),
      'friends': [
        for (final f in friends
            .where((f) => f.id != companion?.id)
            .take(maxExploreFriends))
          _member(f),
      ],
    });

/// [kind] 는 `brake` 또는 `steer`
String joltMessage(String kind) => _msg('jolt', {'kind': kind});

/// [canEndTrip]: 체험(Fake) 주행이라 Unity 안에 "주행 종료" 버튼을 보여도 되는지
String settingsMessage(
        {required bool gyro,
        required bool reducedMotion,
        bool canEndTrip = false}) =>
    _msg('settings', {
      'gyro': gyro,
      'reducedMotion': reducedMotion,
      'canEndTrip': canEndTrip,
    });

/// Unity 화면 위에 잠깐 보일 글. [seq] 가 다르면 같은 글도 다시 보낸다 (ExploreLink 는 같은 문자열을 거른다)
String toastMessage(String text, int seq) =>
    _msg('toast', {'text': text, 'seq': seq});

/// "OO를/을 봤어!" — 받침 유무로 조사를 고른다
String spottedToast(String? nameKo) {
  if (nameKo == null || nameKo.isEmpty) return '봤어!';
  final code = nameKo.codeUnitAt(nameKo.length - 1);
  final hangul = code >= 0xAC00 && code <= 0xD7A3;
  final particle = hangul && (code - 0xAC00) % 28 != 0 ? '을' : '를';
  return '$nameKo$particle 봤어!';
}

/// 급제동·급조향 누적값이 늘었을 때만 한 번 알린다.
///
/// 첫 스냅샷은 기준값만 잡는다. 재구독으로 이미 쌓인 누적값이 다시 와도 흔들지 않는다.
class JoltDetector {
  int? _brake;
  int? _steer;

  List<String> update(VehicleState v) {
    final out = <String>[];
    if (_brake != null && v.harshBrake > _brake!) out.add('brake');
    if (_steer != null && v.harshSteer > _steer!) out.add('steer');
    _brake = v.harshBrake;
    _steer = v.harshSteer;
    return out;
  }
}
