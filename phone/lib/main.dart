import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'affinity/egg_demo_api.dart';
import 'config/firebase_config.dart';
import 'feed/fake_feed.dart';
import 'feed/firebase_feed.dart';
import 'feed/vehicle_feed.dart';
import 'widgets/window_view.dart';

/// --dart-define=FEED=fake → 차 없이 가짜 신호로 실행 (기본값).
/// Firebase 설정은 --dart-define-from-file=config/firebase.local.json 으로 주입.
const _feedKind = String.fromEnvironment('FEED', defaultValue: 'fake');
EggDemoApi? configuredEggApi() {
  const url = String.fromEnvironment('ALLO_DEMO_API_URL');
  const token = String.fromEnvironment('ALLO_DEMO_TOKEN');
  if (url.isEmpty || token.isEmpty) return null;
  try {
    return HttpEggDemoApi.fromEnvironment();
  } on EggDemoApiException {
    return null;
  }
}

const _scenario =
    String.fromEnvironment('SCENARIO', defaultValue: 'rainy_highway');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 앱 전체 가로 고정 (탐험 게임 설계 5절)
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  // 차 안 화면을 꽉 채우려고 상태 표시줄·내비게이션 바를 숨긴다 (가장자리를 쓸면 잠깐 나온다)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // 창밖 스크롤은 실제 실행에서만 켠다. 위젯 테스트는 정지 장면으로 본다.
  runApp(SceneMotion(enabled: true, child: await createApp()));
}

/// 초기화 성공 전에는 Firebase feed를 만들지 않는다.
/// 초기화 함수와 feed 팩토리는 플랫폼 연결 없이 시작 흐름을 검증할 때 주입한다.
Future<Widget> createApp({
  String feedKind = _feedKind,
  String scenario = _scenario,
  FirebaseConfig? config,
  Future<void> Function(FirebaseOptions)? initializeFirebase,
  VehicleFeed Function()? createFirebaseFeed,
}) async {
  if (feedKind == 'fake') {
    return AlloApp(
        feed: FakeVehicleFeed(scenario: FakeScenario.byName(scenario)),
        eggApi: configuredEggApi());
  }
  if (feedKind != 'firebase') {
    return const ConnectionSetupApp(message: '실행 설정을 확인해야 해요.');
  }

  final resolvedConfig = config ?? FirebaseConfig.fromEnvironment();
  final FirebaseOptions options;
  try {
    options = resolvedConfig.toOptions();
  } on FormatException catch (error) {
    return ConnectionSetupApp(message: error.message);
  }

  try {
    if (initializeFirebase != null) {
      await initializeFirebase(options);
    } else {
      await Firebase.initializeApp(options: options);
    }
    return AlloApp(
        eggApi: configuredEggApi(),
        feed: createFirebaseFeed?.call() ??
            FirebaseVehicleFeed(
                functionsRegion: resolvedConfig.functionsRegion));
  } catch (_) {
    // SDK 오류에는 설정 값이 포함될 수 있어 사용자 화면에 원문을 표시하지 않는다.
    return const ConnectionSetupApp(
        message: '차량 연결을 준비하지 못했어요. 앱을 다시 실행해 주세요.');
  }
}

class ConnectionSetupApp extends StatefulWidget {
  const ConnectionSetupApp({super.key, required this.message});
  final String message;

  @override
  State<ConnectionSetupApp> createState() => _ConnectionSetupAppState();
}

class _ConnectionSetupAppState extends State<ConnectionSetupApp> {
  bool _tryFake = false;
  late final _fakeEggApi = configuredEggApi();
  late final _fakeFeed = FakeVehicleFeed(scenario: FakeScenario.rainyHighway);

  @override
  Widget build(BuildContext context) {
    if (_tryFake) {
      return AlloApp(feed: _fakeFeed, eggApi: _fakeEggApi);
    }
    return MaterialApp(
      title: '알로',
      theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4FB3A9), useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('알로')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_off, size: 64),
                  const SizedBox(height: 24),
                  Text(widget.message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  const Text('차 없이 체험 모드로 먼저 만나볼 수 있어요.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => setState(() => _tryFake = true),
                    child: const Text('체험 모드 시작'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
