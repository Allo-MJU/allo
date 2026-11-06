import 'package:firebase_core/firebase_core.dart';

/// 빌드 시 주입한 Firebase 설정. 값은 로그나 오류 화면에 노출하지 않는다.
class FirebaseConfig {
  const FirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.databaseUrl,
  });

  factory FirebaseConfig.fromEnvironment() => const FirebaseConfig(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId:
            String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        databaseUrl: String.fromEnvironment('FIREBASE_DATABASE_URL'),
      );

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String databaseUrl;

  FirebaseOptions toOptions() {
    if ([apiKey, appId, messagingSenderId, projectId, databaseUrl]
        .any((value) => value.trim().isEmpty)) {
      throw const FormatException('차량 연결 설정이 준비되지 않았어요.');
    }
    final url = Uri.tryParse(databaseUrl.trim());
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        (url.path.isNotEmpty && url.path != '/') ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('차량 연결 설정을 확인해야 해요.');
    }
    return FirebaseOptions(
      apiKey: apiKey.trim(),
      appId: appId.trim(),
      messagingSenderId: messagingSenderId.trim(),
      projectId: projectId.trim(),
      databaseURL: databaseUrl.trim(),
    );
  }
}
