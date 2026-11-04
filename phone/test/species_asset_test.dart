import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('앱 내부 생물 에셋은 팀 공용 원본과 일치한다', () async {
    final source = await File('../data/species.json').readAsString();
    final bundled = await rootBundle.loadString('assets/data/species.json');
    expect(bundled, source,
        reason: 'data/species.json 변경 후 assets/data/species.json도 동기화해야 합니다.');
  });
}
