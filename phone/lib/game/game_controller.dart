import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../affinity/egg_demo_api.dart';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../feed/vehicle_feed.dart';
import '../base_camp/base_camp_controller.dart';
import '../base_camp/camp_vehicle_snapshot.dart';
import '../fishing/fishing_controller.dart';
import '../fishing/fishing_store.dart';
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
      int Function()? monotonicMs,
      FishingStore? fishingStore,
      this.baseCamp,
      this.eggApi,
      Random? affinityRandom})
      : engine = engine ?? const RarityEngine(),
        pairingStore = pairingStore ?? PairingStore(),
        _affinityRandom = affinityRandom ?? Random.secure(),
        _monotonicMs = monotonicMs {
    _stopwatch.start();
    baseCamp?.addListener(_onCampChanged);
    fishing = FishingController(
      store: fishingStore,
      clockMs: () => _monotonicMs?.call() ?? _stopwatch.elapsedMilliseconds,
      onChanged: _onFishingChanged,
    );
  }

  final BaseCampController? baseCamp;
  String? _campDriveSessionId;
  int? _campDriveConnection;
  String? _lastCampDisplay;

  void _onCampChanged() {
    if (_disposed) return;
    final camp = baseCamp;
    if (camp == null || !camp.ready) return;
    // A successful retry can arrive after pairing completed without a camp.
    // Restore observation before the display-signature early return.
    if (paired &&
        _sessionId?.isNotEmpty == true &&
        !sessionEnded &&
        !endingSession &&
        fishing.initialized) {
      if (_activateCampForTrip(camp)) {
        _ensureCompanionVehicleSubscription();
      }
    }
    final signature = jsonEncode(campVehicleSnapshot(camp.state));
    if (signature == _lastCampDisplay) return;
    _lastCampDisplay = signature;
    if (paired && !sessionEnded && !endingSession && fishing.initialized) {
      _publish();
    }
    notifyListeners();
  }

  Future<void> _prepareCampForTrip() async {
    final camp = baseCamp;
    if (camp == null) return;
    final connection = _connection;
    final session = _sessionId;
    if (!camp.ready && !await camp.load()) return;
    if (_disposed ||
        connection != _connection ||
        session != _sessionId ||
        sessionEnded) {
      return;
    }
    _activateCampForTrip(camp);
  }

  bool _activateCampForTrip(BaseCampController camp) {
    final id = isFake
        ? (_campDriveSessionId ?? 'fake-$_now-${identityHashCode(this)}')
        : _sessionId;
    if (id == null || id.isEmpty) return false;
    // Camp mutations notify after every saved sample. Reset only for a new
    // trip/connection, otherwise those notifications would discard distance.
    if (_campDriveSessionId == id && _campDriveConnection == _connection) {
      return false;
    }
    _campDriveSessionId = id;
    _campDriveConnection = _connection;
    camp.beginDrivingSession(id);
    return true;
  }

  late final FishingController fishing;

  void _onFishingChanged() {
    if (_disposed) return;
    if (fishing.error != null) error = fishing.error;
    if (paired && !busy && !sessionEnded && !endingSession) {
      if (fishing.initialized && fishing.selectedSpeciesId != null) {
        _ensureCompanionVehicleSubscription();
      }
      _publish();
    }
    notifyListeners();
  }

  /// Selection is only from this phone's persisted collection, never a species ID alone.
  Future<bool> selectCarCompanion(DexEntry entry) async {
    if (!paired || sessionEnded || endingSession || busy) return false;
    final connection = _connection;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final entries = await dex.all();
      if (_disposed || connection != _connection || !paired || sessionEnded) {
        return false;
      }
      if (!entries.any((owned) =>
          jsonEncode(owned.toJson()) == jsonEncode(entry.toJson()))) {
        error = '이 폰의 도감에 있는 친구를 선택해 주세요.';
        return false;
      }
      await fishing.select(entry);
      if (_disposed ||
          connection != _connection ||
          !paired ||
          sessionEnded ||
          endingSession) {
        return false;
      }
      if (fishing.error != null) {
        error = fishing.error;
        return false;
      }
      _ensureCompanionVehicleSubscription();
      _publish();
      return true;
    } catch (_) {
      error = '친구 선택을 저장하지 못했어요. 다시 확인해 주세요.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _ensureCompanionVehicleSubscription() {
    if (_sub != null || !paired || sessionEnded || _disposed) return;
    final connection = _connection;
    _sub = feed.watch().listen((v) {
      if (connection == _connection) _onVehicle(v);
    }, onError: (Object _) {
      if (_disposed || connection != _connection) return;
      fishing.observePresence(null);
      if (_campDriveSessionId != null) {
        baseCamp?.beginDrivingSession(_campDriveSessionId!);
      }
      error = '차량 신호를 받지 못했어요. 연결을 확인해 주세요.';
      notifyListeners();
    });
  }

  final EggDemoApi? eggApi;
  final Random _affinityRandom;
  AffinityRound? _affinity;
  AffinityRound? get affinityRound => _affinity;

  /// Selected mode remains visible while awaiting the first vehicle sample.
  bool get usesAffinity => _affinityForCurrentEgg;
  EggFeedback get eggFeedback => _eggFeedback;
  EggFeedback _eggFeedback = EggFeedback.none;
  bool get speechBusy => _speechBusy;
  bool get photoBusy => _photoBusy;
  bool _speechBusy = false, _photoBusy = false;
  bool _useAffinityForNewEggs = false;
  bool _affinityForCurrentEgg = false;
  int _inputGeneration = 0;
  int _requestNumber = 0;
  Timer? _affinityTimer;
  int _lastAffinityCheckpointMs = 0;
  int? _companionAtMs;
  int? _lastAffinityVehicleAtMs;
  ({
    int harshBrake,
    int harshSteer,
    List<String> capabilities
  })? _affinityEvidence;
  String? _pendingPhotoRequestId;
  Uint8List? _pendingPhotoBytes;
  String? _pendingPhotoMime;
  Future<void> _checkpointTail = Future.value();

  bool get _acceptAffinityInput =>
      !_disposed &&
      _appActive &&
      !busy &&
      !sessionEnded &&
      !endingSession &&
      _timer != null &&
      _modeSelected &&
      !_savingHatch &&
      _retrySave == null &&
      game.stage == Stage.incubating &&
      _affinity != null;

  String _requestId() =>
      '${_eggId}_${_now}_${++_requestNumber}_${_affinityRandom.nextInt(1 << 30)}';

  void _invalidateInputs() {
    _inputGeneration++;
  }

  bool _currentRequest(AffinityRound round, int generation, int connection) =>
      _acceptAffinityInput &&
      identical(round, _affinity) &&
      generation == _inputGeneration &&
      connection == _connection;

  Future<void> _writeCheckpoint(EggTier tier, IncubationProgress value) {
    final write =
        _checkpointTail.then((_) => dex.saveIncubationProgress(tier, value));
    _checkpointTail = write.catchError((Object _) {});
    return write;
  }

  Future<void> _persistAffinity() async {
    if (_affinity == null || _disposed || _savingHatch || _retrySave != null) {
      return;
    }
    try {
      await _writeCheckpoint(game.eggTier, _checkpoint());
    } catch (_) {
      error = '진행을 저장하지 못했어요. 다시 시도해 주세요.';
      notifyListeners();
    }
  }

  void _syncAffinity() {
    final round = _affinity;
    if (round == null) return;
    game = game.copyWith(
      ts: _now,
      affinityScore: round.score,
      affinityPhase:
          round.phase == AffinityPhase.hatched && game.stage != Stage.hatched
              ? 'resultPending'
              : round.phase.name,
      photoQuestCompleted: round.photoCompleted,
      stage: round.phase == AffinityPhase.failed ||
              round.phase == AffinityPhase.discarded
          ? Stage.failed
          : null,
    );
  }

  void _applyAffinity(EggFeedback feedback, {AffinityPhase? previousPhase}) {
    final round = _affinity;
    if (round == null) return;
    _eggFeedback = feedback;
    if (previousPhase != null && previousPhase != round.phase) {
      _invalidateInputs();
    }
    _syncAffinity();
    if (previousPhase != null &&
        previousPhase != round.phase &&
        (round.phase == AffinityPhase.failed ||
            round.phase == AffinityPhase.discarded)) {
      unawaited(_persistAffinity());
    }
    if (round.phase == AffinityPhase.hatched &&
        game.stage != Stage.hatched &&
        _pendingEntry == null &&
        !_savingHatch &&
        _retrySave == null &&
        _affinityEvidence != null) {
      _beginAffinityHatch();
    }
    if (game.stage == Stage.failed) _affinityTimer?.cancel();
    _publish();
    notifyListeners();
  }

  void _advanceAffinity({bool distanceDeadlineReached = false}) {
    final round = _affinity;
    if (round == null) return;
    final previous = round.phase;
    final feedback = round.advanceTo(_elapsedMs,
        distanceDeadlineReached: distanceDeadlineReached);
    _applyAffinity(feedback, previousPhase: previous);
  }

  void _startAffinityTimer() {
    _affinityTimer?.cancel();
    if (_affinity == null ||
        !_appActive ||
        _disposed ||
        _timer == null ||
        sessionEnded ||
        endingSession ||
        game.stage == Stage.failed) {
      return;
    }
    _affinityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed ||
          !_appActive ||
          sessionEnded ||
          endingSession ||
          _timer == null) {
        return;
      }
      _advanceClock();
      if (game.stage != Stage.hatched) _advanceAffinity();
      if (_elapsedMs - _lastAffinityCheckpointMs >= 5000) {
        _lastAffinityCheckpointMs = _elapsedMs;
        unawaited(_persistAffinity());
      }
    });
  }

  bool _prepareAffinity(AffinityPhase phase) {
    if (!_acceptAffinityInput) return false;
    _advanceClock();
    _advanceAffinity();
    return _acceptAffinityInput && _affinity!.phase == phase;
  }

  Future<EggFeedback> petEgg() async {
    if (!_prepareAffinity(AffinityPhase.incubating)) return EggFeedback.none;
    final round = _affinity!;
    final previous = round.phase;
    final feedback = round.pet(atMs: _elapsedMs);
    if (feedback == EggFeedback.positive ||
        feedback == EggFeedback.photoRequired ||
        feedback == EggFeedback.hatched) {
      careCount++;
      game = game.copyWith(careCount: careCount);
    }
    _applyAffinity(feedback, previousPhase: previous);
    await _persistAffinity();
    return feedback;
  }

  Future<EggFeedback> placeEgg(int zone) async {
    if (!_prepareAffinity(AffinityPhase.incubating) || zone < 0 || zone > 3) {
      return EggFeedback.none;
    }
    final round = _affinity!;
    final previous = round.phase;
    final choices = [0, 1, 2, 3]..remove(zone);
    final feedback = round.place(
        atMs: _elapsedMs,
        zone: zone,
        nextPreferredZone: choices[_affinityRandom.nextInt(3)]);
    _applyAffinity(feedback, previousPhase: previous);
    await _persistAffinity();
    return feedback;
  }

  Future<EggFeedback> submitEggSpeech(String text) async {
    if (!_prepareAffinity(AffinityPhase.incubating) ||
        _speechBusy ||
        text.trim().isEmpty ||
        text.runes.length > 500 ||
        _affinity!.speechRemainingMs > 0 ||
        eggApi == null) {
      return EggFeedback.none;
    }
    final round = _affinity!;
    final generation = _inputGeneration, connection = _connection;
    final requestId = _requestId();
    _speechBusy = true;
    notifyListeners();
    try {
      final sentiment = await eggApi!
          .evaluate(eggId: round.eggId, requestId: requestId, text: text);
      if (!_currentRequest(round, generation, connection)) {
        return EggFeedback.none;
      }
      if (!_prepareAffinity(AffinityPhase.incubating) ||
          generation != _inputGeneration) {
        return EggFeedback.none;
      }
      final previous = round.phase;
      final feedback = round.speak(
          atMs: _elapsedMs, requestId: requestId, sentiment: sentiment);
      _applyAffinity(feedback, previousPhase: previous);
      await _persistAffinity();
      return feedback;
    } catch (_) {
      if (_currentRequest(round, generation, connection)) {
        error = '말을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.';
      }
      return EggFeedback.none;
    } finally {
      _speechBusy = false;
      notifyListeners();
    }
  }

  Future<EggFeedback> uploadEggPhoto(Uint8List bytes,
      {String mimeType = 'image/jpeg'}) async {
    if (!_prepareAffinity(AffinityPhase.photoRequired) ||
        _photoBusy ||
        eggApi == null ||
        bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024 ||
        !{'image/jpeg', 'image/png'}.contains(mimeType)) {
      return EggFeedback.none;
    }
    final round = _affinity!;
    final generation = _inputGeneration, connection = _connection;
    _photoBusy = true;
    notifyListeners();
    try {
      // Reconcile an uncertain upload before replacing its bytes or request ID.
      if (_pendingPhotoRequestId != null &&
          (_pendingPhotoBytes == null ||
              !listEquals(bytes, _pendingPhotoBytes) ||
              _pendingPhotoMime != mimeType)) {
        final recovered =
            await _reconcileEggPhoto(round, generation, connection);
        if (round.photoCompleted) return recovered;
      }
      if (!_currentRequest(round, generation, connection)) {
        return EggFeedback.none;
      }
      if (_pendingPhotoBytes == null ||
          !listEquals(bytes, _pendingPhotoBytes) ||
          _pendingPhotoMime != mimeType) {
        _pendingPhotoRequestId = _requestId();
        _pendingPhotoBytes = Uint8List.fromList(bytes);
        _pendingPhotoMime = mimeType;
      }
      final requestId = _pendingPhotoRequestId!;
      await _writeCheckpoint(game.eggTier, _checkpoint());
      if (!_currentRequest(round, generation, connection) ||
          !_prepareAffinity(AffinityPhase.photoRequired)) {
        return EggFeedback.none;
      }
      final receipt = await eggApi!.uploadPhoto(
          eggId: round.eggId,
          requestId: requestId,
          bytes: Uint8List.fromList(_pendingPhotoBytes!),
          mimeType: mimeType);
      if (!_currentRequest(round, generation, connection) ||
          !_prepareAffinity(AffinityPhase.photoRequired) ||
          receipt.eggId != round.eggId ||
          receipt.requestId != requestId) {
        return EggFeedback.none;
      }
      return await _confirmEggPhoto(round, receipt);
    } catch (failure) {
      // An earlier uncertain request may have committed before this upload's conflict.
      if (failure is EggDemoApiException && failure.code == 'http_error') {
        try {
          final recovered =
              await _reconcileEggPhoto(round, generation, connection);
          if (round.photoCompleted) return recovered;
        } catch (_) {
          /* Keep the pending request recoverable after lookup failure. */
        }
      }
      if (_currentRequest(round, generation, connection)) {
        error = '사진을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      }
      return EggFeedback.none;
    } finally {
      _photoBusy = false;
      notifyListeners();
    }
  }

  Future<EggFeedback> _reconcileEggPhoto(
      AffinityRound round, int generation, int connection) async {
    if (!_currentRequest(round, generation, connection)) {
      return EggFeedback.none;
    }
    final photo = await eggApi!.findPhotoForEgg(round.eggId);
    if (!_currentRequest(round, generation, connection) ||
        !_prepareAffinity(AffinityPhase.photoRequired) ||
        photo == null ||
        photo.eggId != round.eggId) {
      return EggFeedback.none;
    }
    // The authenticated server allows only one receipt per globally unique egg.
    return _confirmEggPhoto(round, photo);
  }

  Future<EggFeedback> _confirmEggPhoto(
      AffinityRound round, UploadedEggPhoto photo) async {
    final previous = round.phase;
    final feedback = round.confirmPhoto(
        atMs: _elapsedMs, eggId: photo.eggId, photoId: photo.photoId);
    if (round.photoCompleted) {
      error = null;
      _pendingPhotoRequestId = null;
      _pendingPhotoBytes = null;
      _pendingPhotoMime = null;
    }
    _applyAffinity(feedback, previousPhase: previous);
    await _persistAffinity();
    return feedback;
  }

  Future<EggFeedback> recoverEggPhoto() async {
    if (!_prepareAffinity(AffinityPhase.photoRequired) ||
        _photoBusy ||
        eggApi == null) {
      return EggFeedback.none;
    }
    final round = _affinity!;
    final generation = _inputGeneration, connection = _connection;
    _photoBusy = true;
    notifyListeners();
    try {
      return await _reconcileEggPhoto(round, generation, connection);
    } catch (_) {
      if (_currentRequest(round, generation, connection)) {
        error = '사진을 확인하지 못했어요. 다시 시도해 주세요.';
      }
      return EggFeedback.none;
    } finally {
      _photoBusy = false;
      notifyListeners();
    }
  }

  Future<EggFeedback> discardEgg() async {
    if (!_acceptAffinityInput) return EggFeedback.none;
    _advanceClock();
    _advanceAffinity();
    if (!_acceptAffinityInput || _affinity!.isTerminal) return EggFeedback.none;
    final round = _affinity!;
    final previous = round.phase;
    final feedback = round.discard(atMs: _elapsedMs);
    _applyAffinity(feedback, previousPhase: previous);
    await _persistAffinity();
    return feedback;
  }

  final Stopwatch _stopwatch = Stopwatch();
  final int Function()? _monotonicMs;
  int get activeClockMs =>
      _monotonicMs?.call() ??
      (_stopwatch.elapsedMilliseconds *
              (feed is FakeVehicleFeed
                  ? (feed as FakeVehicleFeed).timeScale
                  : 1))
          .round();
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
  bool _needsResumeBaseline = false;
  int _resumeBrake = 0;
  int _resumeSteer = 0;
  RegionCollection _collection = const RegionCollection.unknown();
  List<String> _collectedIds = const [];

  /// 도감에 있는 캐릭터. 창밖에 친구로 지나갈 수 있다 (표시 전용, 판정에 쓰지 않는다).
  List<Species> get collectedSpecies {
    final table = _table;
    if (table == null) return const [];
    return [
      for (final id in _collectedIds)
        if (table.byId(id) case final s?) s,
    ];
  }

  int _collectionVersion = 0;
  RegionDurationAccumulator _regions = RegionDurationAccumulator();
  int? _regionSourceTs;
  Future<void> _publishTail = Future.value();
  int? _lastPublishedAt;
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
  String? _roundSessionId;
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

  /// "퍼들핍이" · "바다안개가" — 받침 유무로 주격 조사를 고른다
  static String subjectOf(String name) {
    if (name.isEmpty) return name;
    final code = name.codeUnitAt(name.length - 1);
    final batchim =
        code >= 0xAC00 && code <= 0xD7A3 && (code - 0xAC00) % 28 != 0;
    return '$name${batchim ? '이' : '가'}';
  }

  // 동행 반응은 폰 안에서만 유지하며 부화 등급이나 서버 계약을 바꾸지 않는다.
  /// [kind] 는 탐험 화면이 알려 준 먹이 종류 (문구만 바뀐다. 세는 방식은 같다)
  void feedCompanion([String? kind]) {
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
    feedCount++;
    final name = hatched?.nameKo ?? '친구';
    companionMessage = switch (kind) {
      'water' => '${subjectOf(name)} 물을 꿀꺽 마셨어요!',
      'shell' => '${subjectOf(name)} 조개를 맛있게 먹었어요!',
      'acorn' => '${subjectOf(name)} 도토리를 오독오독 먹었어요!',
      'fishbun' => '${subjectOf(name)} 붕어빵을 냠냠 먹었어요!',
      _ => '${subjectOf(name)} 맛있게 먹었어요!',
    };
    notifyListeners();
  }

  /// [kind] 는 탐험 화면의 놀이 종류 (문구만 바뀐다. 세는 방식은 같다)
  void playWithCompanion([String? kind]) {
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
    playCount++;
    final name = hatched?.nameKo ?? '친구';
    companionMessage = switch (kind) {
      'pet' => '${subjectOf(name)} 기분 좋아해요!',
      'ball' => '${subjectOf(name)} 공을 굴려 줬어요!',
      'plush' => '${subjectOf(name)} 인형을 꼭 안았어요!',
      'cushion' => '${subjectOf(name)} 쿠션에서 통통 뛰어요!',
      'blanket' => '${subjectOf(name)} 포근하게 자요',
      'draw' => '${subjectOf(name)} 그림을 구경해요!',
      'bobble' => '${subjectOf(name)} 흔들 인형을 따라 해요!',
      'toycar' => '${subjectOf(name)} 장난감 차를 쫓아가요!',
      'music' => '${subjectOf(name)} 오르골에 맞춰 춤춰요!',
      'book' => '${subjectOf(name)} 그림책을 같이 봐요!',
      'bubble' => '${subjectOf(name)} 비눗방울을 잡으려 해요!',
      'tissue' => '${subjectOf(name)} 에취! 재채기를 했어요',
      'nest' => '${subjectOf(name)} 둥지에서 쉬어요',
      _ => '${subjectOf(name)} 신나게 뛰어요!',
    };
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
    _campDriveSessionId = null;
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
    } on RetryablePairingException catch (e) {
      error = e.message;
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
    // A saved companion belongs to its vehicle session, not the next pairing.
    // Legacy companions still use the known active session for this boundary.
    final previousSessionId = _roundSessionId ?? _activeSessionId;
    if (previousSessionId != null &&
        previousSessionId != credentials.sessionId &&
        game.stage == Stage.hatched) {
      hatched = null;
      companionMessage = null;
      game = GameState(
          ts: _now, eggTier: game.eggTier, stage: Stage.idle, progress: 0);
    }
    _sessionId = credentials.sessionId;
    _remoteEnded = false;
    _remoteSaved = false;
    _finalSnapshotRead = false;
    paired = true;
    await fishing.attach(credentials.sessionId);
    await fishing.setActive(_appActive);
    if (_disposed || connection != _connection) return;
    await _prepareCampForTrip();
    if (_disposed || connection != _connection) return;
    if (fishing.selectedSpeciesId != null || baseCamp?.ready == true) {
      _ensureCompanionVehicleSubscription();
    }
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
    await _refreshCollection();
    if (!_disposed && connection == _connection) _publish();
  }

  void _onCarEvent(Map<String, Object?> event, int connection) {
    if (_disposed ||
        connection != _connection ||
        sessionEnded ||
        event['by'] != 'car') {
      return;
    }
    if (event['type'] == 'fishingRequested' ||
        event['type'] == 'companionTransferRequested') {
      unawaited(fishing.handleEvent(event));
      return;
    }
    if (event['type'] != 'sessionEnd') return;
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
        _sessionId = sessionId;
        await fishing.attach(sessionId);
        await fishing.setActive(_appActive);
        _eventsSub ??=
            feed.events().listen((event) => _onCarEvent(event, _connection));
        await _refreshCollection();
        _publish();
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
  Future<bool> startIncubating(EggTier tier, {bool useAffinity = false}) async {
    if (!canStart) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!await endSession()) return false;
      await loadSpecies();
      await _refreshCollection();
      final saved = await dex.incubationProgress(tier);
      if (_disposed || sessionEnded || (!isFake && !paired)) return false;
      _activeSessionId = isFake ? null : _sessionId;
      await _prepareCampForTrip();
      if (_disposed || sessionEnded || (!isFake && !paired)) return false;
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
      _useAffinityForNewEggs = useAffinity;
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
        if (_campDriveSessionId != null) {
          baseCamp?.beginDrivingSession(_campDriveSessionId!);
        }
        error = '차량 신호를 받지 못했어요. 연결을 확인해 주세요.';
        notifyListeners();
      });
      _startAffinityTimer();
      notifyListeners();
      _publish();
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
    _affinityTimer?.cancel();
    _invalidateInputs();
    _affinity = null;
    _affinityForCurrentEgg = _useAffinityForNewEggs;
    _eggFeedback = EggFeedback.none;
    _pendingPhotoRequestId = null;
    _pendingPhotoBytes = null;
    _pendingPhotoMime = null;
    _pendingEntry = null;
    _companionAtMs = null;
    _lastAffinityVehicleAtMs = null;
    _affinityEvidence = null;
    _lastAffinityCheckpointMs = 0;
    _roundSessionId = _activeSessionId;
    _roundNumber++;
    _eggId = '$_now-$_roundNumber-${_affinityRandom.nextInt(1 << 30)}';
    _elapsedMs = 0;
    _regions = RegionDurationAccumulator();
    _regionSourceTs = null;
    _clockAt = activeClockMs;
    _modeSelected = false;
    _hatchSec = null;
    _companionSec = null;
    _repeats = false;
    _needsCounterBaseline = true;
    _needsResumeBaseline = false;
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
    if (game.stage == Stage.idle) {
      // No egg existed during the deferred interval, so its distance is not care.
      _distanceBaseline = v.distanceM;
      _timer =
          HatchTimer(eggTier: game.eggTier, carriedM: _timer?.carriedM ?? 0);
    }
    _modeSelected = true;
    game = game.copyWith(stage: Stage.incubating);
    _elapsedMs = 0;
    _clockAt = activeClockMs;
    if (eta != null) {
      final round = incubationRound(eta);
      _hatchSec = round.hatchEndSec;
      _companionSec = round.companionEndSec;
      _repeats = round.grantsNextEgg;
    }
    if (_affinityForCurrentEgg) {
      _affinity = AffinityRound.start(
          eggId: _eggId!,
          preferredZone: _affinityRandom.nextInt(4),
          deadlineMs: _hatchSec == null ? null : _hatchSec! * 1000);
      _syncAffinity();
      _startAffinityTimer();
      unawaited(_persistAffinity());
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

  void _recordAffinityEvidence(VehicleState v) {
    _affinityEvidence = (
      harshBrake:
          _brakeOffset + (v.harshBrake - _brakeBaseline).clamp(0, 1 << 30),
      harshSteer:
          _steerOffset + (v.harshSteer - _steerBaseline).clamp(0, 1 << 30),
      capabilities: List<String>.unmodifiable(v.capabilities),
    );
    _observeRegion(v);
    seenTags.addAll(v.envTags);
  }

  void _onVehicle(VehicleState v, {bool finalSnapshot = false}) {
    if (_disposed || (!finalSnapshot && (sessionEnded || !_appActive))) return;
    if (!finalSnapshot) fishing.observePresence(v.fishingPresence);
    // Distance snapshots in older feeds may share a ts. Preserve their high-water
    // distance handling, while ETA rounds reject duplicate/out-of-order samples.
    if ((_hatchSec != null || _affinity != null) &&
        !finalSnapshot &&
        _lastVehicleTs != null &&
        v.ts <= _lastVehicleTs!) {
      return;
    }
    _lastVehicleTs = v.ts;
    vehicle = v;
    final campSession = _campDriveSessionId;
    if (!finalSnapshot &&
        _appActive &&
        campSession != null &&
        baseCamp?.ready == true) {
      unawaited(baseCamp!.recordVehicle(sessionId: campSession, vehicle: v));
    }
    final t = _timer;
    if (t == null) {
      if (!finalSnapshot) _publishHeartbeat();
      notifyListeners();
      return;
    }
    _advanceClock();
    if (_affinity != null && !finalSnapshot) {
      _lastAffinityVehicleAtMs = _elapsedMs;
    }
    if (_needsResumeBaseline) {
      _distanceBaseline +=
          (v.distanceM - _lastDistance).clamp(0, double.infinity);
      _brakeOffset += (_resumeBrake - _brakeBaseline).clamp(0, 1 << 30);
      _steerOffset += (_resumeSteer - _steerBaseline).clamp(0, 1 << 30);
      _brakeBaseline = v.harshBrake;
      _steerBaseline = v.harshSteer;
      _needsResumeBaseline = false;
    }
    if (_needsLegacyBaseline) {
      _distanceBaseline = v.distanceM;
      _needsLegacyBaseline = false;
    }
    if (v.distanceM > _lastDistance) _lastDistance = v.distanceM;
    if (_activeSessionId != null) {
      _sessionDistances[_activeSessionId!] = _lastDistance;
    }
    if (game.stage == Stage.hatched) {
      final granted = _grantNextEgg(v, finalSnapshot: finalSnapshot);
      if (!granted && !finalSnapshot) _publishHeartbeat();
      notifyListeners();
      return;
    }
    if (game.stage == Stage.failed) {
      // The egg is terminal; its selected companion and fishing remain live.
      if (!finalSnapshot) _publishHeartbeat();
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
    if (_affinity == null) {
      _observeRegion(v);
      seenTags.addAll(v.envTags);
    } else if (_affinityEvidence == null && _elapsedMs == 0) {
      _recordAffinityEvidence(v);
    }
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
    if (_affinity != null) {
      // Passive crossings settle before incoming evidence, including a same-time sample.
      _advanceAffinity(distanceDeadlineReached: _hatchSec == null && p >= 1);
      if (!_affinity!.isTerminal) _recordAffinityEvidence(v);
    } else if (p >= 1) {
      _hatch(v);
    }
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
        (_affinity != null &&
            (_lastAffinityVehicleAtMs == null ||
                _lastAffinityVehicleAtMs! < _companionAtMs!)) ||
        _elapsedMs < (_companionAtMs ?? _companionSec! * 1000) ||
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
    if (_affinity == null) {
      _observeRegion(v);
      seenTags.addAll(v.envTags);
    } else {
      _recordAffinityEvidence(v);
    }
    game = GameState(
        ts: _now,
        eggTier: game.eggTier,
        stage: Stage.incubating,
        progress: 0,
        hatchAtM: _hatchSec == null ? _timer!.hatchAtM : null,
        hatchAtSec: _hatchSec);
    _syncAffinity();
    notifyListeners();
    _publish();
    return true;
  }

  void _applyCollection() {
    game = game.copyWith(
        regionCollectionKnown: _collection.known,
        uncollectedRegions: _collection.uncollectedRegions);
  }

  Future<void> _refreshCollection() async {
    final version = ++_collectionVersion;
    try {
      final entries = await dex.all();
      if (_disposed || version != _collectionVersion) return;
      _collection = RegionCollection.fromEntries(entries);
      _collectedIds = {for (final e in entries) e.speciesId}.toList();
      if (baseCamp?.ready == true) await baseCamp!.refreshOwnership();
    } catch (_) {
      if (_disposed || version != _collectionVersion) return;
      _collection = const RegionCollection.unknown();
    }
    _applyCollection();
  }

  void _invalidateCollection() {
    _collectionVersion++;
    _collection = const RegionCollection.unknown();
    _applyCollection();
  }

  // Serialize full game writes and discard queued work for an old connection.
  void _publish() {
    _lastPublishedAt = activeClockMs;
    _applyCollection();
    game = game.copyWith(
        ts: _now,
        vehicleFeatures: fishing.initialized
            ? {
                ...fishing.snapshotFields,
                if (baseCamp?.ready == true)
                  ...campVehicleSnapshot(baseCamp!.state),
              }
            : const {});
    final snapshot = game;
    final connection = _connection;
    final sessionId = _sessionId;
    _publishTail = _publishTail.then((_) async {
      if (_disposed || connection != _connection || sessionId != _sessionId) {
        return;
      }
      await _send(() => feed.publishGame(snapshot));
    });
  }

  // A companion may remain visually unchanged for minutes. Keep its current
  // state live on the vehicle without inventing a new field or changing game rules.
  void _publishHeartbeat() {
    final now = activeClockMs;
    if (_disposed || !_appActive || sessionEnded || endingSession) return;
    if (_lastPublishedAt != null &&
        now >= _lastPublishedAt! &&
        now - _lastPublishedAt! < 3000) {
      return;
    }
    game = game.copyWith(ts: _now);
    _publish();
  }

  int get _regionAtMs =>
      _hatchSec == null ? _elapsedMs : _elapsedMs.clamp(0, _hatchSec! * 1000);

  void _observeRegion(VehicleState v) {
    if (game.stage != Stage.incubating) return;
    if (_hatchSec != null && _elapsedMs >= _hatchSec! * 1000) {
      _regions.finish(_regionAtMs);
      return;
    }
    if (_regionSourceTs != null && v.ts <= _regionSourceTs!) return;
    _regionSourceTs = v.ts;
    _regions.observe(atMs: _regionAtMs, envTags: v.envTags);
  }

  void _hatch(VehicleState v) {
    if (_affinity != null) {
      _beginAffinityHatch();
      return;
    }
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
    final region = _regions.finish(_regionAtMs);
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

  void _beginAffinityHatch() {
    final round = _affinity!;
    if (round.phase != AffinityPhase.hatched ||
        _pendingEntry != null ||
        _retrySave != null) {
      return;
    }
    final evidence = _affinityEvidence!;
    final result = engine.judge(
        seenTags: seenTags,
        harshBrake: evidence.harshBrake,
        harshSteer: evidence.harshSteer,
        careCount: careCount,
        capabilities: evidence.capabilities);
    final species = _table!.pick(result, seenTags);
    final entry = DexEntry(
        speciesId: species.id,
        obtainedAt: DateTime.now(),
        envTags: seenTags.toList(),
        regionTag: _regions.finish(round.hatchedAtMs!),
        tier: result.tier,
        sourceEggId: round.eggId);
    _pendingEntry = entry;
    _companionAtMs = round.hatchedAtMs! + 1800000;
    _repeats = true;
    final tier = game.eggTier;
    _retrySave = () => _saveAffinityHatch(entry, tier);
    _pendingSave = _trySave();
  }

  Future<void> _saveAffinityHatch(DexEntry entry, EggTier tier) async {
    final connection = _connection;
    final round = _affinity!;
    // Write the frozen result first; crashes between writes retry the same source egg.
    await _writeCheckpoint(tier, _checkpoint());
    await dex.add(entry);
    if (_disposed ||
        connection != _connection ||
        !identical(round, _affinity)) {
      return;
    }
    final species = _table!.byId(entry.speciesId)!;
    final completed = game.copyWith(
        stage: Stage.hatched,
        progress: 1,
        speciesId: species.id,
        attribute: species.attribute,
        tier: entry.tier,
        affinityPhase: AffinityPhase.hatched.name);
    final checkpoint = _checkpoint();
    final snapshot = Map<String, dynamic>.from(checkpoint.round!)
      ..remove('pendingEntry')
      ..['game'] = completed.toJson();
    await _writeCheckpoint(
        tier,
        IncubationProgress(
            carriedM: 0,
            sessionDistances: checkpoint.sessionDistances,
            round: snapshot));
    if (_disposed ||
        connection != _connection ||
        !identical(round, _affinity)) {
      return;
    }
    hatched = species;
    game = completed;
    error = null;
    await _refreshCollection();
    _publish();
    await _send(() => feed.emitEvent('hatched',
        payload: {'speciesId': species.id, 'tier': entry.tier}));
    notifyListeners();
  }

  Future<void> _trySave() async {
    if (_savingHatch) return;
    _savingHatch = true;
    try {
      await _retrySave?.call();
      _retrySave = null;
      _pendingEntry = null;
    } catch (_) {
      _invalidateCollection();
      _publish();
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
    await _writeCheckpoint(
        tier,
        _hatchSec == null
            ? IncubationProgress(sessionDistances: checkpoint.sessionDistances)
            : IncubationProgress(
                carriedM: checkpoint.carriedM,
                sessionDistances: checkpoint.sessionDistances,
                round: checkpoint.round == null
                    ? null
                    : (Map<String, dynamic>.of(checkpoint.round!)
                      ..remove('pendingEntry'))));
    if (_disposed || connection != _connection) return;
    await _refreshCollection();
    if (!_disposed && connection == _connection) _publish();
  }

  void care() {
    if (_affinity != null || _affinityForCurrentEgg) {
      unawaited(petEgg());
      return;
    }
    if (game.stage != Stage.incubating || sessionEnded || endingSession) return;
    careCount++;
    game = game.copyWith(ts: _now, careCount: careCount);
    _publish();
    notifyListeners();
  }

  void lookOut() {
    if (game.stage != Stage.hatched || sessionEnded || endingSession) return;
    lookOutCount++;
    if (baseCamp?.ready == true && _campDriveSessionId != null) {
      unawaited(baseCamp!.recordLookOut(
          eventId: '${_campDriveSessionId}_${_eggId}_$lookOutCount'));
    }
    game = game.copyWith(lookOutCount: lookOutCount);
    unawaited(_send(() => feed.emitEvent('lookOutPrompt')));
    _publish();
    notifyListeners();
  }

  /// 로컬 체크포인트. 차량 종료를 받은 경우에는 최종 신호와 저장을 마친 뒤 연결도 정리한다.
  Future<bool> endSession() {
    if (sessionSaved) return Future.value(true);
    final pending = _closing;
    if (pending != null) return pending;
    _invalidateInputs();
    _affinityTimer?.cancel();
    final closing = _finishSession(_connection).whenComplete(() {
      _closing = null;
      _startAffinityTimer();
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
      // Start stopping fishing now, but read the vehicle's final snapshot without
      // waiting for unrelated local storage. Both saves must succeed before closing.
      final fishingStop = () async {
        if (fishing.hasPendingWrite) await fishing.retrySave();
        await fishing.setActive(false);
        if (!sessionEnded) await fishing.setActive(_appActive);
      }();
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
        await fishingStop;
        if (fishing.hasPendingWrite) {
          error = fishing.error;
          return false;
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
                _affinity != null ||
                _lifecycleCheckpoint)) {
          _advanceClock();
          if (_affinity != null) _advanceAffinity();
          await _pendingSave;
          if (_retrySave != null) return false;
          if (_affinity != null) _regions.breakContinuity(_regionAtMs);
          final checkpoint = _checkpoint();
          await _writeCheckpoint(
              game.eggTier,
              game.stage == Stage.hatched &&
                      _affinity == null &&
                      (_hatchSec == null || sessionEnded)
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
        // Preserve the v2 composer while final egg/collection saves publish.
        await fishing.detach();
        if (fishing.hasPendingWrite) {
          error = fishing.error;
          return false;
        }
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
        _startAffinityTimer();
      }
    }
  }

  Map<String, dynamic> _roundSnapshot() => {
        'eggId': _eggId,
        'number': _roundNumber,
        'sessionId': _roundSessionId,
        'elapsedMs': _elapsedMs,
        'hatchSec': _hatchSec,
        'companionSec': _companionSec,
        'companionAtMs': _companionAtMs,
        'useAffinityForNewEggs': _useAffinityForNewEggs,
        if (_affinity != null) 'affinity': _affinity!.toJson(),
        if (_pendingPhotoRequestId != null)
          'pendingPhotoRequestId': _pendingPhotoRequestId,
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
        'needsResumeBaseline': _needsResumeBaseline,
        'region': _affinity == null
            ? _regions.checkpoint(_regionAtMs)
            : _regions.snapshot(_regionAtMs),
        if (_affinity != null && _affinityEvidence != null)
          'affinityEvidence': {
            'harshBrake': _affinityEvidence!.harshBrake,
            'harshSteer': _affinityEvidence!.harshSteer,
            'capabilities': _affinityEvidence!.capabilities,
          },
        'regionSourceTs': _regionSourceTs,
        'resumeBrake': _resumeBrake,
        'resumeSteer': _resumeSteer,
        'feedCount': feedCount,
        'playCount': playCount,
        if (_pendingEntry != null) 'pendingEntry': _pendingEntry!.toJson(),
      };

  IncubationProgress _checkpoint() => IncubationProgress(
        carriedM:
            game.stage == Stage.hatched || (_affinity?.isTerminal ?? false)
                ? 0
                : (_timer?.carryOver(hatched: false) ?? 0),
        sessionDistances: Map.of(_sessionDistances),
        round: _roundSnapshot(),
      );

  void _restoreRound(Map<String, dynamic> round, EggTier tier) {
    final g = Map<String, dynamic>.from(round['game'] as Map);
    _useAffinityForNewEggs =
        _useAffinityForNewEggs || round['useAffinityForNewEggs'] == true;
    _affinityForCurrentEgg = _useAffinityForNewEggs;
    final savedAffinity = round['affinity'] is Map
        ? AffinityRound.fromJson(
            Map<String, dynamic>.from(round['affinity'] as Map))
        : null;
    if (savedAffinity?.phase == AffinityPhase.failed ||
        savedAffinity?.phase == AffinityPhase.discarded) {
      return;
    }
    // Preserve unfinished saves and legacy/Fake checkpoints. A completed round
    // from another real session must not replace the fresh egg set up by start.
    if (!isFake &&
        round['sessionId'] != null &&
        _activeSessionId != null &&
        round['sessionId'] != _activeSessionId &&
        g['stage'] == Stage.hatched.name &&
        round['pendingEntry'] == null) {
      return;
    }
    // A distance-mode arrival retains the existing manual new-egg behavior.
    // Lifecycle snapshots restore distance companions; explicit endSession clears it.
    _affinity = savedAffinity;
    final evidence = round['affinityEvidence'];
    if (savedAffinity != null && evidence is Map) {
      _affinityEvidence = (
        harshBrake: (evidence['harshBrake'] as num).toInt(),
        harshSteer: (evidence['harshSteer'] as num).toInt(),
        capabilities: List<String>.unmodifiable(
            (evidence['capabilities'] as List).cast<String>()),
      );
    }
    _affinityForCurrentEgg = savedAffinity != null;
    _companionAtMs = (round['companionAtMs'] as num?)?.toInt();
    _pendingPhotoRequestId = round['pendingPhotoRequestId'] as String?;
    _eggId = round['eggId'] as String?;
    _roundNumber = (round['number'] as num).toInt();
    _elapsedMs = (round['elapsedMs'] as num).toInt();
    _hatchSec = (round['hatchSec'] as num?)?.toInt();
    _companionSec = (round['companionSec'] as num?)?.toInt();
    _repeats = round['repeats'] == true;
    _modeSelected = round['modeSelected'] == true;
    final region = round['region'];
    if (region is Map) {
      _regions = RegionDurationAccumulator.restore(
          Map<String, dynamic>.from(region),
          atMs: _regionAtMs);
    } else {
      _regions = RegionDurationAccumulator()..breakContinuity(_regionAtMs);
    }
    _regionSourceTs = !isFake && round['sessionId'] == _activeSessionId
        ? (round['regionSourceTs'] as num?)?.toInt()
        : null;
    careCount = (g['careCount'] as num?)?.toInt() ?? 0;
    lookOutCount = (g['lookOutCount'] as num?)?.toInt() ?? 0;
    feedCount = (round['feedCount'] as num?)?.toInt() ?? 0;
    playCount = (round['playCount'] as num?)?.toInt() ?? 0;
    seenTags.addAll((round['tags'] as List).cast<String>());
    _brakeBaseline = (round['brakeBaseline'] as num).toInt();
    _steerBaseline = (round['steerBaseline'] as num).toInt();
    final changedSession = isFake || round['sessionId'] != _activeSessionId;
    _needsResumeBaseline =
        !changedSession && round['needsResumeBaseline'] == true;
    _resumeBrake = (round['resumeBrake'] as num?)?.toInt() ?? _brakeBaseline;
    _resumeSteer = (round['resumeSteer'] as num?)?.toInt() ?? _steerBaseline;
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
    // Retrying a completed result elsewhere must not reassign its source session.
    // Unhatched progress keeps the current session for resume counter baselines.
    if (stage == Stage.hatched && !isFake) {
      _roundSessionId = round['sessionId'] as String?;
    }
    final speciesId = g['speciesId'] as String?;
    if (speciesId != null) {
      hatched = _table!.byId(speciesId);
    }
    game = GameState(
        ts: _now,
        eggTier: tier,
        stage: stage,
        affinityScore: _affinity?.score,
        affinityPhase:
            _affinity?.phase == AffinityPhase.hatched && stage != Stage.hatched
                ? 'resultPending'
                : _affinity?.phase.name,
        photoQuestCompleted: _affinity?.photoCompleted ?? false,
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
      _retrySave = _affinity == null
          ? () => _saveHatch(pending, tier, _checkpoint())
          : () => _saveAffinityHatch(pending, tier);
      _pendingSave = _trySave();
    }
  }

  /// Checkpoints recognized active time, never credits wall-clock suspension.
  /// OS termination before this future finishes can still lose the latest interval.
  Future<bool> setAppActive(bool active) async {
    if (_disposed) return false;
    if (_appActive == active) return true;
    _advanceClock();
    if (_affinity != null && !active) _advanceAffinity();
    _invalidateInputs();
    _affinityTimer?.cancel();
    _appActive = active;
    await fishing.setActive(active);
    _clockAt = activeClockMs;
    if (active) {
      if (_campDriveSessionId != null) {
        baseCamp?.beginDrivingSession(_campDriveSessionId!);
      }
      if (baseCamp?.ready == true) await baseCamp!.refreshOwnership();
      _startAffinityTimer();
      return true;
    }
    if (_timer == null || sessionSaved) return true;
    _regions.breakContinuity(_regionAtMs);
    _needsResumeBaseline = true;
    _resumeBrake = vehicle?.harshBrake ?? _brakeBaseline;
    _resumeSteer = vehicle?.harshSteer ?? _steerBaseline;
    final connection = _connection;
    try {
      await _pendingSave;
      if (_disposed || connection != _connection) return false;
      await _writeCheckpoint(game.eggTier, _checkpoint());
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
    baseCamp?.removeListener(_onCampChanged);
    fishing.dispose();
    _invalidateInputs();
    _affinityTimer?.cancel();
    _connection++;
    _sub?.cancel();
    _eventsSub?.cancel();
    feed.dispose();
    super.dispose();
  }
}
