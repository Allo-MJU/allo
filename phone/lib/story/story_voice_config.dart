import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Credentials only cross the in-process bridge; never enter a game snapshot.
class StoryVoiceConfig {
  static const baseUrl = String.fromEnvironment('ALLO_TTS_BASE_URL');

  /// Local voice testing without Firebase sign-in (fake feed demo). Used only in
  /// debug builds against a loopback gateway that sets the same TTS_DEV_TOKEN.
  static const devToken = String.fromEnvironment('ALLO_TTS_DEV_TOKEN');

  static bool _loopbackHttp(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'http' &&
        {'10.0.2.2', '127.0.0.1', 'localhost'}.contains(uri.host);
  }

  static bool validEndpoint(String value, {required bool development}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    return uri.scheme == 'https' ||
        (development &&
            uri.scheme == 'http' &&
            {'10.0.2.2', '127.0.0.1', 'localhost'}.contains(uri.host));
  }

  static Future<Map<String, Object>> reply(String requestId,
      {String endpoint = baseUrl,
      bool development = kDebugMode,
      String localDevToken = devToken,
      Future<String?> Function()? tokenProvider}) async {
    final response = <String, Object>{
      'v': 1,
      'type': 'storyVoiceConfig',
      'requestId': requestId,
      'baseUrl': '',
      'token': '',
      // The release-exported Unity library follows the host build for loopback http.
      'hostDebug': development
    };
    if (!validEndpoint(endpoint, development: development)) return response;
    if (development && localDevToken.isNotEmpty && _loopbackHttp(endpoint)) {
      response['baseUrl'] = endpoint;
      response['token'] = localDevToken;
      return response;
    }
    try {
      // Firebase refreshes an expired/about-to-expire token before returning it.
      final token = await (tokenProvider ??
              () async => FirebaseAuth.instance.currentUser?.getIdToken())()
          .timeout(const Duration(seconds: 4));
      if (token == null || token.isEmpty) return response;
      response['baseUrl'] = endpoint;
      response['token'] = token;
    } catch (_) {
      // Missing Firebase initialization, signed-out users, and auth failures use local WAV.
    }
    return response;
  }
}
