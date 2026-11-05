import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../pairing/pairing_credentials.dart';

/// 재연결용 식별자만 기기에 보관. 읽을 때마다 서버에서 유효성을 다시 확인한다.
class PairingStore {
  static const _key = 'pairing.session.v1';

  Future<PairingCredentials?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return PairingCredentials.parseFields(
          data['sid'] as String, data['code'] as String);
    } catch (_) {
      await prefs.remove(_key);
      return null;
    }
  }

  Future<void> save(PairingCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(_key,
        jsonEncode({'sid': credentials.sessionId, 'code': credentials.code}));
    if (!saved) throw StateError('pairing save failed');
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final removed = await prefs.remove(_key);
    if (!removed) throw StateError('pairing clear failed');
  }
}
