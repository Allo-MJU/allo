import 'package:allo_phone/story/story_voice_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no endpoint means no authentication or cloud request', () async {
    var calls = 0;
    final result = await StoryVoiceConfig.reply('one', endpoint: '',
        tokenProvider: () async {
      calls++;
      return 'secret';
    });
    expect(calls, 0);
    expect(result['token'], '');
  });
  test('release accepts HTTPS only and rejects embedded credentials', () {
    expect(
        StoryVoiceConfig.validEndpoint('https://voice.example.com',
            development: false),
        isTrue);
    expect(
        StoryVoiceConfig.validEndpoint('http://10.0.2.2:8090',
            development: false),
        isFalse);
    expect(
        StoryVoiceConfig.validEndpoint('http://10.0.2.2:8090',
            development: true),
        isTrue);
    expect(
        StoryVoiceConfig.validEndpoint('https://user:pass@voice.example.com',
            development: false),
        isFalse);
    expect(
        StoryVoiceConfig.validEndpoint('https://voice.example.com?token=x',
            development: false),
        isFalse);
  });
  test('fetches valid token per utterance and preserves correlation ID',
      () async {
    var calls = 0;
    Future<String?> token() async => 'token-${++calls}';
    final a = await StoryVoiceConfig.reply('a',
        endpoint: 'https://voice.example.com', tokenProvider: token);
    final b = await StoryVoiceConfig.reply('b',
        endpoint: 'https://voice.example.com', tokenProvider: token);
    expect(a['token'], 'token-1');
    expect(b['token'], 'token-2');
    expect(b['requestId'], 'b');
  });
  test('dev token is used only in debug against a loopback gateway', () async {
    var calls = 0;
    Future<String?> token() async => 'firebase-${++calls}';
    final local = await StoryVoiceConfig.reply('a',
        endpoint: 'http://10.0.2.2:8787',
        development: true,
        localDevToken: 'dev-secret',
        tokenProvider: token);
    expect(local['token'], 'dev-secret');
    expect(calls, 0);
    final remote = await StoryVoiceConfig.reply('b',
        endpoint: 'https://voice.example.com',
        development: true,
        localDevToken: 'dev-secret',
        tokenProvider: token);
    expect(remote['token'], 'firebase-1');
    final release = await StoryVoiceConfig.reply('c',
        endpoint: 'http://10.0.2.2:8787',
        development: false,
        localDevToken: 'dev-secret',
        tokenProvider: token);
    expect(release['token'], '');
    expect(local['hostDebug'], isTrue);
    expect(release['hostDebug'], isFalse);
  });
  test('authentication failure replies unavailable without leaking error',
      () async {
    final result = await StoryVoiceConfig.reply('a',
        endpoint: 'https://voice.example.com',
        tokenProvider: () async => throw StateError('sensitive details'));
    expect(result['token'], '');
    expect(result['baseUrl'], '');
  });
}
