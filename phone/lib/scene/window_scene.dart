import 'package:allo_core/allo_core.dart';

/// 창밖 장면 종류. 이슈 #45.
/// 숲은 따로 두지 않고 산 장면에 섞는다. 지역 태그가 없으면 기본 도로다.
enum SceneKind { road, coast, mountain, city, tunnel }

/// `/vehicle` 스냅샷 하나로 정한 창밖 상태. 표시 전용이며 게임 판정에 쓰지 않는다.
class WindowScene {
  const WindowScene({
    required this.kind,
    this.night = false,
    this.highway = false,
    this.rainLevel = 0,
    this.speedKph = 0,
  });

  final SceneKind kind;

  /// 낮 그림 위에 밤 틴트를 씌운다. 터널에서는 항상 false.
  final bool night;

  /// 가까운 겹을 고속도로(방음벽)로 바꾼다.
  final bool highway;

  /// 0 은 비 없음, 1~3 은 빗줄기 세기. 터널에서는 항상 0.
  final int rainLevel;

  /// 움직임 상태의 접근성 설명용 속도. 배경 이동에는 사용하지 않는다.
  final double speedKph;

  bool get moving => speedKph > 0;

  static const initial = WindowScene(kind: SceneKind.road);

  factory WindowScene.fromVehicle(VehicleState? v) {
    if (v == null) return initial;
    final tags = v.envTags.toSet();
    final tunnel = tags.contains('tunnel');
    final moving = v.gear != 'P' && v.speedKph > 0.5;
    return WindowScene(
      kind: tunnel ? SceneKind.tunnel : regionOf(tags),
      night: !tunnel && tags.contains('night'),
      highway: tags.contains('highway'),
      // rain 태그는 와이퍼가 켜졌다는 뜻이라 level 0 이 오면 가장 약한 비로 본다.
      rainLevel:
          !tunnel && tags.contains('rain') ? v.wiperLevel.clamp(1, 3) : 0,
      speedKph: moving ? v.speedKph : 0,
    );
  }

  /// 차는 지역 태그를 하나만 보내지만, 여러 개가 와도 schema 3.3 순서(coast → mountain → city)를 따른다.
  static SceneKind regionOf(Set<String> tags) {
    if (tags.contains('coast')) return SceneKind.coast;
    if (tags.contains('mountain')) return SceneKind.mountain;
    if (tags.contains('city')) return SceneKind.city;
    return SceneKind.road;
  }

  WindowScene withKind(SceneKind k) => WindowScene(
      kind: k,
      night: night,
      highway: highway,
      rainLevel: rainLevel,
      speedKph: speedKph);

  @override
  bool operator ==(Object other) =>
      other is WindowScene &&
      other.kind == kind &&
      other.night == night &&
      other.highway == highway &&
      other.rainLevel == rainLevel &&
      other.speedKph == speedKph;

  @override
  int get hashCode => Object.hash(kind, night, highway, rainLevel, speedKph);

  @override
  String toString() =>
      'WindowScene($kind, night=$night, highway=$highway, rain=$rainLevel, ${speedKph}km/h)';
}

/// 지역 반경 경계에서 태그가 켜졌다 꺼졌다 해도 장면이 깜빡이지 않게 한다.
///
/// - 지역 장면(바다·산·도시·기본 도로) 사이의 전환은 새 장면이 [holdMs] 동안 이어질 때만 한다.
/// - 터널 진입·이탈은 경계 왕복이 아니라 바로 바꾼다.
/// - 비·밤·고속도로·속도는 장면 종류와 무관하게 바로 반영한다.
///
/// [holdMs] 기본값은 임시다. 차량 위치 갱신 주기 실측(A) 후 조정한다.
class SceneStabilizer {
  SceneStabilizer({this.holdMs = 4000});

  final int holdMs;
  SceneKind? _shown;
  SceneKind? _pending;
  int _pendingSince = 0;

  SceneKind? get shown => _shown;

  WindowScene update(WindowScene target, int nowMs) {
    final k = target.kind;
    final shown = _shown;
    if (shown == null ||
        k == shown ||
        k == SceneKind.tunnel ||
        shown == SceneKind.tunnel) {
      _shown = k;
      _pending = null;
    } else if (k != _pending) {
      _pending = k;
      _pendingSince = nowMs;
    } else if (nowMs - _pendingSince >= holdMs) {
      _shown = k;
      _pending = null;
    }
    return target.withKind(_shown!);
  }
}
