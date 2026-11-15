import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/affinity/egg_demo_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late HttpEggDemoApi api;
  const photoId = '0123456789abcdef0123456789abcdef';
  final receipt = {
    'eggId': 'egg_1',
    'requestId': 'request-1',
    'photoId': photoId,
    'uploadedAtMs': 123
  };
  Matcher failure([String? code]) => isA<EggDemoApiException>()
      .having((e) => e.code, 'code', code ?? isNotEmpty);
  Future<void> reply(HttpRequest req, Object body, {int status = 200}) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = HttpEggDemoApi(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        token: 'private-token',
        allowInsecureLoopback: true);
  });
  tearDown(() async {
    api.close();
    await server.close(force: true);
  });
  Future<SpeechSentiment> evaluate([String text = 'hello']) =>
      api.evaluate(eggId: 'egg_1', requestId: 'request-1', text: text);
  test(
      'companion turns reuse authenticated transport and preserve server output',
      () async {
    final body = {
      'requestId': 'turn-1',
      'action': 'invite',
      'creatureId': 'one',
      'speciesId': 'road_sprout'
    };
    final output = {'requestId': 'turn-1', 'text': '서버 초대', 'mode': 'menu'};
    server.listen((req) async {
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/companion/turn');
      expect(req.headers.value('authorization'), 'Bearer private-token');
      expect(jsonDecode(await utf8.decoder.bind(req).join()), body);
      await reply(req, output);
    });
    expect(await api.companionTurn(body), output);
  });
  test(
      'quest templates reuse authenticated transport and preserve nullable targets',
      () async {
    final body = {'speciesId': 'bridge_hopper', 'kind': 'story', 'variant': 0};
    final output = {
      'schemaVersion': 1,
      'templateId': 'bridge_hopper_food_0',
      'templateVersion': 1,
      'speciesId': 'bridge_hopper',
      'kind': 'food',
      'title': '간식 부탁',
      'text': '베리 간식 하나 나눠 줄래?',
      'storyId': null,
      'targetFoodId': 'berry_snack',
      'targetRegion': null,
    };
    server.listen((req) async {
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/companion/quest-template');
      expect(req.headers.value('authorization'), 'Bearer private-token');
      expect(jsonDecode(await utf8.decoder.bind(req).join()), body);
      await reply(req, output);
    });
    expect(await api.companionQuestTemplate(body), output);
  });
  for (final sentiment in SpeechSentiment.values) {
    test('authenticated evaluation ${sentiment.name}', () async {
      server.listen((req) async {
        expect(req.method, 'POST');
        expect(req.uri.path, '/v1/egg/evaluate');
        expect(req.headers.value('authorization'), 'Bearer private-token');
        expect(jsonDecode(await utf8.decoder.bind(req).join()),
            {'eggId': 'egg_1', 'requestId': 'request-1', 'text': 'hello'});
        await reply(req, {
          'eggId': 'egg_1',
          'requestId': 'request-1',
          'sentiment': sentiment.name
        });
      });
      expect(await evaluate(), sentiment);
    });
  }
  for (final body in [
    {'eggId': 'wrong', 'requestId': 'request-1', 'sentiment': 'positive'},
    {'eggId': 'egg_1', 'requestId': 'wrong', 'sentiment': 'positive'},
    {'eggId': 'egg_1', 'requestId': 'request-1', 'sentiment': 'bad'},
    {},
    ['positive']
  ]) {
    test('reject malformed evaluation $body', () async {
      server.listen((req) => reply(req, body));
      await expectLater(evaluate(), throwsA(failure()));
    });
  }
  test('HTTP errors sanitize private payload', () async {
    server.listen(
        (req) => reply(req, {'secret': 'private-token hello'}, status: 503));
    try {
      await evaluate();
      fail('must throw');
    } on EggDemoApiException catch (e) {
      expect(e.toString(), isNot(contains('private-token')));
      expect(e.toString(), isNot(contains('hello')));
    }
  });
  test('invalid inputs never reach server', () async {
    var calls = 0;
    server.listen((req) {
      calls++;
      req.response.close();
    });
    for (final text in ['', ' ', 'x' * 501]) {
      await expectLater(evaluate(text), throwsA(failure()));
    }
    await expectLater(api.evaluate(eggId: '../egg', requestId: 'r', text: 'ok'),
        throwsA(failure()));
    for (final bytes in [Uint8List(0), Uint8List(5 * 1024 * 1024 + 1)]) {
      await expectLater(
          api.uploadPhoto(
              eggId: 'e', requestId: 'r', bytes: bytes, mimeType: 'image/jpeg'),
          throwsA(failure()));
    }
    await expectLater(
        api.uploadPhoto(
            eggId: 'e',
            requestId: 'r',
            bytes: Uint8List(1),
            mimeType: 'text/plain'),
        throwsA(failure()));
    await expectLater(api.downloadPhoto('../secret'), throwsA(failure()));
    expect(calls, 0);
  });
  test('reject unsafe URL and token config', () {
    for (final url in [
      'http://example.com',
      'http://127.0.0.1',
      'https://u:p@example.com',
      'https://example.com/path',
      'https://example.com?x=1',
      'https://example.com/#x',
      'ftp://example.com',
      'https:///'
    ]) {
      expect(() => HttpEggDemoApi(baseUri: Uri.parse(url), token: 'token'),
          throwsA(failure()));
    }
    for (final token in ['', 'secret\r\nheader']) {
      expect(
          () => HttpEggDemoApi(
              baseUri: Uri.parse('https://example.com'), token: token),
          throwsA(failure()));
    }
    expect(() => HttpEggDemoApi.fromEnvironment(), throwsA(failure()));
  });
  test('redirect cannot forward auth', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var forwarded = false;
    target.listen((req) {
      forwarded = true;
      req.response.close();
    });
    server.listen((req) async {
      req.response.statusCode = 302;
      req.response.headers.set('location', 'http://127.0.0.1:${target.port}');
      await req.response.close();
    });
    try {
      await expectLater(evaluate(), throwsA(failure()));
      expect(forwarded, false);
    } finally {
      await target.close(force: true);
    }
  });
  test('timeout includes stalled body', () async {
    api.close();
    api = HttpEggDemoApi(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        token: 'token',
        timeout: const Duration(milliseconds: 70),
        allowInsecureLoopback: true);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{');
      await req.response.flush();
    });
    await expectLater(evaluate(), throwsA(failure('timeout')));
  });
  test('upload receipt list and JPEG download', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    server.listen((req) async {
      expect(req.headers.value('authorization'), 'Bearer private-token');
      switch (req.uri.path) {
        case '/v1/egg/photo':
          expect(req.method, 'POST');
          expect(jsonDecode(await utf8.decoder.bind(req).join()), {
            'eggId': 'egg_1',
            'requestId': 'request-1',
            'imageBase64': base64Encode(bytes),
            'mimeType': 'image/png'
          });
          await reply(req, receipt);
        case '/v1/egg/photos':
          expect(req.method, 'GET');
          await reply(req, {
            'photos': [receipt]
          });
        default:
          expect(req.method, 'GET');
          expect(req.uri.path, '/v1/egg/photos/$photoId');
          req.response.headers.contentType = ContentType('image', 'jpeg');
          req.response.add(bytes);
          await req.response.close();
      }
    });
    final uploaded = await api.uploadPhoto(
        eggId: 'egg_1',
        requestId: 'request-1',
        bytes: bytes,
        mimeType: 'image/png');
    expect(uploaded.photoId, photoId);
    expect(uploaded.uploadedAtMs, 123);
    expect((await api.listPhotos()).single.eggId, 'egg_1');
    expect(await api.downloadPhoto(photoId), bytes);
  });
  test('upload rejects mismatched receipt', () async {
    server.listen((req) => reply(req, {...receipt, 'eggId': 'other'}));
    await expectLater(
        api.uploadPhoto(
            eggId: 'egg_1',
            requestId: 'request-1',
            bytes: Uint8List(1),
            mimeType: 'image/jpeg'),
        throwsA(failure()));
  });
  test('strict metadata parser', () {
    for (final invalid in [
      {...receipt, 'uploadedAtMs': '123'},
      {...receipt, 'uploadedAtMs': -1},
      {...receipt, 'photoId': '../x'},
      {...receipt, 'eggId': ''},
      {...receipt, 'token': 'private'}
    ]) {
      expect(() => UploadedEggPhoto.fromJson(invalid), throwsA(failure()));
    }
  });
  test('bounded JSON response', () async {
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write(' ' * (64 * 1024 + 1));
      await req.response.close();
    });
    await expectLater(evaluate(), throwsA(failure()));
  });
  test('bounded photo response', () async {
    server.listen((req) async {
      req.response.headers.contentType = ContentType('image', 'jpeg');
      req.response.add(Uint8List(5 * 1024 * 1024 + 1));
      await req.response.close();
    });
    await expectLater(api.downloadPhoto(photoId), throwsA(failure()));
  });
  test('reject wrong JSON content type', () async {
    server.listen((req) async {
      req.response.write('{}');
      await req.response.close();
    });
    await expectLater(evaluate(), throwsA(failure()));
  });
  test('reject wrong photo content type', () async {
    server.listen((req) => reply(req, receipt));
    await expectLater(api.downloadPhoto(photoId), throwsA(failure()));
  });
  test('reject malformed list', () async {
    server.listen((req) => reply(req, {
          'photos': [null]
        }));
    await expectLater(api.listPhotos(), throwsA(failure()));
  });
  test('close is idempotent and blocks requests', () async {
    api.close();
    api.close();
    await expectLater(evaluate(), throwsA(failure('closed')));
  });
  test('find receipt by egg authenticates and preserves original request ID',
      () async {
    server.listen((req) async {
      expect(req.method, 'GET');
      expect(req.uri.path, '/v1/egg/photos/by-egg/egg_1');
      expect(req.uri.hasQuery, false);
      expect(req.headers.value('authorization'), 'Bearer private-token');
      await reply(req, {...receipt, 'requestId': 'original-upload'});
    });
    final found = await api.findPhotoForEgg('egg_1');
    expect(found?.photoId, photoId);
    expect(found?.requestId, 'original-upload');
  });
  test('find absent egg receipt returns null only for 404', () async {
    server.listen((req) async {
      req.response.statusCode = 404;
      req.response.write('private server payload');
      await req.response.close();
    });
    expect(await api.findPhotoForEgg('egg_1'), isNull);
  });
  for (final invalid in [
    {...receipt, 'eggId': 'other'},
    {...receipt, 'requestId': '../bad'},
    {...receipt, 'photoId': 'bad'},
  ]) {
    test('find rejects mismatched or invalid receipt $invalid', () async {
      server.listen((req) => reply(req, invalid));
      await expectLater(api.findPhotoForEgg('egg_1'), throwsA(failure()));
    });
  }
  test('find invalid egg IDs cannot introduce path or query', () async {
    var calls = 0;
    server.listen((req) {
      calls++;
      req.response.close();
    });
    for (final id in ['', '../egg', 'egg?token=x', 'egg/#x', 'x' * 129]) {
      await expectLater(
          api.findPhotoForEgg(id), throwsA(failure('invalid_input')));
    }
    expect(calls, 0);
  });
  test('find authorization refusal remains an error', () async {
    server.listen((req) => reply(req, {'error': 'private-token'}, status: 401));
    await expectLater(
        api.findPhotoForEgg('egg_1'), throwsA(failure('http_error')));
  });
  for (final upload in [false, true]) {
    test(
        '${upload ? 'photo' : 'Korean evaluation'} sends exact Content-Length without chunking',
        () async {
      final photoBytes = Uint8List.fromList([1, 2, 3, 4]);
      final expectedBody = upload
          ? {
              'eggId': 'egg_1',
              'requestId': 'request-1',
              'imageBase64': base64Encode(photoBytes),
              'mimeType': 'image/jpeg'
            }
          : {
              'eggId': 'egg_1',
              'requestId': 'request-1',
              'text': '안녕 알로! 반가워 🥚'
            };
      late int contentLength;
      String? transferEncoding;
      late List<int> received;
      server.listen((req) async {
        contentLength = req.contentLength;
        transferEncoding =
            req.headers.value(HttpHeaders.transferEncodingHeader);
        received =
            await req.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
        await reply(
            req,
            upload
                ? receipt
                : {
                    'eggId': 'egg_1',
                    'requestId': 'request-1',
                    'sentiment': 'positive'
                  });
      });
      if (upload) {
        await api.uploadPhoto(
            eggId: 'egg_1',
            requestId: 'request-1',
            bytes: photoBytes,
            mimeType: 'image/jpeg');
      } else {
        await evaluate('안녕 알로! 반가워 🥚');
      }
      final expectedBytes = utf8.encode(jsonEncode(expectedBody));
      expect(received, expectedBytes);
      expect(contentLength, expectedBytes.length);
      expect(transferEncoding, isNull);
    });
  }
}
