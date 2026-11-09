import 'package:allo_core/allo_core.dart';

/// 최신 아트 포즈 중 동행 화면에서 사용하는 상태. SAD는 사용하지 않는다.
enum CharacterPose { idle, move, happy, surprised, sleep }

enum CharacterAttachment { none, window, seat }

enum CharacterEvent {
  tap,
  dragStart,
  dragEnd,
  feed,
  play,
  lookOut,
  depart,
  stop,
  brake,
  steer,
  windowCling,
}

/// 폰의 표시 전용 반응 규칙. 서버·등급·돌봄 값을 변경하지 않는다.
///
/// [nowMs]는 호출자가 공급하는 단조 시계다. 타이머를 만들지 않으므로 UI는
/// [nextDeadlineMs]에 [advance]를 호출하고 수신·입력 직후에도 상태를 읽는다.
/// 새 세션/회차와 앱 중단 경계에서는 [reset]으로 과거 반응을 제거한다.
class CharacterBehavior {
  static const _sleepAfterMs = 8000;
  static const _inputCooldownMs = 400;

  CharacterEvent? _event;
  int? _expiresAt;
  int? _lastVehicleTs;
  int _brakes = 0;
  int _steers = 0;
  bool _raining = false;
  String? _scenery;
  int? _lastWindowAt;
  bool? _moving;
  int? _stationarySince;
  bool _asleep = false;
  int _now = 0;
  int _revision = 0;
  final Map<CharacterEvent, int> _lastInput = {};

  CharacterPose get pose => switch (_event) {
        CharacterEvent.brake ||
        CharacterEvent.steer ||
        CharacterEvent.lookOut =>
          CharacterPose.surprised,
        CharacterEvent.tap ||
        CharacterEvent.dragStart ||
        CharacterEvent.dragEnd ||
        CharacterEvent.feed ||
        CharacterEvent.play ||
        CharacterEvent.windowCling =>
          CharacterPose.happy,
        CharacterEvent.depart => CharacterPose.move,
        CharacterEvent.stop => CharacterPose.idle,
        null => _moving == true
            ? CharacterPose.move
            : _asleep
                ? CharacterPose.sleep
                : CharacterPose.idle,
      };

  CharacterEvent? get event => _event;
  int get revision => _revision;

  CharacterAttachment get attachment => switch (_event) {
        CharacterEvent.brake ||
        CharacterEvent.steer =>
          CharacterAttachment.seat,
        CharacterEvent.windowCling => CharacterAttachment.window,
        _ => CharacterAttachment.none,
      };

  String? get message => switch (_event) {
        CharacterEvent.tap => '만나서 반가워!',
        CharacterEvent.dragStart => '같이 움직여 볼까?',
        CharacterEvent.dragEnd => '여기가 내 자리야!',
        CharacterEvent.feed => '냠냠, 맛있어!',
        CharacterEvent.play => '너랑 노니까 신나!',
        CharacterEvent.lookOut => '창밖에 뭐가 있을까?',
        CharacterEvent.depart => '같이 출발하자!',
        CharacterEvent.stop => '잠깐 쉬어 갈까?',
        CharacterEvent.brake => '앗, 깜짝 놀랐어!',
        CharacterEvent.steer => '몸이 살짝 흔들렸네!',
        CharacterEvent.windowCling => '창문에 붙어서 구경할래!',
        null => null,
      };

  int? get nextDeadlineMs {
    final sleepAt = !_asleep && _stationarySince != null
        ? _stationarySince! + _sleepAfterMs
        : null;
    if (_expiresAt == null) return sleepAt;
    if (sleepAt == null) return _expiresAt;
    return _expiresAt! < sleepAt ? _expiresAt : sleepAt;
  }

  /// 수신 순서·누적 카운터를 확인한 뒤 실제 새 차량 사건만 반응으로 만든다.
  void observe(VehicleState? vehicle, int nowMs) {
    advance(nowMs);
    final before = _snapshot;
    if (vehicle == null) {
      // 신호 없음은 종료가 아니다. 복귀한 첫 신호도 과거 사건을 재생하지 않는다.
      _lastVehicleTs = null;
      _raining = false;
      _scenery = null;
      _moving = null;
      _stationarySince = null;
      _asleep = false;
      if (_isVehicleEvent(_event)) {
        _event = null;
        _expiresAt = null;
      }
      _changed(before);
      return;
    }
    if (_lastVehicleTs != null && vehicle.ts <= _lastVehicleTs!) return;
    final first = _lastVehicleTs == null;
    final rollback = !first &&
        (vehicle.harshBrake < _brakes || vehicle.harshSteer < _steers);
    final brake = !first && !rollback && vehicle.harshBrake > _brakes;
    final steer = !first && !rollback && vehicle.harshSteer > _steers;
    final raining = vehicle.envTags.contains('rain') || vehicle.wiperLevel > 0;
    final scenery = vehicle.envTags.contains('coast')
        ? 'coast'
        : vehicle.envTags.contains('mountain')
            ? 'mountain'
            : null;
    final windowChanged = !first &&
        !rollback &&
        ((raining && !_raining) || (scenery != null && scenery != _scenery));
    // 수락되지 않은 풍경도 소비한다. 반응 종료 뒤 과거 사건을 재생하지 않는다.
    _raining = raining;
    _scenery = scenery;
    _lastVehicleTs = vehicle.ts;
    _brakes = vehicle.harshBrake;
    _steers = vehicle.harshSteer;

    final wasMoving = _moving;
    final moving = vehicle.gear == 'P' || vehicle.speedKph <= .5
        ? false
        : vehicle.speedKph >= 3
            ? true
            : _moving ?? false;
    _moving = moving;
    if (moving) {
      _stationarySince = null;
      _asleep = false;
    } else if (_stationarySince == null || wasMoving == true) {
      _stationarySince = _now;
      _asleep = false;
    }
    _changed(before);
    if (brake) {
      interact(CharacterEvent.brake, _now);
    } else if (steer) {
      interact(CharacterEvent.steer, _now);
    } else if (windowChanged) {
      interact(CharacterEvent.windowCling, _now);
    } else if (!first && !rollback && moving != wasMoving) {
      interact(moving ? CharacterEvent.depart : CharacterEvent.stop, _now);
    }
  }

