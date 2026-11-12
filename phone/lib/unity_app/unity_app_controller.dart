import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

import '../base_camp/base_camp_controller.dart';
import '../explore/explore_messages.dart';
import '../game/game_controller.dart';
import '../pairing/pairing_credentials.dart';
import 'unity_demo_creatures.dart';
import '../scene/window_scene.dart';

const _nativeInput = MethodChannel('allo/egg-input');

/// Unity only submits intents. Existing controllers own all game and camp rules.
class UnityAppController extends ChangeNotifier {
  UnityAppController(
      {required this.game,
      required this.camp,
      this.demoCreatures = false,
      Future<String?> Function()? speechInput,
      Future<Uint8List?> Function()? photoInput})
      : _speechInput =
            speechInput ?? (() => _nativeInput.invokeMethod<String>('speech')),
        _photoInput = photoInput ??
            (() => _nativeInput.invokeMethod<Uint8List>('photo')) {
    game.addListener(_changed);
    camp.addListener(_changed);
    _egg = _readEgg();
  }

  final GameController game;
  final BaseCampController camp;
  final bool demoCreatures;
  final Future<String?> Function() _speechInput;
  final Future<Uint8List?> Function() _photoInput;
  final _handled = <String>{};
  final _stabilizer = SceneStabilizer();
  List<Species> _species = [];
  Map<String, int> _counts = {};
  late Map<String, dynamic> _egg;
  String view = 'home';
  bool gyro = true, reducedMotion = false;
  bool _disposed = false,
      _ready = false,
      _nativeSpeech = false,
      _nativePhoto = false;
  int _revision = 0, _pending = 0;
  String _error = '', _notice = '';
  bool _disconnected = false;
  EggTier? _stoppedRoundTier;
  String? _countedHatch;
  Future<void> _tail = Future.value();
  void Function(String)? _send;
  bool _unityReady = false;

  bool _unityActive = true;
  AppLifecycleState _hostLifecycle = AppLifecycleState.resumed;

  Future<void> setHostLifecycle(AppLifecycleState state) async {
    _hostLifecycle = state;
    await _syncGameActive();
  }

  Future<void> _syncGameActive() async {
    if (_disposed) return;
    final active = _hostLifecycle != AppLifecycleState.detached &&
        (_hostLifecycle == AppLifecycleState.resumed ||
            _unityActive ||
            _nativeSpeech ||
            _nativePhoto);
    await game.setAppActive(active);
  }

