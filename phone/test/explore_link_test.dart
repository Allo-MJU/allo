import 'package:allo_phone/explore/explore_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ready 전 메시지는 마지막 것만 모았다가 보낸다', () {
    final sent = <String>[];
    final link = ExploreLink(sent.add)
      ..post('scene', 's1')
      ..post('scene', 's2')
      ..post('cast', 'c1')
      ..post('jolt', 'j1');
    expect(sent, isEmpty);
    link.onReady();
    expect(sent, unorderedEquals(['s2', 'c1']));
  });

  test('ready 후에는 바로 보내고, 같은 값은 다시 보내지 않는다', () {
    final sent = <String>[];
    final link = ExploreLink(sent.add)..onReady();
    link
      ..post('scene', 's2')
      ..post('scene', 's2')
      ..post('scene', 's3');
    expect(sent, ['s2', 's3']);
  });

  test('jolt 는 ready 후 같은 값이어도 매번 보낸다', () {
    final sent = <String>[];
    final link = ExploreLink(sent.add)..onReady();
    link
      ..post('jolt', 'j')
      ..post('jolt', 'j');
    expect(sent, ['j', 'j']);
  });

  test('Unity 가 다시 ready 를 보내면 (재시작) 마지막 값을 다시 보낸다', () {
    final sent = <String>[];
    final link = ExploreLink(sent.add)
      ..onReady()
      ..post('scene', 's1');
    link.onReady();
    expect(sent, ['s1', 's1']);
  });
}
