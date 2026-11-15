import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

void main() {
  test('steering-derived display signal survives vehicle parsing and copies',
      () {
    final vehicle = VehicleState.fromJson({
      'cornering': {'version': 1, 'bend': -0.5, 'receivedAtMs': 1200},
    });
    expect(vehicle.cornering?.bend, -0.5);
    expect(vehicle.copyWith().cornering?.receivedAtMs, 1200);
    expect(vehicle.copyWith(clearCornering: true).cornering, isNull);
  });

  test('legacy snapshots have no steering cue', () {
    expect(VehicleState.fromJson({}).cornering, isNull);
    expect(VehicleState.fromJson({'cornering': null}).cornering, isNull);
  });

  test('left right straight and saturation values keep their sign', () {
    for (final bend in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
      final cue =
          Cornering.parse({'version': 1, 'bend': bend, 'receivedAtMs': 1200});
      expect(cue?.toJson(), {'version': 1, 'bend': bend, 'receivedAtMs': 1200});
    }
  });

  test('malformed or unsupported steering cues are ignored', () {
    for (final value in [
      'invalid',
      <String, Object>{},
      {'version': 2, 'bend': 0.5, 'receivedAtMs': 1200},
      {'version': 1, 'bend': 'right', 'receivedAtMs': 1200},
      {'version': 1, 'bend': double.nan, 'receivedAtMs': 1200},
      {'version': 1, 'bend': double.infinity, 'receivedAtMs': 1200},
      {'version': 1, 'bend': -1.1, 'receivedAtMs': 1200},
      {'version': 1, 'bend': 1.1, 'receivedAtMs': 1200},
      {'version': 1, 'bend': 0.5, 'receivedAtMs': 0},
      {'version': 1, 'bend': 0.5, 'receivedAtMs': -1},
      {'version': 1, 'bend': 0.5, 'receivedAtMs': 1.5},
      {'version': 1, 'bend': 0.5, 'receivedAtMs': double.infinity},
      {'version': 1, 'bend': 0.5, 'receivedAtMs': 9007199254740992},
    ]) {
      expect(VehicleState.fromJson({'cornering': value}).cornering, isNull,
          reason: '$value');
    }
  });
}