  /// 수락한 이벤트만 true. 거부된 입력을 큐에 남기지 않는다.
  bool interact(CharacterEvent incoming, int nowMs) {
    advance(nowMs);
    if (incoming == CharacterEvent.windowCling &&
        _lastWindowAt != null &&
        _now - _lastWindowAt! < 8000) {
      return false;
    }
    final releasingDrag = incoming == CharacterEvent.dragEnd &&
        _event == CharacterEvent.dragStart;
    // 놓기는 이미 시작한 제스처의 종료이므로 입력 제한으로 막으면 안 된다.
    if (_isUserEvent(incoming) && !releasingDrag) {
      final last = _lastInput[incoming];
      if (last != null && _now - last < _inputCooldownMs) return false;
    }
    final current = _event;
    if (current != null && !releasingDrag) {
      if (_priority(incoming) < _priority(current)) return false;
      // 급변을 반복 수신해도 놀람을 무한 연장하지 않는다. 동시에는 제동 우선.
      if (_isHarsh(current) && _isHarsh(incoming)) {
        if (current == CharacterEvent.steer &&
            incoming == CharacterEvent.brake) {
          _event = incoming;
          _revision++;
          return true;
        }
        return false;
      }
    }
    if (incoming == CharacterEvent.dragEnd && !releasingDrag) return false;
    _event = incoming;
    if (incoming == CharacterEvent.windowCling) _lastWindowAt = _now;
    final duration = _durationMs(incoming);
    _expiresAt = duration == null ? null : _now + duration;
    if (_isUserEvent(incoming)) _lastInput[incoming] = _now;
    _revision++;
    return true;
  }

  /// 타이머 만료는 활성 사건을 끝낼 뿐, 관측하지 않은 차량 사건을 만들지 않는다.
  void advance(int nowMs) {
    final before = _snapshot;
    if (nowMs > _now) _now = nowMs;
    if (_expiresAt != null && _now >= _expiresAt!) {
      _event = null;
      _expiresAt = null;
    }
    if (_stationarySince != null && _now - _stationarySince! >= _sleepAfterMs) {
      _asleep = true;
    }
    _changed(before);
  }

  void reset() {
    _event = null;
    _expiresAt = null;
    _lastVehicleTs = null;
    _brakes = 0;
    _steers = 0;
    _raining = false;
    _scenery = null;
    _lastWindowAt = null;
    _moving = null;
    _stationarySince = null;
    _asleep = false;
    _now = 0;
    _lastInput.clear();
    _revision++;
  }

  Object get _snapshot => (pose, _event, _expiresAt, nextDeadlineMs, _moving);

  void _changed(Object before) {
    if (before != _snapshot) _revision++;
  }

  static bool _isHarsh(CharacterEvent? e) =>
      e == CharacterEvent.brake || e == CharacterEvent.steer;

  static bool _isVehicleEvent(CharacterEvent? e) =>
      _isHarsh(e) ||
      e == CharacterEvent.depart ||
      e == CharacterEvent.stop ||
      e == CharacterEvent.windowCling;

  static bool _isUserEvent(CharacterEvent e) => !_isVehicleEvent(e);

  static int _priority(CharacterEvent e) => switch (e) {
        CharacterEvent.brake || CharacterEvent.steer => 100,
        CharacterEvent.dragStart => 60,
        CharacterEvent.feed ||
        CharacterEvent.play ||
        CharacterEvent.lookOut =>
          40,
        CharacterEvent.tap || CharacterEvent.dragEnd => 30,
        CharacterEvent.windowCling => 25,
        CharacterEvent.depart || CharacterEvent.stop => 20,
      };

  static int? _durationMs(CharacterEvent e) => switch (e) {
        CharacterEvent.brake || CharacterEvent.steer => 1500,
        CharacterEvent.tap || CharacterEvent.lookOut => 900,
        CharacterEvent.feed || CharacterEvent.play => 1200,
        CharacterEvent.dragStart => null,
        CharacterEvent.dragEnd => 600,
        CharacterEvent.windowCling => 2400,
        CharacterEvent.depart || CharacterEvent.stop => 900,
      };
}
