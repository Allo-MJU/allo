import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 차 안 말풍선 대사 뱅크(assets/data/cabin_dialogue.json)가 docs/dialogue-style.md 규칙을 지키는지.
/// - 50자 이내, 최대 3문장, 느낌표는 문장당 1개
/// - 영어는 한 문장에 한 덩어리(단어 1개, 또는 "good night"·"bye bye" 같은 두 단어 인사)까지
/// - "~는 영어로 ~" 식 설명 금지: 캐릭터가 신나서 내뱉는 말로 섞는다
/// - 아이에게 되묻기 금지 (이름·나이·사는 곳), 무서운 표현 금지
void main() {
  late Map<String, dynamic> bank;

  setUpAll(() {
    bank = jsonDecode(File('assets/data/cabin_dialogue.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  Iterable<(String key, String line)> lines() sync* {
    for (final item in bank['items'] as List) {
      final m = item as Map<String, dynamic>;
      for (final l in m['lines'] as List) {
        yield (m['key'] as String, l as String);
      }
    }
  }

  test('키 형식은 상황|대상|문맥', () {
    for (final (key, _) in lines()) {
      expect(key.split('|').length, 3, reason: key);
    }
  });

  test('길이·문장 수·느낌표', () {
    for (final (key, raw) in lines()) {
      if (key.startsWith('name|')) continue;
      final line = raw.replaceAll('{name}', '길싹이');
      expect(line.length, lessThanOrEqualTo(50), reason: '$key: $line');
      final sentences = line
          .split(RegExp(r'(?<=[.!?])\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      expect(sentences.length, lessThanOrEqualTo(3), reason: '$key: $line');
      for (final s in sentences) {
        expect('!'.allMatches(s).length, lessThanOrEqualTo(1),
            reason: '$key: $s');
        final english = RegExp(r'[A-Za-z]+').allMatches(s).length;
        expect(english, lessThanOrEqualTo(2), reason: '$key: $s');
        expect(s.contains('영어로'), isFalse, reason: '$key: $s (가르치듯 말하지 않는다)');
      }
    }
  });

  test('아이에게 되묻지 않고 무서운 말이 없다', () {
    final banned = ['이름이 뭐', '몇 살', '어디 살', '피', '죽', '괴물', '비밀이야'];
    for (final (key, line) in lines()) {
      for (final b in banned) {
        expect(line.contains(b), isFalse, reason: '$key: $line ($b)');
      }
    }
  });

  test('12종 이름과 부화 첫마디가 있다', () {
    final keys = (bank['items'] as List)
        .map((e) => (e as Map<String, dynamic>)['key'] as String)
        .toSet();
    for (final id in [
      'road_sprout', 'bridge_hopper', 'mountain_sprite', 'puddle_pip',
      'river_glider', 'tide_keeper', 'storm_lantern', 'sea_mist',
      'lamp_moth', 'tunnel_moth', 'star_owl', 'highway_comet',
    ]) {
      expect(keys, contains('name|$id|*'));
    }
    expect(keys, contains('hatch|*|*'));
    for (final evt in ['scene', 'idle', 'request', 'snack', 'ball', 'pet', 'blanket', 'window', 'window_done']) {
      expect(keys.any((k) => k.startsWith('$evt|')), isTrue, reason: evt);
    }
  });
}
