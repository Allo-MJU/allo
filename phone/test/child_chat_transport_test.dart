import 'dart:convert';
import 'dart:io';
import 'package:allo_phone/child_chat/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local client sends bounded JSON with Content-Length required by server',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8766);
    final service = LocalChatService();
    addTearDown(() async {
      service.close();
      await server.close(force: true);
    });
    final requestFuture = server.first;
    final replyFuture = service.reply('Why is ice cold?', 'puddle_pip', []);
    final request = await requestFuture;
    expect(request.uri.path, '/chat');
    expect(request.headers.contentType?.mimeType, 'application/json');
    expect(request.headers.contentLength, greaterThan(0));
    expect(request.headers.value('transfer-encoding'), isNull);
    final data = jsonDecode(await utf8.decoder.bind(request).join());
    expect(data, {
      'message': 'Why is ice cold?',
      'speciesId': 'puddle_pip',
      'history': []
    });
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'answer': 'Ice absorbs heat from warmer things.',
      'parentPrompt': 'Ask a trusted adult how water freezes.',
      'source': 'ai'
    }));
    await request.response.close();
    expect((await replyFuture).source, 'ai');
  });
}