  Future<bool> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      gyro = preferences.getBool('unityApp.gyro') ?? true;
      reducedMotion = preferences.getBool('unityApp.reducedMotion') ?? false;
      _species = SpeciesTable.fromJson(jsonDecode(
                  await rootBundle.loadString('assets/data/species.json'))
              as Map<String, dynamic>)
          .all;
      if (demoCreatures && game.isFake) {
        await seedUnityDemoCreatures(game.dex, _species);
      }
      final loaded =
          camp.ready ? await camp.refreshOwnership() : await camp.load();
      await _readCounts();
      if (_disposed) return false;
      _ready = loaded;
      _changed();
      return loaded;
    } catch (_) {
      _error = '앱 정보를 불러오지 못했어요. 새로고침해 주세요.';
      _changed();
      return false;
    }
  }

  Future<void> _readCounts() async {
    final counts = <String, int>{};
    for (final entry in await game.dex.all()) {
      counts.update(entry.speciesId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (!_disposed) _counts = counts;
  }

  void attach(void Function(String) send) {
    _send = send;
    _publish();
  }

  Map<String, dynamic> _readEgg() {
    final r = game.affinityRound;
    final active = _stoppedRoundTier == null &&
        !_disconnected &&
        !game.sessionEnded &&
        game.game.stage == Stage.incubating &&
        r != null &&
        !r.isTerminal;
    final remaining = r?.deadlineMs == null
        ? null
        : (r!.deadlineMs! - r.elapsedMs).clamp(0, 1 << 40);
    return {
      'speciesId':
          game.game.stage == Stage.hatched ? game.hatched?.id ?? '' : '',
      'name':
          game.game.stage == Stage.hatched ? game.hatched?.nameKo ?? '' : '',
      'sprite':
          game.game.stage == Stage.hatched ? game.hatched?.sprite ?? '' : '',
      'id': game.eggId ?? '',
      'phase': game.game.affinityPhase ?? r?.phase.name ?? game.game.stage.name,
      'feedback': game.eggFeedback.name,
      'remainingLabel': remaining == null
          ? '차량 신호를 기다려요'
          : '${(remaining / 60000).ceil()}분 남음',
      'active': active,
      'photoRequired': r?.phase == AffinityPhase.photoRequired,
      'speechBusy': game.speechBusy || _nativeSpeech,
      'photoBusy': game.photoBusy || _nativePhoto,
      'score': game.game.affinityScore ?? r?.score ?? 0.0,
      'zone': r?.currentZone ?? 0,
      'preferredZone': r?.preferredZone ?? 0,
      'speechCooldown': ((r?.speechRemainingMs ?? 0) / 1000).ceil(),
      'petCooldown': ((r?.petRemainingMs ?? 0) / 1000).ceil(),
      'moveCooldown': ((r?.moveRemainingMs ?? 0) / 1000).ceil(),
    };
  }

  bool get _canStartEgg =>
      _ready &&
      ((game.canStart &&
              (game.game.stage == Stage.idle ||
                  game.game.stage == Stage.failed ||
                  _stoppedRoundTier != null)) ||
          (game.isFake &&
              game.sessionEnded &&
              game.sessionSaved &&
              !game.busy &&
              !game.endingSession));

  Map<String, dynamic> get snapshot {
    final c = camp.state;
    final buffs = c.toJson()['buffs'] as Map;
    bool affordable(Map<CampMaterial, int> cost) =>
        cost.entries.every((e) => (c.materials[e.key] ?? 0) >= e.value);
    return {
      'v': 1,
      'type': 'app',
      'revision': _revision,
      'view': view,
      'ready': _ready,
      'busy': _pending > 0 ||
          game.busy ||
          camp.busy ||
          _nativeSpeech ||
          _nativePhoto,
      'error':
          _error.isNotEmpty ? _error : game.error ?? _campError(camp.error),
      'notice': _notice.isNotEmpty ? _notice : game.pairingNotice ?? '',
      'connected': game.paired && !game.sessionEnded,
      'isDemo': game.isFake,
      'canStart': _canStartEgg,
      'sessionEnded': game.sessionEnded,
      'speechAvailable': game.eggApi != null,
      'photoAvailable': game.eggApi != null,
      'gyro': gyro,
      'reducedMotion': reducedMotion,
      'egg': {
        ..._egg,
        'speechBusy': game.speechBusy || _nativeSpeech,
        'photoBusy': game.photoBusy || _nativePhoto
      },
      'materials': [
        for (final material in CampMaterial.values)
          {
            'id': material.name,
            'label': switch (material) {
              CampMaterial.wood => '나무',
              CampMaterial.stone => '돌',
              CampMaterial.ingredient => '식재료'
            },
            'count': c.materials[material] ?? 0
          }
      ],
      'facilities': [
        for (final facility in CampFacility.values)
          _facility(c, facility, affordable)
      ],
      'creatures': [
        for (final creature in c.creatures.values)
          {
            'id': creature.id,
            'speciesId': creature.speciesId,
            'name': _species
                    .where((s) => s.id == creature.speciesId)
                    .firstOrNull
                    ?.nameKo ??
                creature.speciesId,
            'role': CampCatalog.roleFor(creature.speciesId)?.name ?? '',
            'sprite': _species
                    .where((s) => s.id == creature.speciesId)
                    .firstOrNull
                    ?.sprite ??
                '',
            'actions': (c.learnedActions[creature.id] ?? {}).toList()..sort(),
            'foodBoostUntilMs': buffs[creature.id] ?? 0
          }
      ],
      'assignments': [
        for (final e in c.assignments.entries)
          {'role': e.key.name, 'creatureId': e.value}
      ],
      'jobs': [for (final j in c.jobs.values) _job(c, j)],
      'foods': [
        for (final r in CampCatalog.recipes.values)
          {
            'id': r.id,
            'label': _label(r.id),
            'count': c.foodInventory[r.id] ?? 0,
            'costIngredient': r.cost[CampMaterial.ingredient] ?? 0,
            'requiredLevel': r.level,
            'unlocked': (c.facilities[CampFacility.kitchen] ?? 0) >= r.level
          }
      ],
      'training': [
        for (final l in CampCatalog.lessons.values)
          {
            'id': l.id,
            'label': _label(l.id),
            'woodCost': l.cost[CampMaterial.wood] ?? 0,
            'stoneCost': l.cost[CampMaterial.stone] ?? 0,
            'ingredientCost': l.cost[CampMaterial.ingredient] ?? 0,
            'requiredLevel': l.level,
            'unlocked': (c.facilities[CampFacility.training] ?? 0) >= l.level
          }
      ],
      'dex': [
        for (final s in _species)
          {
            'id': s.id,
            'name': s.nameKo,
            'sprite': s.sprite,
            'attribute': s.attribute.name,
            'role': CampCatalog.roleFor(s.id)?.name ?? '',
            'description': s.hint,
            'collected': (_counts[s.id] ?? 0) > 0,
            'count': _counts[s.id] ?? 0
          }
      ],
      'fishingRecords': game.fishing.totalRecords,
      'fishingError': game.fishing.error ?? '',
      'rewardStatus': '활동 연동 준비 중 · 주행 거리와 창밖 보기 재료만 반영돼요',
    };
  }

  Map<String, dynamic> _facility(BaseCamp c, CampFacility f,
      bool Function(Map<CampMaterial, int>) affordable) {
    final level = c.facilities[f] ?? 0;
    final cost = level < CampCatalog.maxLevel
        ? CampCatalog.buildCost(level + 1)
        : <CampMaterial, int>{};
    final worker = c.assignments[CampRole.builder];
    return {
      'id': f.name,
      'label': switch (f) {
        CampFacility.workshop => '작업장',
        CampFacility.kitchen => '주방',
        CampFacility.training => '훈련장'
      },
      'level': level,
      'woodCost': cost[CampMaterial.wood] ?? 0,
      'stoneCost': cost[CampMaterial.stone] ?? 0,
      'unlocked': level > 0,
      'canUpgrade': camp.ready &&
          (f == CampFacility.workshop ||
              (c.facilities[CampFacility.workshop] ?? 0) > 0) &&
          level < CampCatalog.maxLevel &&
          worker != null &&
          !c.isBusy(worker) &&
          !c.jobs.containsKey(CampRole.builder) &&
          affordable(cost)
    };
  }

  Map<String, dynamic> _job(BaseCamp c, CampJob j) {
    final work = switch (j.role) {
      CampRole.builder => CampCatalog.buildWorkMs(
          (c.facilities[CampFacility.values.byName(j.contentId)] ?? 0) + 1),
      CampRole.cook => CampCatalog.recipes[j.contentId]!.workMs,
      CampRole.trainer => CampCatalog.lessons[j.contentId]!.workMs
    };
    return {
      'id': j.taskId,
      'role': j.role.name,
      'label': _label(j.contentId),
      'workerId': j.workerId,
      'targetId': j.targetId ?? (j.role == CampRole.builder ? j.contentId : ''),
      'progress': (1 - j.remainingWorkUnits / (work * 1000)).clamp(0.0, 1.0),
      'remainingSec': (j.remainingWorkUnits / (j.speedMilli * 1000)).ceil()
    };
  }

  static String _campError(String? code) => switch (code) {
        null => '',
        'missing_worker' => '해당 역할의 친구를 먼저 배정해 주세요.',
        'insufficient_materials' => '재료가 부족해요. 주행이나 창밖 보기로 모아 주세요.',
        'facility_locked' => '작업장을 먼저 짓거나 필요한 시설 레벨을 올려 주세요.',
        'role_busy' || 'creature_busy' => '진행 중인 작업을 마치거나 취소해 주세요.',
        'invalid_worker' => '친구의 고정 역할에 맞게 배정해 주세요.',
        'missing_food' => '주방에서 음식을 먼저 만들어 주세요.',
        'already_learned' => '이미 배운 행동이에요. 다른 훈련을 골라 주세요.',
        'max_level' => '이미 최고 레벨이에요.',
        'save_failed' => '캠프를 저장하지 못했어요. 다시 시도해 주세요.',
        'not_ready' ||
        'load_failed' ||
        'invalid_data' ||
        'ownership_read_failed' =>
          '캠프를 불러오지 못했어요. 새로고침해 주세요.',
        _ => '캠프 요청을 처리하지 못했어요. 친구와 작업 조건을 확인해 주세요.',
      };

  static String _label(String id) =>
      const {
        'berry_snack': '베리 간식',
        'travel_soup': '여행 수프',
        'picnic_feast': '소풍 만찬',
        'greeting': '인사',
        'cheer': '응원',
        'look_around': '둘러보기',
        'workshop': '작업장',
        'kitchen': '주방',
        'training': '훈련장'
      }[id] ??
      id;

  void _changed() {
    if (_disposed) return;
    if (_pending == 0 && game.error == null) _egg = _readEgg();
    final hatch = game.game.stage == Stage.hatched ? game.eggId : null;
    if (hatch != null && hatch != _countedHatch) {
      _countedHatch = hatch;
      unawaited(_readCounts().then((_) => _changed()));
    }
    _revision++;
    notifyListeners();
    _publish();
  }

  void _publish() {
    if (!_unityReady || _disposed) return;
    _send?.call(jsonEncode(snapshot));
    _send?.call(sceneMessage(_stabilizer.update(
        WindowScene.fromVehicle(game.vehicle),
        DateTime.now().millisecondsSinceEpoch)));
    _send?.call(
        castMessage(companion: game.hatched, friends: game.collectedSpecies));
    _send?.call(routeMessage(game.vehicle?.turns ?? const [],
        headingDeg: game.vehicle?.headingDeg));
    _send?.call(jsonEncode({
      ...jsonDecode(settingsMessage(
          gyro: gyro,
          reducedMotion: reducedMotion,
          canEndTrip: game.isFake &&
              !game.sessionEnded &&
              !game.endingSession)) as Map<String, dynamic>,
      'appMode': true
    }));
  }

  static const _views = {
    'home',
    'cabin',
    'camp',
    'dex',
    'inventory',
    'settings'
  };
  static const _eggActions = {
    'petEgg',
    'placeEgg',
    'speech',
    'submitSpeech',
    'photo',
    'recoverPhoto',
    'discardEgg'
  };
  static const _actions = {
    'navigate',
    'startEgg',
    'pair',
    'disconnect',
    'refresh',
    'endTrip',
    'petEgg',
    'placeEgg',
    'speech',
    'submitSpeech',
    'photo',
    'recoverPhoto',
    'discardEgg',
    'assign',
    'build',
    'cook',
    'train',
    'cancel',
    'feedFood',
    'performAction',
    'selectCarCompanion',
    'retryFishingSave',
    'settings'
  };
  static bool _string(Object? value, [int max = 256]) =>
      value is String && value.trim().isNotEmpty && value.length <= max;
  bool _currentEgg(Map<String, dynamic> m) =>
      !_disconnected &&
      _stoppedRoundTier == null &&
      view == 'cabin' &&
      m['eggId'] == game.eggId &&
      game.affinityRound != null &&
      !game.affinityRound!.isTerminal &&
      !game.sessionEnded &&
      game.game.stage == Stage.incubating;
  bool _valid(Map<String, dynamic> m) {
    if (m['v'] != 1 ||
        m['type'] != 'appAction' ||
        !_string(m['requestId'], 128) ||
        !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(m['requestId'] as String) ||
        !_actions.contains(m['action'])) {
      return false;
    }
    if (_eggActions.contains(m['action']) &&
        (!_string(m['eggId'], 200) || !_currentEgg(m))) {
      return false;
    }
    return switch (m['action']) {
      'navigate' => _views.contains(m['view']),
      'startEgg' => {'small', 'mid', 'large'}.contains(m['tier']),
      'pair' => _string(m['sessionId'], 36) &&
          m['pairCode'] is String &&
          RegExp(r'^\d{6}$').hasMatch(m['pairCode'] as String),
      'placeEgg' => m['zone'] is int && m['zone'] >= 0 && m['zone'] <= 3,
      'submitSpeech' =>
        _string(m['text'], 1000) && (m['text'] as String).runes.length <= 500,
      'assign' => CampRole.values.any((r) => r.name == m['role']) &&
          m['creatureId'] is String &&
          (m['creatureId'] as String).length <= 256,
      'cancel' => CampRole.values.any((r) => r.name == m['role']),
      'build' => CampFacility.values.any((f) => f.name == m['facility']),
      'cook' => CampCatalog.recipes.containsKey(m['recipeId']),
      'train' => CampCatalog.lessons.containsKey(m['actionId']) &&
          _string(m['targetId']),
      'feedFood' => CampCatalog.recipes.containsKey(m['recipeId']) &&
          _string(m['creatureId']),
      'selectCarCompanion' => _string(m['creatureId']),
      'performAction' => CampCatalog.lessons.containsKey(m['actionId']) &&
          _string(m['creatureId']),
      'settings' => m['gyro'] is bool && m['reducedMotion'] is bool,
      _ => true,
    };
  }

  Future<bool> handleMessage(String json) async {
    if (_disposed || json.length > 8192) return false;
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return false;
    }
    if (decoded is! Map<String, dynamic>) return false;
    final m = decoded;
    if (m['v'] == 1 && m['type'] == 'appLifecycle' && m['active'] is bool) {
      _unityActive = m['active'] as bool;
      await _syncGameActive();
      _changed();
      return true;
    }
    if (m['type'] == 'ready') {
      _unityReady = true;
      _publish();
      return true;
    }
    if (m['type'] != 'appAction') {
      if (view != 'cabin' || game.sessionEnded || _disconnected) return false;
      switch (m['type']) {
        case 'lookTogether':
        case 'spotted':
          if (m['type'] == 'spotted' && !_string(m['id'], 128)) return false;
          game.lookOut();
          return true;
        case 'tap':
          if (m['kind'] != null &&
              !{'pet', 'ball', 'plush', 'cushion', 'blanket', 'draw'}
                  .contains(m['kind'])) {
            return false;
          }
          game.playWithCompanion(m['kind'] as String?);
          return true;
        case 'feed':
          if (m['kind'] != null &&
              !{'apple', 'shell', 'acorn', 'fishbun'}.contains(m['kind'])) {
            return false;
          }
          game.feedCompanion(m['kind'] as String?);
          return true;
        case 'drink':
          game.feedCompanion('water');
          return true;
        default:
          return false;
      }
    }
    if (!_valid(m) || _handled.contains(m['requestId'])) return false;
    _handled.add(m['requestId'] as String);
    if (_handled.length > 256) _handled.remove(_handled.first);
    if (m['action'] == 'navigate') {
      view = m['view'] as String;
      _changed();
      return true;
    }
    // Native dialogs must not block navigation; validate again when they return.
    if (m['action'] == 'speech' || m['action'] == 'photo') return _capture(m);
    _pending++;
    _changed();
    final result = _tail.then((_) async {
      if (_disposed || (_eggActions.contains(m['action']) && !_currentEgg(m))) {
        return false;
      }
      _error = '';
      _notice = '';
      try {
        return await _dispatch(m);
      } catch (_) {
        _error = '요청을 처리하지 못했어요. 다시 시도해 주세요.';
        return false;
      }
    });
    _tail = result.then<void>((_) {});
    try {
      return await result;
    } finally {
      _pending--;
      if (!_disposed) {
        if (game.error == null) _egg = _readEgg();
        // Preserve saved affinity when a checkpoint fails, while still publishing errors.
        _revision++;
        notifyListeners();
        _publish();
      }
    }
  }

  Future<bool> _capture(Map<String, dynamic> m) async {
    final speech = m['action'] == 'speech';
    if (game.eggApi == null) {
      _error = '음성·사진 서버 설정이 필요해요. 연결 설정을 확인해 주세요.';
      _changed();
      return false;
    }
    if ((speech &&
            (_nativeSpeech ||
                game.speechBusy ||
                game.affinityRound!.phase != AffinityPhase.incubating ||
                game.affinityRound!.speechRemainingMs > 0)) ||
        (!speech &&
            (_nativePhoto ||
                game.photoBusy ||
                game.affinityRound!.phase != AffinityPhase.photoRequired))) {
      return false;
    }
    if (speech) {
      _nativeSpeech = true;
    } else {
      _nativePhoto = true;
    }
    _changed();
    await _syncGameActive();
    try {
      if (speech) {
        final text = await _speechInput();
        if (_disposed ||
            !_currentEgg(m) ||
            text == null ||
            !_string(text, 1000) ||
            text.runes.length > 500) {
          return false;
        }
        return await handleMessage(jsonEncode({
          ...m,
          'requestId': '${m['requestId']}:result',
          'action': 'submitSpeech',
          'text': text
        }));
      }
      final bytes = await _photoInput();
      if (_disposed ||
          !_currentEgg(m) ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > 5 * 1024 * 1024) {
        return false;
      }
      // Upload itself remains serialized with other mutations.
      _pending++;
      _changed();
      final result = _tail.then((_) async {
        if (_disposed || !_currentEgg(m)) return false;
        return await game.uploadEggPhoto(bytes) != EggFeedback.none &&
            game.error == null;
      });
      _tail = result.then<void>((_) {});
      try {
        return await result;
      } finally {
        _pending--;
      }
    } on PlatformException {
      _error = speech
          ? '음성을 시작하지 못했어요. 글로 입력해 주세요.'
          : '카메라를 시작하지 못했어요. 권한을 확인하고 다시 시도해 주세요.';
      return false;
    } on MissingPluginException {
      _error = '이 기기에서 입력을 시작할 수 없어요. 글로 입력하거나 지원 기기에서 다시 시도해 주세요.';
      return false;
    } catch (_) {
      _error = '입력을 완료하지 못했어요. 다시 시도해 주세요.';
      return false;
    } finally {
      if (speech) {
        _nativeSpeech = false;
      } else {
        _nativePhoto = false;
      }
      if (!_disposed) {
        await _syncGameActive();
        if (game.error == null) _egg = _readEgg();
        _revision++;
        notifyListeners();
        _publish();
      }
    }
  }

  Future<bool> _dispatch(Map<String, dynamic> m) async {
    switch (m['action']) {
      case 'startEgg':
        if (!_canStartEgg) return false;
        final tier = EggTier.values.byName(m['tier']);
        if (_stoppedRoundTier != null && tier != _stoppedRoundTier) {
          _error = '진행하던 알과 같은 크기를 골라 이어가 주세요.';
          return false;
        }
        game.prepareNextFakeTrip();
        final started = await game.startIncubating(tier, useAffinity: true);
        if (started) {
          _disconnected = false;
          _stoppedRoundTier = null;
        }
        return started;
      case 'pair':
        final p = PairingCredentials.parseFields(m['sessionId'], m['pairCode']);
        if (game.busy || game.endingSession) return false;
        final resumeTier = _stoppedRoundTier ??
            (game.game.stage == Stage.incubating ||
                    game.game.stage == Stage.hatched
                ? game.game.eggTier
                : null);
        // Real pairing saves and stops its old feed even for the same vehicle.
        final resume =
            resumeTier != null && (!game.isFake || _stoppedRoundTier != null);
        if (resume) _stoppedRoundTier = resumeTier;
        await game.pair(p.sessionId, pairCode: p.code);
        if (!game.paired) return false;
        _disconnected = false;
        // The core intentionally closes a saved hatch when the vehicle changes.
        if (resume && game.game.stage == Stage.idle) {
          _stoppedRoundTier = null;
          return true;
        }
        if (!resume) return true;
        final resumed =
            await game.startIncubating(resumeTier, useAffinity: true);
        if (resumed) _stoppedRoundTier = null;
        return resumed;
      case 'disconnect':
        final ok = await game.disconnect();
        if (ok) {
          _disconnected = true;
          if (game.game.stage == Stage.incubating ||
              game.game.stage == Stage.hatched) {
            _stoppedRoundTier = game.game.eggTier;
          }
        }
        return ok;
      case 'refresh':
        final ok =
            camp.ready ? await camp.refreshOwnership() : await camp.load();
        await _readCounts();
        _ready = ok;
        return ok;
      case 'endTrip':
        if (!game.isFake || game.sessionEnded) return false;
        game.endFakeTrip();
        return true;
      case 'petEgg':
        return await game.petEgg() != EggFeedback.none && game.error == null;
      case 'placeEgg':
        return await game.placeEgg(m['zone']) != EggFeedback.none &&
            game.error == null;
      case 'submitSpeech':
        if (game.eggApi == null) {
          _error = '음성 판정 서버 설정이 필요해요. 연결 설정을 확인해 주세요.';
          return false;
        }
        return await game.submitEggSpeech(m['text']) != EggFeedback.none &&
            game.error == null;
      case 'recoverPhoto':
        if (game.eggApi == null) {
          _error = '사진 서버 설정이 필요해요. 연결 설정을 확인해 주세요.';
          return false;
        }
        return await game.recoverEggPhoto() != EggFeedback.none &&
            game.error == null;
      case 'discardEgg':
        await game.discardEgg();
        return game.eggId == m['eggId'] &&
            game.affinityRound?.phase == AffinityPhase.discarded &&
            game.error == null;
      case 'assign':
        return camp.assign(CampRole.values.byName(m['role']),
            m['creatureId'] == '' ? null : m['creatureId']);
      case 'build':
        return camp.startBuild(CampFacility.values.byName(m['facility']));
      case 'cook':
        return camp.startCooking(m['recipeId']);
      case 'train':
        return camp.startTraining(m['actionId'], m['targetId']);
      case 'cancel':
        return camp.cancel(CampRole.values.byName(m['role']));
      case 'feedFood':
        return camp.feedFood(m['recipeId'], m['creatureId']);
      case 'selectCarCompanion':
        if (!game.paired ||
            game.sessionEnded ||
            game.endingSession ||
            game.busy) {
          _error = '차량에 먼저 연결한 뒤 친구를 골라 주세요.';
          return false;
        }
        final id = m['creatureId'] as String;
        final entry = await camp.ownedEntryForCreature(id);
        if (_disposed ||
            entry == null ||
            camp.state.creatures[id]?.speciesId != entry.speciesId ||
            !game.paired ||
            game.sessionEnded ||
            game.endingSession ||
            game.busy) {
          if (!_disposed) _error = '도감을 새로고침한 뒤 소유한 친구를 다시 골라 주세요.';
          return false;
        }
        return game.selectCarCompanion(entry);
      case 'retryFishingSave':
        final previousError = game.error;
        final previousFishingError = game.fishing.error;
        await game.fishing.retrySave();
        if (_disposed) return false;
        final fishingError = game.fishing.error;
        if (previousError != null &&
            previousError != previousFishingError &&
            (game.error == previousFishingError ||
                game.error == fishingError)) {
          game.error = previousError;
        } else if (fishingError == null && game.error == previousFishingError) {
          game.error = null;
        }
        return !game.fishing.hasPendingWrite && fishingError == null;
      case 'performAction':
        final result = camp.performAction(m['creatureId'], m['actionId']);
        if (result != null) _notice = _label(result);
        return result != null;
      case 'settings':
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool('unityApp.gyro', m['gyro']) ||
            !await prefs.setBool(
                'unityApp.reducedMotion', m['reducedMotion'])) {
          _error = '설정을 저장하지 못했어요.';
          return false;
        }
        gyro = m['gyro'];
        reducedMotion = m['reducedMotion'];
        return true;
    }
    return false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    game.removeListener(_changed);
    camp.removeListener(_changed);
    _send = null;
    super.dispose();
  }
}
