// Cross-language integration check. Uses only synthetic input and a test evaluator.
import 'dart:convert';
import 'dart:io';
import 'package:allo_core/allo_core.dart';
import 'package:allo_phone/affinity/egg_demo_api.dart';

Future<void> main(List<String> args) async {
  final first = HttpEggDemoApi(
      baseUri: Uri.parse(args.single),
      token: Platform.environment['SMOKE_ROOM_TOKEN']!,
      allowInsecureLoopback: true);
  final second = HttpEggDemoApi(
      baseUri: Uri.parse(args.single),
      token: Platform.environment['SMOKE_ROOM_TOKEN']!,
      allowInsecureLoopback: true);
  try {
    final round = AffinityRound.start(
        eggId: 'smoke-egg', preferredZone: 1, deadlineMs: 600000);
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
        mimeType: 'image/png');
    final recovered = await second.findPhotoForEgg(round.eggId);
    if (recovered?.photoId != receipt.photoId) {
      throw StateError('cross-client receipt');
    }
    final jpeg = await second.downloadPhoto(receipt.photoId);
    if (jpeg.length < 3 || jpeg[0] != 255 || jpeg[1] != 216) {
      throw StateError('JPEG');
    }
    round.confirmPhoto(
        atMs: 160000, eggId: receipt.eggId, photoId: receipt.photoId);
    if (round.score != 65) throw StateError('photo reward');
    final verdict = await first.evaluate(
        eggId: round.eggId, requestId: 'smoke-utterance', text: '바다에 가서 놀고 싶어');
    round.speak(atMs: 160000, requestId: 'smoke-utterance', sentiment: verdict);
    round.advanceTo(220000);
    if (round.score != 77) throw StateError('speech ramp');
    for (var i = 0; i < 8; i++) {
      round.pet(atMs: 220000 + i * 10000);
    }
    if (round.phase != AffinityPhase.hatched || round.score != 100) {
      throw StateError('hatch');
    }
    stdout.writeln(jsonEncode({
      'crossLanguageHttp': true,
      'crossClientPhotoRecovery': true,
      'photoGateReward': 65,
      'rampedScore': 77,
      'hatched': true,
      'provider': 'injected synthetic evaluator, no live model'
    }));
  } finally {
    first.close();
    second.close();
  }
}
