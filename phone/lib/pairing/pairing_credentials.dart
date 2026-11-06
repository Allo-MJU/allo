class PairingException implements Exception {
  const PairingException(this.message);
  final String message;
}

class SessionEndedException extends PairingException {
  const SessionEndedException() : super('주행이 끝났어요. 차량의 새 QR을 스캔해 주세요.');
}

/// 차량 QR 계약: allo://pair?sid={UUID}&code={6자리}.
class PairingCredentials {
  const PairingCredentials._(this.sessionId, this.code);
  final String sessionId;
  final String code;

  factory PairingCredentials.parseFields(String sid, String code) {
    final session = sid.trim();
    final digits = code.trim();
    if (!RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(session) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(digits)) {
      throw const PairingException('차량의 세션 ID와 6자리 코드를 확인해 주세요.');
    }
    return PairingCredentials._(session.toLowerCase(), digits);
  }

  factory PairingCredentials.fromQr(String raw) {
    try {
      final uri = Uri.tryParse(raw.trim());
      if (uri == null ||
          uri.scheme != 'allo' ||
          uri.host != 'pair' ||
          uri.path.isNotEmpty ||
          uri.hasFragment ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.queryParametersAll.length != 2 ||
          uri.queryParametersAll['sid']?.length != 1 ||
          uri.queryParametersAll['code']?.length != 1) {
        throw const PairingException('알로 차량 화면의 QR을 스캔해 주세요.');
      }
      return PairingCredentials.parseFields(
          uri.queryParameters['sid']!, uri.queryParameters['code']!);
    } on FormatException {
      throw const PairingException('알로 차량 화면의 QR을 스캔해 주세요.');
    }
  }

  void validateMeta(Map<String, dynamic>? meta, {required DateTime now}) {
    if (meta == null) {
      throw const PairingException('세션이 없어요. 차량의 새 QR을 확인해 주세요.');
    }
    final createdAt = meta['createdAt'];
    if (createdAt is! num ||
        !createdAt.isFinite ||
        now.millisecondsSinceEpoch - createdAt >=
            const Duration(hours: 24).inMilliseconds) {
      throw const PairingException('연결 시간이 지났어요. 차량의 새 QR을 확인해 주세요.');
    }
    if (meta['pairCode'] != code) {
      throw const PairingException('코드가 달라요. 차량의 코드를 확인해 주세요.');
    }
  }
}
