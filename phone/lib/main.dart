import 'package:flutter/material.dart';

import 'app.dart';
import 'feed/fake_feed.dart';
import 'feed/firebase_feed.dart';
import 'feed/vehicle_feed.dart';

/// --dart-define=FEED=fake  → 차 없이 가짜 신호로 실행 (기본값은 fake)
/// --dart-define=SCENARIO=rainy_highway|tunnel_rough|clear|rough  (fake 일 때)
const _feedKind = String.fromEnvironment('FEED', defaultValue: 'fake');
const _scenario =
    String.fromEnvironment('SCENARIO', defaultValue: 'rainy_highway');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final VehicleFeed feed;
  if (_feedKind == 'fake') {
    feed = FakeVehicleFeed(scenario: FakeScenario.byName(_scenario));
  } else {
    // `flutterfire configure` 로 lib/firebase_options.dart 를 생성한 뒤 아래 주석을 푼다 (git 미추적).
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    feed = FirebaseVehicleFeed();
  }

  runApp(AlloApp(feed: feed));
}
