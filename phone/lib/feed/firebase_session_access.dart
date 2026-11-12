import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pairing/pairing_credentials.dart';

abstract interface class FirebaseSessionAccess {
  Future<Map<String, dynamic>> join(PairingCredentials credentials);
}

/// Auth SDK persists the anonymous identity and refreshes ID tokens. The callable
/// SDK attaches that token; the client never writes its own session membership.
class AuthenticatedFirebaseSessionAccess implements FirebaseSessionAccess {
  AuthenticatedFirebaseSessionAccess({
    FirebaseAuth? auth,
    Future<Object?> Function(Map<String, Object?>)? callJoin,
    this.functionsRegion = 'asia-northeast3',
  })  : _authOverride = auth,
        _callJoinOverride = callJoin;

  final FirebaseAuth? _authOverride;
  final Future<Object?> Function(Map<String, Object?>)? _callJoinOverride;
  final String functionsRegion;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  @override
  Future<Map<String, dynamic>> join(PairingCredentials credentials) async {
    try {
      // Never sign out/recreate an identity to work around a denied request.
      final user = _auth.currentUser ??
          (await _auth.signInAnonymously().timeout(const Duration(seconds: 15)))
              .user;
      if (user == null || !user.isAnonymous) {
        throw const PairingException('차량 연결용 기기 인증을 확인해 주세요.');
      }
      final input = <String, Object?>{
        'sessionId': credentials.sessionId,
        'pairCode': credentials.code,
      };
      final Object? reply;
      if (_callJoinOverride != null) {
        reply =
            await _callJoinOverride(input).timeout(const Duration(seconds: 15));
      } else {
        reply = (await FirebaseFunctions.instanceFor(region: functionsRegion)
                .httpsCallable('joinVehicleSession',
                    options: HttpsCallableOptions(
                        timeout: const Duration(seconds: 15)))
                .call<Object?>(input))
            .data;
      }
      if (reply is! Map) {
        throw const PairingException('차량 연결 응답을 확인하지 못했어요. 다시 시도해 주세요.');
      }
      final meta = Map<String, dynamic>.from(reply);
      if (meta['sessionId'] != credentials.sessionId ||
          meta['paired'] != true) {
        throw const PairingException('차량 연결 응답을 확인하지 못했어요. 다시 시도해 주세요.');
      }
      credentials.validateMeta(meta, now: DateTime.now());
      return meta;
    } on FirebaseAuthException {
      throw const RetryablePairingException(
          '기기 인증에 실패했어요. 연결 설정과 네트워크를 확인해 주세요.');
    } on FirebaseFunctionsException catch (error) {
      // Do not surface raw server error messages/details or credentials.
      final message = switch (error.code) {
        'already-exists' => '다른 폰에 연결된 차량이에요. 차량에서 새 연결을 시작해 주세요.',
        'resource-exhausted' => '연결 시도가 너무 많아요. 잠시 후 차량의 새 코드를 확인해 주세요.',
        'deadline-exceeded' ||
        'unavailable' =>
          '차량 연결을 확인하지 못했어요. 네트워크를 확인한 뒤 다시 시도해 주세요.',
        'failed-precondition' ||
        'not-found' =>
          '차량 연결 시간이 지났거나 종료됐어요. 차량의 새 QR을 확인해 주세요.',
        'permission-denied' ||
        'invalid-argument' =>
          '연결 코드나 차량 연결 권한을 확인해 주세요.',
        'unauthenticated' => '기기 인증을 확인하지 못했어요. 앱을 다시 실행해 주세요.',
        _ => '차량 연결을 확인하지 못했어요. 다시 시도해 주세요.',
      };
      if (const {
        'already-exists',
        'failed-precondition',
        'not-found',
        'permission-denied',
        'invalid-argument'
      }.contains(error.code)) {
        throw PairingException(message);
      }
      throw RetryablePairingException(message);
    } on TimeoutException {
      throw const RetryablePairingException(
          '연결 응답이 늦어요. 네트워크를 확인한 뒤 다시 시도해 주세요.');
    }
  }
}
