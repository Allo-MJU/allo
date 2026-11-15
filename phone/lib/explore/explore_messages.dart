import 'dart:convert';

import 'package:allo_core/allo_core.dart';

import '../scene/window_scene.dart';

/// Flutter → Unity 탐험 화면 메시지 (v1). 설계: docs/superpowers/specs/2026-11-09-car-explore-design.md 3.1
///
/// Unity 는 표시 전용이다. 판정 결과나 좌표는 보내지 않고, 장면·등장 캐릭터·흔들림·안내 글만 보낸다.
/// Unity → Flutter 는 의도만 온다: ready · close · tap{id|kind} · feed · drink · lookTogether · endTrip · spotted{id}
/// · care{kind} (품는 알 돌보기: tap·rub·sing·blanket)
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
String routeMessage(List<Turn> turns,
        {double? headingDeg, Cornering? cornering}) =>
    _msg('route', {
      'turns': [for (final t in turns) t.toJson()],
      'heading':
          headingDeg == null ? -1.0 : (headingDeg * 10).roundToDouble() / 10,
      if (cornering?.isValid == true) 'cornering': cornering!.toJson(),
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

/// 품고 있는 알. Unity 는 뒷좌석 둥지에 알을 놓고, 진행도에 따라 흔들림·금을 그린다.
///
/// - [stage] 가 incubating 이면 알이 있다. 같은 [eggId] 의 알이 hatched 로 바뀌면 Unity 가 둥지에서 깨어나는 연출을 하고
///   그 자리에서 동행 캐릭터(cast.companion)를 꺼낸다. 처음부터 hatched 로 들어오면 연출 없이 알을 두지 않는다
/// - [bornText] 는 깨어날 때 보일 글 ("바다안개가 태어났어요!"). 글은 Flutter 가 정한다
String eggMessage(
        {required Stage stage,
        required double progress,
        String? eggId,
        EggTier tier = EggTier.small,
        String? bornText}) =>
    _msg('egg', {
      'state': stage.name,
      'progress': (progress.clamp(0.0, 1.0) * 100).roundToDouble() / 100,
      'eggId': eggId ?? '',
      'big': tier != EggTier.small,
      'bornText': bornText ?? '',
    });

/// "OO가/이 태어났어요!" — 받침 유무로 조사를 고른다
String bornToast(String? nameKo) {
  if (nameKo == null || nameKo.isEmpty) return '알에서 친구가 태어났어요!';
  return '$nameKo${_hasBatchim(nameKo) ? '이' : '가'} 태어났어요!';
}

bool _hasBatchim(String word) {
  final code = word.codeUnitAt(word.length - 1);
  return code >= 0xAC00 && code <= 0xD7A3 && (code - 0xAC00) % 28 != 0;
}

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
  return '$nameKo${_hasBatchim(nameKo) ? '을' : '를'} 봤어!';
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
