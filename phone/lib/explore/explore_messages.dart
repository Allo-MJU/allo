import 'dart:convert';

import 'package:allo_core/allo_core.dart';

import '../scene/window_scene.dart';

/// Flutter → Unity 탐험 화면 메시지 (v1). 설계: docs/superpowers/specs/2026-11-09-car-explore-design.md 3.1
///
/// Unity 는 표시 전용이다. 판정 결과나 좌표는 보내지 않고, 장면·등장 캐릭터·흔들림만 보낸다.
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

String settingsMessage({required bool gyro, required bool reducedMotion}) =>
    _msg('settings', {'gyro': gyro, 'reducedMotion': reducedMotion});

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
