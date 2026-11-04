import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../feed/vehicle_feed.dart';
import '../feed/fake_feed.dart';
import '../storage/dex_store.dart';
import '../storage/pairing_store.dart';
import '../pairing/pairing_credentials.dart';

/// 한 세션의 게임 상태 머신. 판정은 allo_core 에 위임하고, 결과를 feed.publishGame 으로 차 화면에 보낸다.
class GameController extends ChangeNotifier {
  GameController(
      {required this.feed,
      required this.dex,
      RarityEngine? engine,
      PairingStore? pairingStore})
      : engine = engine ?? const RarityEngine(),
        pairingStore = pairingStore ?? PairingStore();

  final VehicleFeed feed;
  final DexStore dex;
  final PairingStore pairingStore;
  String? pairingNotice;
  bool _restoredPairing = false;
  final RarityEngine engine;

  SpeciesTable? _table;
  StreamSubscription<VehicleState>? _sub;
  HatchTimer? _timer;

  VehicleState? vehicle;
  GameState game =
      GameState(ts: 0, eggTier: EggTier.small, stage: Stage.idle, progress: 0);
  Species? hatched;
  final Set<String> seenTags = {};
  int careCount = 0;
  int lookOutCount = 0;
  int feedCount = 0;
  int playCount = 0;
  String? companionMessage;

  /// 실제 수신된 태그만 사용한다. 지역 정보가 없으면 풍경을 단정하지 않는다.
  (String, String) get lookOutPrompt {
    final tags = vehicle?.envTags ?? const <String>[];
    if (tags.contains('coast')) return ('창밖에 바다가 보이나요?', 'sea');
    if (tags.contains('mountain')) return ('창밖에 산이 보이나요?', 'mountain');
    if (tags.contains('city')) return ('창밖에 건물이 보이나요?', 'building');
    if (tags.contains('rain')) return ('창밖에 빗방울이 보이나요?', 'rain');
    if (tags.contains('tunnel')) return ('터널의 불빛을 찾아볼까요?', 'light');
    if (tags.contains('night')) return ('밤하늘을 살펴볼까요?', 'night');
    return ('창밖에 무엇이 보이나요?', 'window');
  }

  // 동행 반응은 폰 안에서만 유지하며 부화 등급이나 서버 계약을 바꾸지 않는다.
  void feedCompanion() {
    if (game.stage != Stage.hatched) return;
    feedCount++;
    companionMessage = '${hatched?.nameKo ?? "친구"}가 맛있게 먹었어요!';
    notifyListeners();
  }

  void playWithCompanion() {
    if (game.stage != Stage.hatched) return;
    playCount++;
    companionMessage = '${hatched?.nameKo ?? "친구"}가 신나게 뛰어요!';
    notifyListeners();
  }

  bool paired = false;
  bool busy = false;
  bool _disposed = false;
  Future<void> _pendingSave = Future.value();
  Future<void> Function()? _retrySave;
  bool get isFake => feed is FakeVehicleFeed;
  bool get canStart => !busy && (isFake || paired);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _send(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (_) {
      error = '연결이 불안정해요. 잠시 후 다시 시도해 주세요.';
      notifyListeners();
    }
  }

  String? error;

  Future<void> loadSpecies() async {
    _table ??= SpeciesTable.fromJson(
        jsonDecode(await rootBundle.loadString('../data/species.json'))
            as Map<String, dynamic>);
  }

