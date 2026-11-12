import 'package:allo_phone/feed/firebase_session_access.dart';
import 'package:allo_phone/feed/firebase_feed.dart';
import 'package:allo_phone/pairing/pairing_credentials.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

const sid = 'b0c260a8-e807-42e9-a119-26119837113b';
final credentials = PairingCredentials.parseFields(sid, '004829');
Map<String, Object?> reply() => {
      'sessionId': sid,
      'pairCode': '004829',
      'paired': true,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'carAppVersion': 'test'
    };

void main() {
  test('기존 익명 사용자는 재로그인하지 않고 callable로만 참여한다', () async {
    final auth = _Auth(_User());
    var calls = 0;
    final access = AuthenticatedFirebaseSessionAccess(
        auth: auth,
        callJoin: (input) async {
          calls++;
          expect(input, {'sessionId': sid, 'pairCode': '004829'});
          return reply();
        });
    await access.join(credentials);
    await access.join(credentials);
    expect(auth.signIns, 0);
    expect(calls, 2);
  });
  test('로그아웃 상태에서만 익명 인증하고 같은 ID를 재사용한다', () async {
    final auth = _Auth(null);
    final access = AuthenticatedFirebaseSessionAccess(
        auth: auth, callJoin: (_) async => reply());
    await access.join(credentials);
    await access.join(credentials);
    expect(auth.signIns, 1);
  });
  test('인증 실패는 callable이나 데이터베이스 접근 전에 중단한다', () async {
    final auth = _Auth(null)..failSignIn = true;
    final access = AuthenticatedFirebaseSessionAccess(
        auth: auth, callJoin: (_) async => fail('must not call'));
    final db = _NoReadsDatabase();
    await expectLater(
        FirebaseVehicleFeed(db: db, sessionAccess: access)
            .pair(sid, pairCode: '004829'),
        throwsA(isA<PairingException>()));
    expect(db.reads, 0);
    expect(auth.signIns, 1);
  });
  for (final code in [
    'permission-denied',
    'already-exists',
    'failed-precondition',
    'resource-exhausted',
    'unauthenticated'
  ]) {
    test('$code 서버 거부 후 데이터 읽기·쓰기를 하지 않으며 계정을 바꾸지 않는다', () async {
      final auth = _Auth(_User());
      final access = AuthenticatedFirebaseSessionAccess(
          auth: auth,
          callJoin: (_) async {
            throw FirebaseFunctionsException(
                code: code, message: 'secret server detail');
          });
      final db = _NoReadsDatabase();
      final feed = FirebaseVehicleFeed(db: db, sessionAccess: access);
      await expectLater(
          feed.pair(sid, pairCode: '004829'),
          throwsA(isA<PairingException>().having(
              (e) => e.message, 'sanitized', isNot(contains('secret')))));
      expect(db.reads, 0);
      expect(auth.signIns, 0);
    });
  }
  for (final result in [
    null,
    {'sessionId': 'other', 'paired': true},
    {...reply(), 'paired': false}
  ]) {
    test('일치하지 않는 서버 응답은 연결 성공이 아니다: $result', () async {
      final access = AuthenticatedFirebaseSessionAccess(
          auth: _Auth(_User()), callJoin: (_) async => result);
      await expectLater(
          access.join(credentials), throwsA(isA<PairingException>()));
    });
  }
  test('기존 다른 인증 방식 계정을 임의 로그아웃하지 않는다', () async {
    final auth = _Auth(_User(anonymous: false));
    final access = AuthenticatedFirebaseSessionAccess(
        auth: auth, callJoin: (_) async => fail('must not call'));
    await expectLater(
        access.join(credentials), throwsA(isA<PairingException>()));
    expect(auth.signIns, 0);
  });
}

class _Auth implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  User? currentUser;
  int signIns = 0;
  bool failSignIn = false;
  @override
  Future<UserCredential> signInAnonymously() async {
    signIns++;
    if (failSignIn) {
      throw FirebaseAuthException(
          code: 'network-request-failed', message: 'sensitive');
    }
    currentUser = _User();
    return _Credential(currentUser!);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _User implements User {
  _User({bool anonymous = true}) : isAnonymous = anonymous;
  @override
  final bool isAnonymous;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Credential implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoReadsDatabase implements FirebaseDatabase {
  int reads = 0;
  @override
  DatabaseReference ref([String? path]) => _NoReadsReference(this);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoReadsReference implements DatabaseReference {
  _NoReadsReference(this.db);
  final _NoReadsDatabase db;
  @override
  DatabaseReference child(String path) => this;
  @override
  Future<DataSnapshot> get() {
    db.reads++;
    throw StateError('must not read');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
