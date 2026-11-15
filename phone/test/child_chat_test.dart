import 'dart:async';
import 'package:allo_phone/child_chat/chat_controller.dart';
import 'package:allo_phone/child_chat/chat_screen.dart';
import 'package:allo_phone/child_chat/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Request {
  _Request(this.message, this.species, this.history);
  final String message, species;
  final List<ChatTurn> history;
}

class _Service implements ChatService {
  @override
  bool get isDemo => false;
  bool closed = false;
  final requests = <_Request>[];
  final pending = <Completer<ChatReply>>[];
  @override
  Future<ChatReply> reply(
      String message, String species, List<ChatTurn> history) {
    requests.add(_Request(message, species, List.of(history)));
    final c = Completer<ChatReply>();
    pending.add(c);
    return c.future;
  }

  @override
  void close() => closed = true;
}

const _answer = ChatReply('Water can change from a liquid into a gas.',
    'Ask a trusted adult where they have noticed evaporation.', 'ai');

void main() {
  test('consent, valid text, trimmed free input and pending deduplication',
      () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'sea_mist');
    addTearDown(c.dispose);
    expect(await c.send('Why does water evaporate?'), false);
    c.allowSession();
    expect(await c.send('  '), false);
    expect(await c.send('x' * 601), false);
    expect(s.requests, isEmpty);
    final sent = c.send('  Why does water evaporate?  ');
    expect(s.requests.single.message, 'Why does water evaporate?');
    expect(s.requests.single.species, 'sea_mist');
    expect(s.requests.single.history, isEmpty);
    expect(c.busy, true);
    expect(await c.send('Duplicate'), false);
    s.pending.single.complete(_answer);
    expect(await sent, true);
    expect(c.busy, false);
    expect(c.pendingQuestion, isNull);
    expect(c.exchanges.single.question, 'Why does water evaporate?');
    expect(() => c.exchanges.clear(), throwsUnsupportedError);
  });
  test('history includes only completed AI user-assistant pairs', () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'road_sprout');
    addTearDown(c.dispose);
    c.allowSession();
    var sent = c.send('first');
    s.pending.last.complete(_answer);
    await sent;
    sent = c.send('second');
    s.pending.last.complete(ChatReply.unavailable);
    await sent;
    sent = c.send('third');
    expect(s.requests.last.history.map((t) => t.toJson()).toList(), [
      {'role': 'user', 'content': 'first'},
      {
        'role': 'assistant',
        'content': '${_answer.answer}\n${_answer.parentPrompt}'
      },
    ]);
    s.pending.last.complete(_answer);
    await sent;
  });
  test('clear rejects old response without disturbing new pending request',
      () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'road_sprout');
    addTearDown(c.dispose);
    c.allowSession();
    final old = c.send('old');
    c.clear();
    expect(c.consented, false);
    expect(c.busy, false);
    expect(await c.send('without consent'), false);
    c.allowSession();
    final fresh = c.send('new');
    s.pending.first.complete(_answer);
    expect(await old, false);
    expect(c.exchanges, isEmpty);
    expect(c.busy, true);
    expect(c.pendingQuestion, 'new');
    s.pending.last.complete(_answer);
    expect(await fresh, true);
    expect(c.exchanges.single.question, 'new');
  });
  test('dispose closes transport and suppresses late answer', () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'road_sprout');
    c.allowSession();
    final sent = c.send('Question');
    c.dispose();
    expect(s.closed, true);
    s.pending.single.complete(_answer);
    expect(await sent, false);
    expect(c.exchanges, isEmpty);
  });
  test('provider exception shows fallback without private error detail',
      () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'road_sprout');
    addTearDown(c.dispose);
    c.allowSession();
    final sent = c.send('Question');
    s.pending.single.completeError(StateError('private provider detail'));
    expect(await sent, true);
    expect(c.exchanges.single.reply, ChatReply.unavailable);
    expect(c.exchanges.single.reply.answer, isNot(contains('private')));
    expect(c.busy, false);
  });
  test('conversation continues past six turns with bounded recent context',
      () async {
    final s = _Service();
    final c = ChildChatController(service: s, speciesId: 'road_sprout');
    addTearDown(c.dispose);
    c.allowSession();
    for (var i = 0; i < 9; i++) {
      final sent = c.send('Question $i');
      expect(s.requests.last.history.length, (i > 6 ? 6 : i) * 2);
      s.pending.last.complete(_answer);
      await sent;
    }
    expect(s.requests.length, 9);
    expect(s.requests.last.history.first.content, 'Question 2');
    c.clear();
    c.allowSession();
    final sent = c.send('fresh');
    expect(s.requests.last.history, isEmpty);
    s.pending.last.complete(_answer);
    await sent;
  });
  test('wire parser rejects malformed, oversized, unknown and demo sources',
      () {
    final valid = {
      'answer': 'An explanation.',
      'parentPrompt': 'Discuss together.',
      'source': 'ai'
    };
    expect(ChatReply.fromJson(valid).source, 'ai');
    for (final bad in <Map<String, dynamic>>[
      {},
      {...valid, 'answer': ' '},
      {...valid, 'answer': 123},
      {...valid, 'answer': 'x' * 901},
      {...valid, 'parentPrompt': 'x' * 251},
      {...valid, 'parentPrompt': null},
      {...valid, 'source': 'demo'},
      {...valid, 'source': 'invented'},
    ]) {
      expect(() => ChatReply.fromJson(bad), throwsFormatException);
    }
  });
  test('demo never pretends unknown free-text question has a generated answer',
      () async {
    final s = DemoChatService();
    final known = await s.reply('Why is the sky blue?', 'road_sprout', []);
    expect(s.isDemo, true);
    expect(known.source, 'demo');
    expect(known.answer, contains('scatter'));
    final unknown =
        await s.reply('Why does my bicycle have gears?', 'road_sprout', []);
    expect(unknown.source, 'demo');
    expect(unknown.answer, contains('cannot generate'));
  });
  Future<void> mount(WidgetTester t, ChatService s) async {
    await t.pumpWidget(MaterialApp(
        home: ChildChatScreen(
            speciesId: 'sea_mist', name: 'Sea Mist', service: s)));
  }

  Future<void> start(WidgetTester t) async {
    await t.scrollUntilVisible(find.text('Start with an adult'), 150,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Start with an adult'));
    await t.pumpAndSettle();
  }

  testWidgets('English disclosure, custom input, parent invitation and clear',
      (t) async {
    final s = _Service();
    await mount(t, s);
    expect(find.textContaining('ages 10–12'), findsOneWidget);
    expect(find.textContaining('recent chat are sent'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(s.requests, isEmpty);
    await start(t);
    await t.enterText(find.byType(TextField), 'Can wind move water?');
    await t.tap(find.text('Send'));
    await t.pump();
    expect(s.requests.single.message, 'Can wind move water?');
    expect(s.requests.single.species, 'sea_mist');
    expect(t.widget<TextField>(find.byType(TextField)).enabled, false);
    s.pending.single.complete(_answer);
    await t.pumpAndSettle();
    expect(find.text('Sea Mist · AI'), findsOneWidget);
    expect(find.text('Talk together'), findsOneWidget);
    expect(find.text(_answer.parentPrompt), findsOneWidget);
    expect(find.textContaining('Do not interrupt someone who is driving.'),
        findsOneWidget);
    await t.tap(find.text('Clear chat'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Can wind move water?'), findsNothing);
    expect(find.text(_answer.answer), findsNothing);
  });
  testWidgets('demo and failure remain visibly distinct from generated AI',
      (t) async {
    await mount(t, DemoChatService());
    expect(find.textContaining('Nothing you type is sent'), findsOneWidget);
    await start(t);
    expect(find.text('Example mode · scripted replies, not live AI'),
        findsOneWidget);
    await t.enterText(find.byType(TextField), 'What are stars made of?');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('Sea Mist · Example'), findsOneWidget);
    expect(find.textContaining('cannot generate an answer'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    final s = _Service();
    await mount(t, s);
    await start(t);
    await t.enterText(find.byType(TextField), 'A question');
    await t.tap(find.text('Send'));
    s.pending.single.complete(ChatReply.unavailable);
    await t.pumpAndSettle();
    expect(
        find.text('Sea Mist · Connection / safety fallback'), findsOneWidget);
    expect(find.text('Sea Mist · AI'), findsNothing);
  });
  testWidgets(
      'small landscape with keyboard and multiline input has no overflow',
      (t) async {
    t.view.physicalSize = const Size(800, 360);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetViewInsets);
    await mount(t, DemoChatService());
    await start(t);
    t.view.viewInsets = const FakeViewPadding(bottom: 240);
    await t.enterText(find.byType(TextField),
        'Why is the sky blue?\nWhat changes at sunset?\nCan we talk about light?');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Send').hitTestable(), findsOneWidget);
  });
}
