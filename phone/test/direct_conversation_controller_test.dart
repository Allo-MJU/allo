import 'dart:async';
import 'package:allo_phone/learning/companion_learning_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'companion_learning_test.dart' as fixture;

Map<String, dynamic> directReply(Map<String, dynamic> request) => {
      ...fixture.reply(request),
      'mode': 'chat',
      'source': 'ai',
      'text':
          request['action'] == 'greet' ? '안녕! 오늘은 어떤 기분이야?' : '졸리면 잠깐 쉬어도 좋아.'
    };

void main() {
  late CompanionLearningController controller;
  late fixture.MemoryLearningStore store;
  late List<Map<String, dynamic>> requests;
  late List<String> spoken;
  void create(
      {Future<Map<String, dynamic>> Function(Map<String, dynamic>)? request}) {
    controller = CompanionLearningController(
        catalog: fixture.catalog(),
        store: store,
        request: request ??
            (body) async {
              requests.add(body);
              return directReply(body);
            },
        speak: (text) async {
          spoken.add(text);
        },
        stop: () async {});
    controller.setContext(
        profile: 'real', creatures: fixture.owned, active: true);
  }

  setUp(() {
    store = fixture.MemoryLearningStore();
    requests = [];
    spoken = [];
    create();
  });
  tearDown(() => controller.dispose());
  test(
      'open sends AI greet directly without synthetic child history or persistence',
      () async {
    await controller.select('one');
    expect(await controller.openConversation(requestId: 'greet-1'), true);
    expect(requests.single['action'], 'greet');
    expect(requests.single['text'], '');
    expect(controller.conversationMode, 'chat');
    expect(controller.snapshot['source'], 'ai');
    expect(controller.snapshot['lastUserText'], '');
    expect(controller.history, isEmpty);
    expect(store.data, isEmpty);
    expect(spoken.single, '안녕! 오늘은 어떤 기분이야?');
  });
  test(
      'close reopen retains six actual pairs for greeting without fake user turns',
      () async {
    await controller.select('one');
    await controller.openConversation(requestId: 'greet');
    for (var i = 0; i < 8; i++) {
      expect(await controller.chat('졸려 $i', requestId: 'child-$i'), true);
    }
    controller.closeInvitation();
    expect(controller.conversationMode, 'closed');
    expect(controller.history, hasLength(12));
    await controller.openConversation(requestId: 'reopen');
    expect(requests.last['action'], 'greet');
    expect((requests.last['history'] as List).first['text'], '졸려 2');
    expect(controller.snapshot['lastUserText'], '졸려 7');
    expect(controller.history, hasLength(12));
    expect(store.data.toString(), isNot(contains('졸려')));
  });
  test(
      'target profile and connection changes clear dialogue without disk transcripts',
      () async {
    for (final change in ['target', 'profile', 'connection']) {
      await controller.select('one');
      await controller.openConversation(requestId: 'greet-$change');
      await controller.chat('PRIVATE_CHILD', requestId: 'child-$change');
      if (change == 'target') await controller.select('two');
      if (change == 'profile') {
        controller.setContext(
            profile: 'demo', creatures: fixture.owned, active: true);
      }
      if (change == 'connection') controller.invalidate();
      expect(controller.history, isEmpty);
      expect(controller.snapshot['lastUserText'], '');
      expect(controller.snapshot['text'], '');
      expect(store.data.toString(), isNot(contains('PRIVATE_CHILD')));
      controller.setActive(true);
    }
  });
  test(
      'closing pending greeting drops late output and leaves history untouched',
      () async {
    final gate = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> sent;
    controller.dispose();
    create(request: (body) {
      sent = body;
      return gate.future;
    });
    await controller.select('one');
    final pending = controller.openConversation(requestId: 'pending');
    await Future<void>.delayed(Duration.zero);
    controller.closeInvitation();
    gate.complete(directReply(sent));
    expect(await pending, false);
    expect(controller.conversationMode, 'closed');
    expect(controller.history, isEmpty);
    expect(spoken, isEmpty);
  });
  test('failed or forged authored greeting never masquerades as conversation',
      () async {
    for (final response in ['failure', 'authored']) {
      controller.dispose();
      create(request: (body) async {
        if (response == 'failure') throw StateError('unavailable');
        return {...directReply(body), 'source': 'authored'};
      });
      await controller.select('one');
      expect(await controller.openConversation(requestId: response), false);
      expect(controller.snapshot['error'], isNotEmpty);
      expect(controller.snapshot['text'], '');
      expect(controller.snapshot['source'], '');
      expect(controller.history, isEmpty);
      expect(spoken, isEmpty);
    }
  });
}
