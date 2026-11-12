import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'base_camp/base_camp_controller.dart';
import 'base_camp/base_camp_store.dart';
import 'feed/firebase_feed.dart';
import 'feed/firebase_session_access.dart';
import 'game/game_controller.dart';
import 'local_firebase/stores.dart';

/// Debug-only Firebase Emulator Suite transport, with no live project or synthetic API responses.
Future<void> main() async {
  if (!kDebugMode) throw UnsupportedError('Local Firebase is debug only');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('로컬 Firebase 연결 준비 중')))));
  try {
    await startLocalFirebase().timeout(const Duration(seconds: 25));
  } catch (error) {
    debugPrint('Local Firebase startup failed: ${error.runtimeType}');
    runApp(const MaterialApp(
        home: Scaffold(
            body: Center(
                child: Text('로컬 Firebase 준비에 실패했어요. 에뮬레이터 서버를 확인해 주세요.')))));
  }
}

Future<void> startLocalFirebase() async {
  debugPrint('Local Firebase startup: initialize');
  const project = 'demo-allo-auth';
  const region = 'asia-northeast3';
  const host = '10.0.2.2';
  final app = await Firebase.initializeApp(
    name: 'allo-local-firebase',
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1234567890:android:abcdef123456',
      messagingSenderId: '1234567890',
      projectId: project,
      databaseURL: 'https://demo-allo-auth-default-rtdb.firebaseio.com',
    ),
  );
  debugPrint('Local Firebase startup: auth');
  final auth = FirebaseAuth.instanceFor(app: app);
  await auth.useAuthEmulator(host, 9099);
  debugPrint('Local Firebase startup: database');
  final db = FirebaseDatabase.instanceFor(app: app);
  db.useDatabaseEmulator(host, 9000);
  debugPrint('Local Firebase startup: functions');
  final feed = FirebaseVehicleFeed(
      db: db,
      sessionAccess: AuthenticatedFirebaseSessionAccess(
        auth: auth,
        functionsRegion: region,
        // The Android callable SDK also initializes Firebase IID, which has no
        // local emulator. Use the callable wire protocol with the same Auth
        // identity here; production keeps the normal callable SDK.
        callJoin: (data) async {
          final token = await auth.currentUser!.getIdToken();
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 10);
          try {
            final request = await client.postUrl(Uri.parse(
                'http://$host:5001/$project/$region/joinVehicleSession'));
            request.headers.contentType = ContentType.json;
            request.headers
                .set(HttpHeaders.authorizationHeader, 'Bearer $token');
            request.write(jsonEncode({'data': data}));
            final response = await request.close();
            final body =
                jsonDecode(await utf8.decoder.bind(response).join()) as Map;
            if (body['error'] case final Map error) {
              final status = (error['status'] as String? ?? 'UNKNOWN')
                  .toLowerCase()
                  .replaceAll('_', '-');
              throw FirebaseFunctionsException(
                  code: status, message: 'Local callable failed');
            }
            if (response.statusCode != 200 || !body.containsKey('result')) {
              throw FirebaseFunctionsException(
                  code: 'internal', message: 'Invalid local callable response');
            }
            return body['result'];
          } finally {
            client.close(force: true);
          }
        },
      ));
  final stores = LocalFirebaseStores();
  await stores.seedSamples();
  final camp = BaseCampController(
      store: SharedPreferencesBaseCampStore(profile: 'local-firebase'),
      dex: stores.dex);
  await camp.load();
  final controller = GameController(
      baseCamp: camp,
      feed: feed,
      dex: stores.dex,
      fishingStore: stores.fishing,
      pairingStore: stores.pairing);
  debugPrint('Local Firebase startup: species');
  await controller.loadSpecies();
  debugPrint('Local Firebase startup: ready');
  runApp(_CampOwner(
      camp: camp,
      child: AlloApp(
          feed: feed,
          createController: () => controller,
          frameBuilder: (context, c, child) => Scaffold(
                  body: SafeArea(
                      child: Column(children: [
                const Material(
                    color: Color(0xffffe6a1),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Text('로컬 Firebase 검증 · 샘플 획득 기록 · 실제 여행 기록 아님'),
                    )),
                Expanded(child: child),
              ]))))));
}

class _CampOwner extends StatefulWidget {
  const _CampOwner({required this.camp, required this.child});
  final BaseCampController camp;
  final Widget child;
  @override
  State<_CampOwner> createState() => _CampOwnerState();
}

class _CampOwnerState extends State<_CampOwner> {
  @override
  void dispose() {
    widget.camp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