  Future<void> restorePairing() async {
    if (isFake || _restoredPairing || busy || paired) return;
    _restoredPairing = true;
    busy = true;
    notifyListeners();
    try {
      final saved = await pairingStore.read();
      if (_disposed) return;
      if (saved != null) {
        await _connect(saved);
      }
    } on PairingException catch (e) {
      error = e.message;
      try {
        await pairingStore.clear();
      } catch (_) {/* 다음 연결에서 덮어쓴다. */}
    } catch (_) {
      error = '이전 차량에 연결하지 못했어요. 새 QR을 스캔하거나 다시 연결해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _connect(PairingCredentials credentials) async {
    await feed.pair(credentials.sessionId, pairCode: credentials.code);
    if (_disposed) return;
    paired = true;
    try {
      await pairingStore.save(credentials);
    } catch (_) {
      pairingNotice = '연결됐지만 자동 재연결 정보를 저장하지 못했어요. 다음에는 QR을 다시 스캔해 주세요.';
    }
  }

  Future<void> pair(String sessionId, {String? pairCode}) async {
    if (busy) return;
    busy = true;
    paired = false;
    error = null;
    pairingNotice = null;
    notifyListeners();
    try {
      if (isFake) {
        await feed.pair(sessionId, pairCode: pairCode);
        paired = true;
      } else {
        await _connect(
            PairingCredentials.parseFields(sessionId, pairCode ?? ''));
      }
    } on PairingException catch (e) {
      error = e.message;
    } catch (_) {
      error = '연결하지 못했어요. 네트워크와 차량의 새 QR을 확인해 주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 알 고르기 → 품기 시작. 이전 주행에서 넘어온 거리는 DexStore 에 있다.
  Future<bool> startIncubating(EggTier tier) async {
    if (!canStart) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!await endSession()) return false;
      await loadSpecies();
      final carried = await dex.carriedDistance(tier);
      _timer = HatchTimer(eggTier: tier, carriedM: carried);
      vehicle = null;
      seenTags.clear();
      careCount = 0;
      lookOutCount = 0;
      feedCount = 0;
      playCount = 0;
      companionMessage = null;
      hatched = null;
      game = GameState(
          ts: _now,
          eggTier: tier,
          stage: Stage.incubating,
          progress: 0,
          hatchAtM: _timer!.hatchAtM);
      await _sub?.cancel();
      _sub = feed.watch().listen(_onVehicle, onError: (Object _) {
        error = '차량 신호를 받지 못했어요. 연결을 확인해 주세요.';
        notifyListeners();
      });
      notifyListeners();
      unawaited(_send(() => feed.publishGame(game)));
      return true;
    } catch (_) {
      error = '시작하지 못했어요. 다시 시도해 주세요.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onVehicle(VehicleState v) {
    vehicle = v;
    seenTags.addAll(v.envTags);
    final t = _timer;
    if (t == null || game.stage != Stage.incubating) {
      notifyListeners();
      return;
    }
    final p = t.update(v);
    game = GameState(
        ts: _now,
        eggTier: game.eggTier,
        stage: Stage.incubating,
        progress: p,
        careCount: careCount,
        lookOutCount: lookOutCount,
        hatchAtM: t.hatchAtM,
        hatchAtSec: t.hatchAtSec);
    if (t.shouldHatch(p)) _hatch(v);
    notifyListeners();
    unawaited(_send(() => feed.publishGame(game)));
  }

  void _hatch(VehicleState v) {
    final r = engine.judge(
        seenTags: seenTags,
        harshBrake: v.harshBrake,
        harshSteer: v.harshSteer,
        careCount: careCount,
        capabilities: v.capabilities);
    final s = _table!.pick(r, seenTags);
    hatched = s;
    game = game.copyWith(
        stage: Stage.hatched,
        progress: 1,
        speciesId: s.id,
        attribute: s.attribute,
        tier: r.tier);
    unawaited(_send(() => feed
        .emitEvent('hatched', payload: {'speciesId': s.id, 'tier': r.tier})));
    final region = seenTags
        .where((t) => const {'coast', 'mountain', 'city'}.contains(t))
        .firstOrNull;
    final entry = DexEntry(
      speciesId: s.id,
      obtainedAt: DateTime.now(),
      envTags: seenTags.toList(),
      regionTag: region,
      tier: r.tier,
    );
    final eggTier = game.eggTier;
    _retrySave = () => _saveHatch(entry, eggTier);
    _pendingSave = _trySave();
  }

  Future<void> _trySave() async {
    try {
      await _retrySave?.call();
      _retrySave = null;
    } catch (_) {
      error = '도감을 저장하지 못했어요. 도착 버튼으로 다시 시도해 주세요.';
      notifyListeners();
    }
  }

  Future<void> _saveHatch(DexEntry entry, EggTier tier) async {
    await dex.add(entry);
    await dex.setCarriedDistance(tier, 0);
  }

  void care() {
    if (game.stage != Stage.incubating) return;
    careCount++;
    game = game.copyWith(ts: _now, careCount: careCount);
    unawaited(_send(() => feed.publishGame(game)));
    notifyListeners();
  }

  void lookOut() {
    if (game.stage != Stage.hatched) return;
    lookOutCount++;
    game = game.copyWith(lookOutCount: lookOutCount);
    unawaited(_send(() => feed.emitEvent('lookOutPrompt')));
    unawaited(_send(() => feed.publishGame(game)));
    notifyListeners();
  }

  /// 도착(기어 P) 또는 앱 종료. 부화 전이면 거리를 다음 주행으로 넘긴다.
  Future<bool> endSession() async {
    try {
      await _sub?.cancel();
      _sub = null;
      await _pendingSave;
      if (_retrySave != null) await _trySave();
      if (_retrySave != null) return false;
      final t = _timer;
      if (t != null && game.stage == Stage.incubating) {
        await dex.setCarriedDistance(game.eggTier, t.carryOver(hatched: false));
      }
      _timer = null;
      return true;
    } catch (_) {
      error = '저장하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    feed.dispose();
    super.dispose();
  }
}
