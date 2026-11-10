import 'package:allo_core/allo_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _base() => {
      'ts': 1,
      'gear': 'D',
      'speedKph': 50,
      'distanceM': 0,
      'harshBrake': 0,
      'harshSteer': 0,
      'wiperLevel': 0,
      'headlightOn': false,
      'seatRow2': true,
      'envTags': <String>[],
      'capabilities': <String>[],
    };

void main() {
  test('turns 누락은 빈 목록', () {
    expect(VehicleState.fromJson(_base()).turns, isEmpty);
  });

  test('가까운 순 최대 3개, 모르는 type·깨진 값은 버린다', () {
    final v = VehicleState.fromJson({
      ..._base(),
      'turns': [
        {'type': 'uturn', 'inM': 900},
        {'type': 'left', 'inM': 229.6},
        {'type': 'toll', 'inM': 50},
        {'type': 'right', 'inM': -3},
        {'type': 'keepLeft'},
        'bad',
        {'type': 'keepRight', 'inM': 1500},
      ],
    });
    expect(v.turns, [const Turn('right', 0), const Turn('left', 230), const Turn('uturn', 900)]);
  });

  test('headingDeg 는 0~360 으로 맞추고, 숫자가 아니면 null', () {
    expect(VehicleState.fromJson(_base()).headingDeg, isNull);
    expect(VehicleState.fromJson({..._base(), 'headingDeg': 87.5}).headingDeg, 87.5);
    expect(VehicleState.fromJson({..._base(), 'headingDeg': -90}).headingDeg, 270);
    expect(VehicleState.fromJson({..._base(), 'headingDeg': 720.5}).headingDeg, 0.5);
    expect(VehicleState.fromJson({..._base(), 'headingDeg': 'n'}).headingDeg, isNull);
  });

  test('turns 가 목록이 아니면 빈 목록', () {
    expect(VehicleState.fromJson({..._base(), 'turns': {'type': 'left', 'inM': 3}}).turns, isEmpty);
  });
}
