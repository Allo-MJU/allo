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
      PairingStore? pairingStore,
      int Function()? monotonicMs})
      : engine = engine ?? const RarityEngine(),
        pairingStore = pairingStore ?? PairingStore(),
        _monotonicMs = monotonicMs {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();
  final int Function()? _monotonicMs;
  int get activeClockMs =>
      _monotonicMs?.call() ?? _stopwatch.elapsedMilliseconds;
  bool _appActive = true;
  int? _clockAt;
  int _elapsedMs = 0;
  int? _hatchSec;
  int? _companionSec;
  bool _repeats = false;
  bool _modeSelected = false;
  int _roundNumber = 0;
  String? _eggId;
  int _brakeOffset = 0;
  int _steerOffset = 0;
  int _brakeBaseline = 0;
  int _steerBaseline = 0;
  bool _needsCounterBaseline = true;
  int? _lastVehicleTs;
  DexEntry? _pendingEntry;
  bool _savingHatch = false;
  bool _lifecycleCheckpoint = false;
  String? get eggId => _eggId;

  final VehicleFeed feed;
  final DexStore dex;
  final PairingStore pairingStore;
  String? pairingNotice;
  bool _restoredPairing = false;
  final RarityEngine engine;

  SpeciesTable? _table;
  StreamSubscription<VehicleState>? _sub;
  StreamSubscription<Map<String, Object?>>? _eventsSub;
  int _connection = 0;
  bool _remoteEnded = false;
  bool _remoteSaved = false;
  bool _finalSnapshotRead = false;
  String? _endedSessionId;
  Future<bool>? _closing;
  Future<void> _pairingSave = Future.value();
  HatchTimer? _timer;
  String? _sessionId;
  String? _activeSessionId;
  Map<String, double> _sessionDistances = {};
  double _distanceBaseline = 0;
  double _lastDistance = 0;
  bool _needsLegacyBaseline = false;

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
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
    feedCount++;
    companionMessage = '${hatched?.nameKo ?? "친구"}가 맛있게 먹었어요!';
    notifyListeners();
  }

  void playWithCompanion() {
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
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
  bool get sessionEnded => _remoteEnded;
  bool get sessionSaved => _remoteSaved;
  bool get endingSession => _closing != null;
  bool get canStart =>
      !busy && !sessionEnded && !endingSession && (isFake || paired);

  void endFakeTrip() {
    final fake = feed;
    if (fake is FakeVehicleFeed && !sessionEnded && !endingSession) {
      fake.endTrip();
    }
  }

  void prepareNextFakeTrip() {
    if (!isFake || !sessionSaved || endingSession) return;
    _remoteEnded = false;
    _remoteSaved = false;
    _finalSnapshotRead = false;
    pairingNotice = null;
    error = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _send(Future<void> Function() operation) async {
    if (_disposed) return;
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
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map<String, dynamic>);
  }

  Future<void> restorePairing() async {
    if (isFake || _restoredPairing || busy || paired || endingSession) return;
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
    if (credentials.sessionId == _endedSessionId) {
      throw const SessionEndedException();
    }
    if (!await endSession()) {
      throw const PairingException('이전 주행을 먼저 저장해 주세요.');
    }
    await _eventsSub?.cancel();
    _eventsSub = null;
    final connection = ++_connection;
    await feed.pair(credentials.sessionId, pairCode: credentials.code);
    if (_disposed || connection != _connection) return;
    _sessionId = credentials.sessionId;
    _remoteEnded = false;
    _remoteSaved = false;
    _finalSnapshotRead = false;
    paired = true;
    _eventsSub = feed.events().listen(
      (event) => _onCarEvent(event, connection),
      onError: (Object _) {
        if (_disposed || connection != _connection) return;
        error = '차량 연결을 확인해 주세요. 종료 신호를 받지 못할 수 있어요.';
        notifyListeners();
      },
    );
    try {
      _pairingSave = pairingStore.save(credentials);
      await _pairingSave;
    } catch (_) {
      pairingNotice = '연결됐지만 자동 재연결 정보를 저장하지 못했어요. 다음에는 QR을 다시 스캔해 주세요.';
    }
  }

  void _onCarEvent(Map<String, Object?> event, int connection) {
    if (_disposed ||
        connection != _connection ||
        sessionEnded ||
        event['by'] != 'car' ||
        event['type'] != 'sessionEnd') {
      return;
    }
    _remoteEnded = true;
    _endedSessionId = _sessionId;
    paired = false;
    unawaited(endSession());
    notifyListeners();
  }

  Future<void> pair(String sessionId, {String? pairCode}) async {
    if (busy || endingSession || (sessionEnded && !sessionSaved)) return;
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
    } on SessionEndedException catch (e) {
      error = e.message;
      try {
        await pairingStore.clear();
      } catch (_) {
        error = '${e.message} 이전 연결 정보를 지우지 못했어요. 다시 시도해 주세요.';
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
      final saved = await dex.incubationProgress(tier);
      if (_disposed || sessionEnded || (!isFake && !paired)) return false;
      _activeSessionId = isFake ? null : _sessionId;
      _sessionDistances = Map.of(saved.sessionDistances);
      _distanceBaseline = _sessionDistances[_activeSessionId] ?? 0;
      _lastDistance = _distanceBaseline;
      // 구버전 기록은 어느 세션의 거리인지 모른다. 첫 신호를 기준점으로
      // 삼아 저장분을 보존하되 같은 거리를 다시 계산하지 않는다.
      _needsLegacyBaseline =
          !isFake && saved.sessionDistances.isEmpty && saved.carriedM > 0;
      _timer = HatchTimer(eggTier: tier, carriedM: saved.carriedM);
      vehicle = null;
      _lastVehicleTs = null;
      _resetEgg(tier);
      final round = saved.round;
      if (round != null) _restoreRound(round, tier);
      _clockAt = activeClockMs;
      await _sub?.cancel();
      if (_disposed || sessionEnded || (!isFake && !paired)) return false;
      if (isFake) {
        _eventsSub ??=
            feed.events().listen((event) => _onCarEvent(event, _connection));
      }
      final connection = _connection;
      _sub = feed.watch().listen((v) {
        if (connection == _connection) _onVehicle(v);
      }, onError: (Object _) {
        if (connection != _connection || _disposed) return;
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

  // A new egg never opens another vehicle subscription (Fake.watch resets a trip).
  void _resetEgg(EggTier tier) {
    _roundNumber++;
    _eggId = '$_now-$_roundNumber';
    _elapsedMs = 0;
    _clockAt = activeClockMs;
    _modeSelected = false;
    _hatchSec = null;
    _companionSec = null;
    _repeats = false;
    _needsCounterBaseline = true;
    _brakeOffset = _steerOffset = 0;
    seenTags.clear();
    careCount = lookOutCount = feedCount = playCount = 0;
    companionMessage = null;
    hatched = null;
    game = GameState(
        ts: _now,
        eggTier: tier,
        stage: Stage.incubating,
        progress: 0,
        hatchAtM: _timer?.hatchAtM);
  }

  bool _selectMode(VehicleState v) {
    if (_modeSelected) return true;
    final eta = v.etaSec;
    if (eta != null && eta < 120) {
      game = GameState(
          ts: _now, eggTier: game.eggTier, stage: Stage.idle, progress: 0);
      return false;
    }
    _modeSelected = true;
    _elapsedMs = 0;
    _clockAt = activeClockMs;
    if (eta != null) {
      final round = incubationRound(eta);
      _hatchSec = round.hatchEndSec;
      _companionSec = round.companionEndSec;
      _repeats = round.grantsNextEgg;
    }
    return true;
  }

  void _advanceClock() {
    final now = activeClockMs;
    final previous = _clockAt;
    if (_appActive && previous != null && _modeSelected) {
      _elapsedMs += (now - previous).clamp(0, 1 << 62);
    }
    _clockAt = now;
  }

  void _onVehicle(VehicleState v, {bool finalSnapshot = false}) {
    if (_disposed || (!finalSnapshot && (sessionEnded || !_appActive))) return;
    // Distance snapshots in older feeds may share a ts. Preserve their high-water
    // distance handling, while ETA rounds reject duplicate/out-of-order samples.
    if (_hatchSec != null &&
        !finalSnapshot &&
        _lastVehicleTs != null &&
        v.ts <= _lastVehicleTs!) {
      return;
    }
    _lastVehicleTs = v.ts;
    vehicle = v;
    final t = _timer;
    if (t == null) {
      notifyListeners();
      return;
    }
    _advanceClock();
    if (_needsLegacyBaseline) {
      _distanceBaseline = v.distanceM;
      _needsLegacyBaseline = false;
    }
    if (v.distanceM > _lastDistance) _lastDistance = v.distanceM;
    if (_activeSessionId != null) {
      _sessionDistances[_activeSessionId!] = _lastDistance;
    }
    if (game.stage == Stage.hatched) {
      _grantNextEgg(v, finalSnapshot: finalSnapshot);
      notifyListeners();
      return;
    }
    if (!_selectMode(v)) {
      notifyListeners();
      _publish();
      return;
    }
    if (_needsCounterBaseline) {
      _brakeBaseline = v.harshBrake;
      _steerBaseline = v.harshSteer;
      _needsCounterBaseline = false;
    }
    seenTags.addAll(v.envTags);
    final p = _hatchSec != null
        ? (_elapsedMs / (_hatchSec! * 1000)).clamp(0.0, 1.0)
        : _timer!.update(v.copyWith(
            distanceM: _lastDistance - _distanceBaseline, clearEta: true));
    game = GameState(
        ts: _now,
        eggTier: game.eggTier,
        stage: Stage.incubating,
        progress: p,
        careCount: careCount,
        lookOutCount: lookOutCount,
        hatchAtM: _hatchSec == null ? _timer!.hatchAtM : null,
        hatchAtSec: _hatchSec);
    if (p >= 1) _hatch(v);
    notifyListeners();
    _publish();
  }

  bool _grantNextEgg(VehicleState v, {bool finalSnapshot = false}) {
    if (_disposed ||
        !_appActive ||
        finalSnapshot ||
        sessionEnded ||
        endingSession ||
        game.stage != Stage.hatched ||
        _retrySave != null ||
        _savingHatch ||
        !_repeats ||
        _elapsedMs < _companionSec! * 1000 ||
        (v.etaSec != null && v.etaSec! < 120)) {
      return false;
    }
    _distanceBaseline = _lastDistance;
    _timer = HatchTimer(eggTier: game.eggTier);
    _resetEgg(game.eggTier);
    _selectMode(v);
    _brakeBaseline = v.harshBrake;
    _steerBaseline = v.harshSteer;
    _needsCounterBaseline = false;
    seenTags.addAll(v.envTags);
    game = GameState(
        ts: _now,
        eggTier: game.eggTier,
        stage: Stage.incubating,
        progress: 0,
        hatchAtM: _hatchSec == null ? _timer!.hatchAtM : null,
        hatchAtSec: _hatchSec);
    notifyListeners();
    _publish();
    return true;
  }

  void _publish() => unawaited(_send(() => feed.publishGame(game)));

  void _hatch(VehicleState v) {
    final r = engine.judge(
        seenTags: seenTags,
        harshBrake:
            _brakeOffset + (v.harshBrake - _brakeBaseline).clamp(0, 1 << 30),
        harshSteer:
            _steerOffset + (v.harshSteer - _steerBaseline).clamp(0, 1 << 30),
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
    _pendingEntry = entry;
    final eggTier = game.eggTier;
    _retrySave = () => _saveHatch(entry, eggTier, _checkpoint());
    _pendingSave = _trySave();
  }

  Future<void> _trySave() async {
    if (_savingHatch) return;
    _savingHatch = true;
    try {
      await _retrySave?.call();
      _retrySave = null;
      _pendingEntry = null;
    } catch (_) {
      error = '도감을 저장하지 못했어요. 도착 버튼으로 다시 시도해 주세요.';
      notifyListeners();
    } finally {
      _savingHatch = false;
    }
    // A delayed observation settles exactly one past egg. Once storage succeeds,
    // grant one new egg at now with the latest ETA; never replay absent cycles.
    final latest = vehicle;
    if (_retrySave == null && latest != null) _grantNextEgg(latest);
  }

  Future<void> _saveHatch(
      DexEntry entry, EggTier tier, IncubationProgress checkpoint) async {
    final connection = _connection;
    await dex.add(entry);
    if (_disposed || connection != _connection) return;
    await dex.saveIncubationProgress(
        tier,
        _hatchSec == null
            ? IncubationProgress(sessionDistances: checkpoint.sessionDistances)
            : checkpoint);
  }

  void care() {
    if (game.stage != Stage.incubating || sessionEnded || endingSession) return;
    careCount++;
    game = game.copyWith(ts: _now, careCount: careCount);
    unawaited(_send(() => feed.publishGame(game)));
    notifyListeners();
  }

  void lookOut() {
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
    lookOutCount++;
    game = game.copyWith(lookOutCount: lookOutCount);
    unawaited(_send(() => feed.emitEvent('lookOutPrompt')));
    unawaited(_send(() => feed.publishGame(game)));
    notifyListeners();
  }

  /// 로컬 체크포인트. 차량 종료를 받은 경우에는 최종 신호와 저장을 마친 뒤 연결도 정리한다.
  Future<bool> endSession() {
    if (sessionSaved) return Future.value(true);
    final pending = _closing;
    if (pending != null) return pending;
    final closing = _finishSession(_connection).whenComplete(() {
      _closing = null;
      notifyListeners();
    });
    _closing = closing;
    notifyListeners();
    return closing;
  }

  Future<bool> _finishSession(int connection) async {
    final subscription = _sub;
    subscription?.pause();
    var subscriptionClosed = false;
    try {
      bool closingRemote;
      do {
        closingRemote = sessionEnded;
        if (closingRemote &&
            !_finalSnapshotRead &&
            _timer != null &&
            game.stage == Stage.incubating) {
          final last = await feed.readLatestVehicle();
          if (_disposed || connection != _connection) return false;
          if (last != null) _onVehicle(last, finalSnapshot: true);
          _finalSnapshotRead = true;
        }
        await _pendingSave;
        if (_disposed || connection != _connection) return false;
        if (_retrySave != null) await _trySave();
        if (_disposed || connection != _connection) return false;
        if (_retrySave != null) return false;
        final t = _timer;
        if (t != null &&
            (game.stage != Stage.hatched ||
                _hatchSec != null ||
                _lifecycleCheckpoint)) {
          _advanceClock();
          final checkpoint = _checkpoint();
          await dex.saveIncubationProgress(
              game.eggTier,
              game.stage == Stage.hatched && _hatchSec == null
                  ? IncubationProgress(
                      sessionDistances: checkpoint.sessionDistances)
                  : checkpoint);
          _lifecycleCheckpoint = false;
        }
        if (_disposed || connection != _connection) return false;
        // 저장 성공 후에만 해제한다. 실패하면 기존 구독의 버퍼를 재개한다.
        if (!subscriptionClosed) {
          await subscription?.cancel();
          subscriptionClosed = true;
          _sub = null;
        }
        // 저장 또는 구독 해제 중 차량 종료가 도착하면 최종 신호도 반영한다.
      } while (sessionEnded && !closingRemote);
      if (_disposed || connection != _connection) return false;
      if (sessionEnded) {
        try {
          await _pairingSave;
        } catch (_) {/* 실패한 재연결 정보도 아래에서 제거한다. */}
        if (_disposed || connection != _connection) return false;
        await pairingStore.clear();
        await _eventsSub?.cancel();
        _eventsSub = null;
        if (_disposed || connection != _connection) return false;
        _remoteSaved = true;
        paired = false;
        error = null;
        pairingNotice = '주행이 끝났어요. 다음에는 차량의 새 QR로 연결해 주세요.';
      }
      _timer = null;
      return true;
    } catch (_) {
      error = '저장하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    } finally {
      if (!subscriptionClosed && !_disposed && connection == _connection) {
        subscription?.resume();
      }
    }
  }

  Map<String, dynamic> _roundSnapshot() => {
        'eggId': _eggId,
        'number': _roundNumber,
        'sessionId': _activeSessionId,
        'elapsedMs': _elapsedMs,
        'hatchSec': _hatchSec,
        'companionSec': _companionSec,
        'repeats': _repeats,
        'modeSelected': _modeSelected,
        'game': game.toJson(),
        'tags': seenTags.toList(),
        'brakeOffset': _brakeOffset,
        'steerOffset': _steerOffset,
        'brakeAccumulated': _brakeOffset +
            ((vehicle?.harshBrake ?? _brakeBaseline) - _brakeBaseline)
                .clamp(0, 1 << 30),
        'steerAccumulated': _steerOffset +
            ((vehicle?.harshSteer ?? _steerBaseline) - _steerBaseline)
                .clamp(0, 1 << 30),
        'brakeBaseline': _brakeBaseline,
        'steerBaseline': _steerBaseline,
        'needsCounterBaseline': _needsCounterBaseline,
        'feedCount': feedCount,
        'playCount': playCount,
        if (_pendingEntry != null) 'pendingEntry': _pendingEntry!.toJson(),
      };

  IncubationProgress _checkpoint() => IncubationProgress(
        carriedM: game.stage == Stage.hatched
            ? 0
            : (_timer?.carryOver(hatched: false) ?? 0),
        sessionDistances: Map.of(_sessionDistances),
        round: _roundSnapshot(),
      );

  void _restoreRound(Map<String, dynamic> round, EggTier tier) {
    final g = Map<String, dynamic>.from(round['game'] as Map);
    // A distance-mode arrival retains the existing manual new-egg behavior.
    // Lifecycle snapshots restore distance companions; explicit endSession clears it.
    _eggId = round['eggId'] as String?;
    _roundNumber = (round['number'] as num).toInt();
    _elapsedMs = (round['elapsedMs'] as num).toInt();
    _hatchSec = (round['hatchSec'] as num?)?.toInt();
    _companionSec = (round['companionSec'] as num?)?.toInt();
    _repeats = round['repeats'] == true;
    _modeSelected = round['modeSelected'] == true;
    careCount = (g['careCount'] as num?)?.toInt() ?? 0;
    lookOutCount = (g['lookOutCount'] as num?)?.toInt() ?? 0;
    feedCount = (round['feedCount'] as num?)?.toInt() ?? 0;
    playCount = (round['playCount'] as num?)?.toInt() ?? 0;
    seenTags.addAll((round['tags'] as List).cast<String>());
    _brakeBaseline = (round['brakeBaseline'] as num).toInt();
    _steerBaseline = (round['steerBaseline'] as num).toInt();
    final changedSession = round['sessionId'] != _activeSessionId;
    _needsCounterBaseline =
        round['needsCounterBaseline'] == true || changedSession;
    _brakeOffset =
        (round[changedSession ? 'brakeAccumulated' : 'brakeOffset'] as num?)
                ?.toInt() ??
            0;
    _steerOffset =
        (round[changedSession ? 'steerAccumulated' : 'steerOffset'] as num?)
                ?.toInt() ??
            0;
    final stage = Stage.values.byName(g['stage'] as String);
    final speciesId = g['speciesId'] as String?;
    if (speciesId != null) {
      hatched = _table!.byId(speciesId);
    }
    game = GameState(
        ts: _now,
        eggTier: tier,
        stage: stage,
        progress: (g['progress'] as num).toDouble(),
        speciesId: speciesId,
        attribute: g['attribute'] == null
            ? null
            : Attribute.values.byName(g['attribute'] as String),
        tier: (g['tier'] as num?)?.toInt(),
        careCount: careCount,
        lookOutCount: lookOutCount,
        hatchAtSec: _hatchSec,
        hatchAtM:
            _hatchSec == null && stage != Stage.idle ? _timer!.hatchAtM : null);
    final entry = round['pendingEntry'];
    if (entry != null) {
      _pendingEntry =
          DexEntry.fromJson(Map<String, dynamic>.from(entry as Map));
      final pending = _pendingEntry!;
      _retrySave = () => _saveHatch(pending, tier, _checkpoint());
      _pendingSave = _trySave();
    }
  }

  /// Checkpoints recognized active time, never credits wall-clock suspension.
  /// OS termination before this future finishes can still lose the latest interval.
  Future<bool> setAppActive(bool active) async {
    if (_disposed) return false;
    if (_appActive == active) return true;
    _advanceClock();
    _appActive = active;
    _clockAt = activeClockMs;
    if (active || _timer == null || sessionSaved) return true;
    final connection = _connection;
    try {
      await _pendingSave;
      if (_disposed || connection != _connection) return false;
      await dex.saveIncubationProgress(game.eggTier, _checkpoint());
      _lifecycleCheckpoint = true;
      return true;
    } catch (_) {
      error = '진행을 저장하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
      return false;
    }
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _disposed = true;
    _connection++;
    _sub?.cancel();
    _eventsSub?.cancel();
    feed.dispose();
    super.dispose();
  }
}
