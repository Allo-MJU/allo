// Cross-language integration check. Uses only synthetic input and a test evaluator.
import 'dart:convert';
import 'dart:io';

import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/affinity/egg_demo_api.dart';

Future<void> main(List<String> args) async {
  final first = HttpEggDemoApi(
    baseUri: Uri.parse(args.single),
    token: Platform.environment['SMOKE_ROOM_TOKEN']!,
    allowInsecureLoopback: true,
  );
  final second = HttpEggDemoApi(
    baseUri: Uri.parse(args.single),
    token: Platform.environment['SMOKE_ROOM_TOKEN']!,
    allowInsecureLoopback: true,
  );
  try {
    final round = AffinityRound.start(
      eggId: 'smoke-egg',
      preferredZone: 1,
      deadlineMs: 600000,
    );
    for (var i = 0; i < 17; i++) {
      round.pet(atMs: i * 10000);
    }
    if (round.phase != AffinityPhase.photoRequired || round.score != 50) {
      throw StateError('photo gate');
    }
    final image = base64Decode(Platform.environment['SMOKE_IMAGE']!);
    final receipt = await first.uploadPhoto(
      eggId: round.eggId,
      requestId: 'smoke-photo',
      bytes: image,
      mimeType: 'image/png',
    );
    final recovered = await second.findPhotoForEgg(round.eggId);
    if (recovered?.photoId != receipt.photoId) {
      throw StateError('cross-client receipt');
    }
    final jpeg = await second.downloadPhoto(receipt.photoId);
    if (jpeg.length < 3 || jpeg[0] != 255 || jpeg[1] != 216) {
      throw StateError('JPEG');
    }
    round.confirmPhoto(
      atMs: 160000,
      eggId: receipt.eggId,
      photoId: receipt.photoId,
    );
    if (round.score != 65) throw StateError('photo reward');
    final verdict = await first.evaluate(
      eggId: round.eggId,
      requestId: 'smoke-utterance',
      text: '바다에 가서 놀고 싶어',
    );
    round.speak(atMs: 160000, requestId: 'smoke-utterance', sentiment: verdict);
    round.advanceTo(220000);
    if (round.score != 77) throw StateError('speech ramp');
    for (var i = 0; i < 8; i++) {
      round.pet(atMs: 220000 + i * 10000);
    }
    if (round.phase != AffinityPhase.hatched || round.score != 100) {
      throw StateError('hatch');
    }
    final catalog = jsonDecode(
      await File('assets/data/companion_learning.json').readAsString(),
    ) as Map<String, dynamic>;
    final stories = catalog['stories'] as List;
    for (final story in stories) {
      final request = <String, dynamic>{
        'requestId': 'learning-${story['speciesId']}',
        'creatureId': 'smoke-friend',
        'speciesId': story['speciesId'],
        'storyId': story['storyId'],
        'version': story['version'],
        'sceneId': story['firstSceneId'],
        'text': '네 이야기를 들려줘.',
        'history': <Object>[],
        'allowParentPrompt': false,
      };
      final answer = await first.companionChat(request);
      for (final key in [
        'requestId',
        'creatureId',
        'speciesId',
        'storyId',
        'version',
        'sceneId',
      ]) {
        if (answer[key] != request[key]) {
          throw StateError('learning context mismatch');
        }
      }
      if (answer['text'] != '작은 씨앗을 함께 관찰해 보자.' ||
          answer['parentPromptUsed'] != false) {
        throw StateError('learning response');
      }
      Future<Map<String, dynamic>> turn(String action, String sceneId) =>
          first.companionTurn({
            ...request,
            'requestId': 'turn-${story['speciesId']}-$action',
            'sceneId': sceneId,
            'action': action,
            'text': '',
          });
      final invited = await turn('invite', story['firstSceneId'] as String);
      if (invited['mode'] != 'menu' || invited['text'] != '나한테 궁금한 게 있는 거야?') {
        throw StateError('server invitation');
      }
      final listened = await turn('listen', invited['sceneId'] as String);
      if (listened['mode'] != 'story' ||
          (listened['text'] as String).isEmpty ||
          listened['canNext'] != true) {
        throw StateError('server authored story');
      }
      final next = await turn('next', listened['sceneId'] as String);
      if (next['sceneId'] == listened['sceneId'] || next['mode'] != 'story') {
        throw StateError('server controls next scene');
      }
      final repeated = await turn('repeat', next['sceneId'] as String);
      if (repeated['sceneId'] != next['sceneId'] ||
          repeated['text'] != next['text']) {
        throw StateError('server repeat');
      }
    }
    stdout.writeln(
      jsonEncode({
        'crossLanguageHttp': true,
        'crossClientPhotoRecovery': true,
        'photoGateReward': 65,
        'rampedScore': 77,
        'hatched': true,
        'companionStoriesChecked': stories.length,
        'serverOwnedTurnsChecked': stories.length * 4,
        'provider': 'injected synthetic evaluator, no live model',
      }),
    );
  } finally {
    first.close();
    second.close();
  }
}
