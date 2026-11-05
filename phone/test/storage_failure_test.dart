import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:allo_phone/storage/dex_store.dart';
import 'package:allo_phone/storage/pairing_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  final stored = <String, Object>{};
  var failListWrite = false;
  var failRemove = false;

  setUp(() async {
    stored.clear();
    failListWrite = false;
    failRemove = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll' || call.method == 'getAllWithParameters') {
        return Map<String, Object>.of(stored);
      }
      final arguments = Map<String, Object?>.from(call.arguments as Map);
      final key = arguments['key']! as String;
      if (call.method == 'remove') {
        if (failRemove) return false;
        stored.remove(key);
        return true;
      }
      if (call.method == 'setStringList' && failListWrite) return false;
      if (call.method == 'setString' || call.method == 'setStringList') {
        stored[key] = arguments['value']!;
        return true;
      }
      throw StateError('Unexpected preferences method: ${call.method}');
    });
    await (await SharedPreferences.getInstance()).reload();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('도감 쓰기가 false이면 실패를 알리고 같은 기록을 다시 저장할 수 있다', () async {
    final store = DexStore();
    final entry = DexEntry(
      speciesId: 'pebble_pup',
      obtainedAt: DateTime.utc(2026, 11, 4),
      envTags: const ['city'],
      regionTag: 'city',
      tier: 1,
    );
    failListWrite = true;
    await expectLater(store.add(entry), throwsStateError);
    failListWrite = false;
    await store.add(entry);
    await (await SharedPreferences.getInstance()).reload();
    final entries = await store.all();
    expect(entries, hasLength(1));
    expect(entries.single.speciesId, 'pebble_pup');
  });

  test('페어링 삭제가 false이면 실패를 알리고 삭제를 다시 시도할 수 있다', () async {
    final store = PairingStore();
    await store.save(PairingCredentials.parseFields(
        'b0c260a8-e807-42e9-a119-26119837113b', '123456'));
    failRemove = true;
    await expectLater(store.clear(), throwsStateError);
    await (await SharedPreferences.getInstance()).reload();
    expect((await store.read())?.sessionId,
        'b0c260a8-e807-42e9-a119-26119837113b');
    failRemove = false;
    await store.clear();
    await (await SharedPreferences.getInstance()).reload();
    expect(await store.read(), isNull);
  });
}
