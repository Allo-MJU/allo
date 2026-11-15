import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

import '../affinity/egg_demo_api.dart';
import '../base_camp/base_camp_controller.dart';
import '../learning/companion_learning_controller.dart';
import '../learning/learning_catalog.dart';
import '../learning/learning_store.dart';
import '../explore/explore_messages.dart';
import '../game/game_controller.dart';
import '../quests/companion_quest_coordinator.dart';
import '../pairing/pairing_credentials.dart';
import 'unity_demo_creatures.dart';
import 'village_selection_store.dart';
import '../scene/window_scene.dart';
import '../story/story_voice_config.dart';

const _nativeInput = MethodChannel('allo/egg-input');
const _companionVoice = MethodChannel('allo/companion-voice');

/// Unity only submits intents. Existing controllers own all game and camp rules.
class UnityAppController extends ChangeNotifier {
  UnityAppController(
      {required this.game,
      required this.camp,
      this.demoCreatures = false,
      VillageSelectionStore? villageSelectionStore,
      CompanionQuestCoordinator? quests,
      CompanionLearningController? learning,
      this.pairingScanner,
      this.onStartTestConnection,
      this.onReturnToVehicle,
      Future<String?> Function()? speechInput,
      Future<Uint8List?> Function()? photoInput})
      : _villageSelectionStore =
            villageSelectionStore ?? PreferencesVillageSelectionStore(),
        _speechInput =
            speechInput ?? (() => _nativeInput.invokeMethod<String>('speech')),
        _photoInput = photoInput ??
            (() => _nativeInput.invokeMethod<Uint8List>('photo')) {
    game.addListener(_changed);
    camp.addListener(_changed);
    _egg = _readEgg();
    _learning = learning;
    _learning?.addListener(_learningChanged);
    _quests = quests ??
        CompanionQuestCoordinator(
            game: game, camp: camp, onTravelRequest: _proposeQuestTravel);
    _quests.addListener(_changed);
  }

  final GameController game;
  final BaseCampController camp;
  final Future<bool> Function()? onStartTestConnection;
  final Future<bool> Function()? onReturnToVehicle;
  late final CompanionQuestCoordinator _quests;

  Future<bool> _proposeQuestTravel(
      String creatureId, String questId, String region, String placeId) async {
    if (_disposed || !game.paired || game.sessionEnded || game.endingSession)
      return false;
    final entry = await camp.ownedEntryForCreature(creatureId);
    if (entry == null ||
        _disposed ||
        !await game.selectCarCompanion(entry, creatureId: creatureId))
      return false;
    return game.proposeQuestTravel(questId, region, placeId);
  }

  final bool demoCreatures;
  final VillageSelectionStore _villageSelectionStore;
  List<String>? _villageCreatureIds;
  String _villageSelectionRequestId = '';
  bool _villageSelectionReady = false;
  String get _villageProfile =>
      '${game.isFake ? 'demo' : 'real'}:${game.dex.namespace}:${game.dex.profile}';
  List<String> get _visibleVillageIds => !_villageSelectionReady
      ? const []
      : (_villageCreatureIds ?? camp.state.creatures.keys.take(4).toList())
          .where(camp.state.creatures.containsKey)
          .toList();

  Future<bool> _loadVillageSelection() async {
    try {
      final ids = await _villageSelectionStore.read(_villageProfile);
      if (_disposed) return false;
      _villageCreatureIds = ids;
      _villageSelectionReady = true;
      return true;
    } catch (_) {
      if (!_disposed) {
        _villageSelectionReady = false;
        _error = '마을 친구 선택을 불러오지 못했어요. 새로고침해 주세요.';
      }
      return false;
    }
  }

  Future<PairingCredentials?> Function()? pairingScanner;
  bool _scanningPairing = false;
  int _pairingGeneration = 0, _navigationGeneration = 0;
  CompanionLearningController? _learning;
  CompanionLearningController? get learning => _learning;
  final _learningRandom = math.Random.secure();
  String _careActionId = '';
  int _careSequence = 0;
  bool _nativeCompanionSpeech = false;
  int _companionInputGeneration = 0;
  String? _learningConnection;
  final Future<String?> Function() _speechInput;
  final Future<Uint8List?> Function() _photoInput;
  final _handled = <String>{};
  final _stabilizer = SceneStabilizer();
  List<Species> _species = [];
  Map<String, Map<String, dynamic>> _characters = {};
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
  String? _observedIncubatingEgg, _pendingHatchTarget;
  int _hatchTargetGeneration = 0;
  bool _bindingHatchTarget = false, _retryHatchBinding = false;
  Future<void> _tail = Future.value();
  void Function(String)? _send;
  bool _unityReady = false;
  int _bridgeGeneration = 0;

  WindowScene _shownScene = WindowScene.initial;
  bool _learningUiBlocked = false;

  void _updateScene() {
    if (_disposed) return;
    _shownScene = _stabilizer.update(WindowScene.fromVehicle(game.vehicle),
        DateTime.now().millisecondsSinceEpoch);
  }

  bool _unityActive = true;
  AppLifecycleState _hostLifecycle = AppLifecycleState.resumed;

  Future<bool> setHostLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) {
      _pairingGeneration++;
      _bridgeGeneration++;
    }
    if (_hostLifecycle != state &&
        state != AppLifecycleState.resumed &&
        !_nativeCompanionSpeech) {
      _learning?.invalidate();
    }
    _hostLifecycle = state;
    _quests.setActive(state != AppLifecycleState.detached);
    final saved = await _syncGameActive();
    _changed();
    return saved;
  }

  Future<bool> _syncGameActive() async {
    if (_disposed) return false;
    final active = _hostLifecycle != AppLifecycleState.detached &&
        (_hostLifecycle == AppLifecycleState.resumed ||
            _unityActive ||
            _nativeSpeech ||
            _nativePhoto ||
            _nativeCompanionSpeech);
    return game.setAppActive(active);
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
      final characters =
          jsonDecode(await rootBundle.loadString('assets/data/characters.json'))
              as Map<String, dynamic>;
      _characters = {
        for (final c in characters['species'] as List)
          (c as Map<String, dynamic>)['id'] as String: c
      };
      if (demoCreatures && game.isFake) {
        await seedUnityDemoCreatures(game.dex, _species);
      }
      final loaded =
          camp.ready ? await camp.refreshOwnership() : await camp.load();
      await _readCounts();
      await _loadVillageSelection();
      if (_disposed) return false;
      if (_learning == null) {
        final catalog = LearningCatalog.fromJson(jsonDecode(await rootBundle
                .loadString('assets/data/companion_learning.json'))
            as Map<String, dynamic>);
        if (_disposed) return false;
        final api = game.eggApi;
        _learning = CompanionLearningController(
            catalog: catalog,
            store: PreferencesLearningStore(),
            request: api is HttpEggDemoApi ? api.companionTurn : null,
            speak: (text) =>
                _companionVoice.invokeMethod<void>('speak', {'text': text}),
            stop: () => _companionVoice.invokeMethod<void>('stop'));
        _learning!.addListener(_learningChanged);
      }
      _ready = loaded;
      _changed();
      // Optional history and quest preparation must not hold the village startup.
      unawaited(_quests.initialize());
      return loaded;
    } catch (_) {
      _error = '앱 정보를 불러오지 못했어요. 새로고침해 주세요.';
      _changed();
      return false;
    }
  }

  Future<void> reloadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (_disposed) return;
    gyro = preferences.getBool('unityApp.gyro') ?? true;
    reducedMotion = preferences.getBool('unityApp.reducedMotion') ?? false;
    _changed();
  }

  Future<void> _readCounts() async {
    final counts = <String, int>{};
    for (final entry in await game.dex.all()) {
      counts.update(entry.speciesId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (!_disposed) _counts = counts;
  }

  void attach(void Function(String) send, {UnityAppController? replacing}) {
    if (_disposed) return;
    if (replacing != null && !identical(replacing, this)) {
      replacing.detach();
      // One Unity engine retains its last accepted revision across mode switches.
      _revision = math.max(_revision, replacing._revision) + 1;
    }
    _send = send;
    _publish();
  }

  void detach() {
    if (_disposed) return;
    _send = null;
    _unityReady = false;
    _unityActive = false;
    _bridgeGeneration++;
    _pairingGeneration++;
    _companionInputGeneration++;
    _learning?.invalidate();
  }

  Map<String, dynamic> _readEgg() {
    final r = game.affinityRound;
    final active = _stoppedRoundTier == null &&
        !_disconnected &&
        game.paired &&
        !game.sessionEnded &&
        (game.tripEggAwaitingPlan ||
            (game.game.stage == Stage.incubating &&
                r != null &&
                !r.isTerminal));
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
          ? (game.vehicle == null ? '차량 신호를 기다려요' : '도착 시간 정보가 없어요')
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
          _nativeSpeech ||
          _nativePhoto ||
          _nativeCompanionSpeech,
      'error':
          _error.isNotEmpty ? _error : game.error ?? _campError(camp.error),
      'notice': _notice.isNotEmpty ? _notice : game.pairingNotice ?? '',
      'connected': game.paired && !_disconnected && !game.sessionEnded,
      'pairingScanAvailable':
          pairingScanner != null && onReturnToVehicle == null,
      'isDemo': game.isFake,
      'testConnectionAvailable':
          game.isFake || (onStartTestConnection != null && !game.paired),
      'canReturnToVehicle': onReturnToVehicle != null,
      'canStart': false,
      'sessionEnded': game.sessionEnded,
      'collectionRewardForTrip': game.collectionRewardForTrip,
      'quests': _quests.snapshot,
      'speechAvailable': game.eggApi != null,
      'photoAvailable': game.eggApi != null,
      'gyro': gyro,
      'reducedMotion': reducedMotion,
      'learning': {
        ...?_learning?.snapshot,
        'speechAvailable':
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
        'careActionId': _careActionId,
        'careSequence': _careSequence,
      },
      'story': null,
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
      'villageCreatureIds': _visibleVillageIds,
      'villageSelectionReady': _villageSelectionReady,
      'villageSelectionRequestId': _villageSelectionRequestId,
      'creatures': [
        for (final creature in c.creatures.values)
          {
            'id': creature.id,
            'speciesId': creature.speciesId,
            'name': _characterName(creature.speciesId),
            'role': CampCatalog.roleFor(creature.speciesId)?.name ?? '',
            'sprite': _characters[creature.speciesId]?['sprite'] ??
                _species
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
      'rewardStatus': '주행·창밖 보기로 모은 재료와 거점 상태를 차량에 함께 전달해요',
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

  void _learningChanged() {
    if (_disposed) return;
    _revision++;
    notifyListeners();
    _publish();
  }

  bool get _learningActive =>
      view == 'cabin' &&
      _unityActive &&
      !_learningUiBlocked &&
      !_nativeSpeech &&
      !_nativePhoto &&
      !_disconnected &&
      game.paired &&
      !game.sessionEnded &&
      !game.endingSession &&
      _hostLifecycle != AppLifecycleState.detached &&
      (_hostLifecycle == AppLifecycleState.resumed || _unityActive);

  String _characterName(String id) =>
      _characters[id]?['nameKo'] as String? ??
      _species.where((s) => s.id == id).firstOrNull?.nameKo ??
      id;

  void _syncLearning() {
    _learning?.setContext(
        profile:
            '${game.isFake ? 'demo' : 'real'}:${game.dex.namespace}:${game.dex.profile}',
        creatures: [
          for (final c in camp.state.creatures.values.where(
              (_) => game.paired && !_disconnected && !game.sessionEnded))
            LearningCreature(
                id: c.id,
                speciesId: c.speciesId,
                name: _characterName(c.speciesId))
        ],
        active: _learningActive ||
            (_nativeCompanionSpeech &&
                !_learningUiBlocked &&
                view == 'cabin' &&
                !_disconnected &&
                game.paired &&
                !game.sessionEnded &&
                !game.endingSession));
  }

  void _changed() {
    if (_disposed) return;
    final connection =
        '${game.paired}:${game.sessionEnded}:${game.endingSession}:${game.dex.namespace}:${game.dex.profile}';
    if (_learningConnection != null && _learningConnection != connection) {
      _companionInputGeneration++;
      _pairingGeneration++;
      _observedIncubatingEgg = _pendingHatchTarget = null;
      _learning?.invalidate();
    }
    _learningConnection = connection;
    _syncLearning();
    if (_pending == 0 && game.error == null) _egg = _readEgg();
    final hatch = game.game.stage == Stage.hatched ? game.eggId : null;
    if (_ready &&
        !game.busy &&
        !game.endingSession &&
        game.game.stage == Stage.incubating) {
      _observedIncubatingEgg = game.eggId;
    } else if (hatch != null && hatch == _observedIncubatingEgg) {
      _observedIncubatingEgg = null;
      if (_learning?.creatureId == '') {
        _pendingHatchTarget = hatch;
        _hatchTargetGeneration = _companionInputGeneration;
      }
    }
    if (_pendingHatchTarget != null) {
      if (_bindingHatchTarget) {
        _retryHatchBinding = true;
      } else {
        unawaited(_bindNewHatchTarget(_pendingHatchTarget!));
      }
    }
    if (hatch != null && hatch != _countedHatch) {
      _countedHatch = hatch;
      unawaited(_readCounts().then((_) => _changed()));
    }
    _updateScene();
    _revision++;
    notifyListeners();
    _publish();
  }

  Future<void> _bindNewHatchTarget(String egg) async {
    final controller = _learning;
    if (controller == null) return;
    final generation = _hatchTargetGeneration;
    bool current() =>
        !_disposed &&
        generation == _companionInputGeneration &&
        game.paired &&
        !game.sessionEnded &&
        !game.endingSession &&
        game.error == null &&
        game.eggId == egg &&
        game.game.stage == Stage.hatched &&
        controller.creatureId.isEmpty;
    if (!current()) {
      _pendingHatchTarget = null;
      return;
    }
    _bindingHatchTarget = true;
    try {
      final species = game.hatched?.id;
      // A hatch can become visible before its ownership save has settled.
      // Later ownership notifications retry; species alone never chooses a target.
      for (final creature in camp.state.creatures.values.toList()) {
        if (creature.speciesId != species) continue;
        final owned = await camp.ownedEntryForCreature(creature.id);
        if (!current()) return;
        if (owned?.sourceEggId != egg || owned?.speciesId != species) continue;
        if (await controller.select(creature.id)) _pendingHatchTarget = null;
        return;
      }
    } finally {
      _bindingHatchTarget = false;
      final retry = _retryHatchBinding;
      _retryHatchBinding = false;
      if (_disposed ||
          generation != _companionInputGeneration ||
          game.eggId != egg ||
          game.game.stage != Stage.hatched ||
          controller.creatureId.isNotEmpty) {
        _pendingHatchTarget = null;
      } else if (retry && current() && _pendingHatchTarget != null) {
        unawaited(_bindNewHatchTarget(egg));
      }
    }
  }

  void _publish() {
    if (!_unityReady || _disposed) return;
    final selected =
        _species.where((s) => s.id == _learning?.speciesId).firstOrNull;
    final connected = game.paired && !_disconnected && !game.sessionEnded;
    final cast = jsonDecode(castMessage(
        companion: connected ? selected : null,
        friends: const [])) as Map<String, dynamic>;
    final character = connected ? _characters[_learning?.speciesId] : null;
    if (character != null) {
      cast['companion'] = {
        'id': character['id'],
        'sprite': character['sprite'],
        'attribute': character['attribute']
      };
    }
    _send?.call(jsonEncode(cast));
    _send?.call(jsonEncode(snapshot));
    _send?.call(sceneMessage(_shownScene));
    _send?.call(routeMessage(game.vehicle?.turns ?? const [],
        headingDeg: game.vehicle?.headingDeg,
        cornering: game.vehicle?.cornering));
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
    'pairing',
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
    ..._questActions,
    'navigate',
    'pair',
    'testPair',
    'returnToVehicle',
    'scanPairingQr',
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
    'setVillageFriends',
    'retryFishingSave',
    'settings',
    ..._learningActions,
    'storyUiBlocked',
    'learningUiBlocked'
  };
  static bool _string(Object? value, [int max = 256]) =>
      value is String && value.trim().isNotEmpty && value.length <= max;
  static const _questActions = {
    'openQuest',
    'laterQuest',
    'acceptQuest',
    'observeQuest',
    'requestQuestTravel'
  };

  bool _currentEgg(Map<String, dynamic> m) =>
      !_disconnected &&
      game.paired &&
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
    if (_questActions.contains(m['action'])) {
      return _string(m['creatureId']) &&
          _string(m['questId'], 200) &&
          (m['placeId'] == null ||
              m['placeId'] == '' ||
              _string(m['placeId'], 128)) &&
          camp.state.creatures.containsKey(m['creatureId']);
    }
    return switch (m['action']) {
      'storyUiBlocked' || 'learningUiBlocked' => m['blocked'] is bool,
      'navigate' => _views.contains(m['view']),
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
      'companionChat' =>
        _string(m['text'], 1000) && (m['text'] as String).runes.length <= 500,
      'companionTapped' ||
      'closeCompanionInvitation' =>
        _string(m['creatureId']) && _string(m['speciesId']),
      'learningMute' => m['value'] == null || m['value'] is bool,
      'commonCare' => _commonActions.contains(m['actionId']) && view == 'cabin',
      'setVillageFriends' => m['creatureIds'] is List &&
          (m['creatureIds'] as List).length <= 4 &&
          (m['creatureIds'] as List).every((id) => _string(id)) &&
          (m['creatureIds'] as List).toSet().length ==
              (m['creatureIds'] as List).length,
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
    if (m['v'] == 1 && m['type'] == 'storyVoiceConfigRequest') {
      final requestId = m['requestId'];
      if (requestId is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId)) {
        return false;
      }
      final response = await StoryVoiceConfig.reply(requestId);
      if (!_disposed) _send?.call(jsonEncode(response));
      return true;
    }
    if (m['v'] == 1 && m['type'] == 'appLifecycle' && m['active'] is bool) {
      final active = m['active'] as bool;
      if (_unityActive && !active && !_nativeCompanionSpeech) {
        _companionInputGeneration++;
        _learning?.closeInvitation();
      }
      _unityActive = active;
      await _syncGameActive();
      _syncLearning();
      _changed();
      return true;
    }
    if (m['type'] == 'ready') {
      _unityReady = true;
      _publish();
      return true;
    }
    if (_hostLifecycle == AppLifecycleState.detached) return false;
    if (m['type'] != 'appAction') {
      if (view != 'cabin' ||
          game.sessionEnded ||
          _disconnected ||
          !game.paired) {
        return false;
      }
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
    if (m['action'] == 'learningUiBlocked') {
      _learningUiBlocked = m['blocked'] as bool;
      _changed();
      return true;
    }
    if (m['action'] == 'storyUiBlocked') {
      // Legacy experiment signals cannot capture the direct cabin surface.
      return true;
    }
    if (m['action'] == 'navigate') {
      if (view != m['view']) {
        _navigationGeneration++;
        _pairingGeneration++;
        _companionInputGeneration++;
        _learning?.invalidate();
      }
      _learningUiBlocked = false;
      view = m['view'] as String;
      _changed();
      return true;
    }
    if (_learningActions.contains(m['action'])) return _dispatchLearning(m);
    if (_questActions.contains(m['action'])) {
      final id = m['creatureId'] as String, questId = m['questId'] as String;
      switch (m['action']) {
        case 'openQuest':
          await _quests.open(id, questId: questId);
        case 'laterQuest':
          if (!_quests.snapshot
              .any((q) => q['creatureId'] == id && q['questId'] == questId))
            return false;
          _quests.later(id);
        case 'acceptQuest':
          await _quests.accept(id, questId,
              placeId: m['placeId'] == '' ? null : m['placeId'] as String?);
        case 'observeQuest':
          await _quests.observe(id, questId);
        case 'requestQuestTravel':
          await _quests.requestTravel(id, questId);
      }
      if (!_disposed) _changed();
      return true;
    }
    if (m['action'] == 'scanPairingQr') return _scanPairingQr();
    // Native dialogs must not block navigation; validate again when they return.
    if (m['action'] == 'speech' || m['action'] == 'photo') return _capture(m);
    _pending++;
    _changed();
    final bridgeGeneration = _bridgeGeneration;
    final result = _tail.then((_) async {
      if (_disposed ||
          _hostLifecycle == AppLifecycleState.detached ||
          bridgeGeneration != _bridgeGeneration ||
          (_eggActions.contains(m['action']) && !_currentEgg(m))) {
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

  static const _commonActions = {
    'snack',
    'water',
    'ball',
    'pet',
    'plush',
    'cushion',
    'blanket'
  };
  static const _learningActions = {
    'companionTapped',
    'closeCompanionInvitation',
    'companionChat',
    'companionSpeech',
    'learningMute',
    'commonCare'
  };

  String _learningRequestId() =>
      'learning_${List.generate(16, (_) => _learningRandom.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  Future<bool> _dispatchLearning(Map<String, dynamic> m) async {
    final controller = _learning;
    if (controller == null || _disposed) return false;
    final action = m['action'];
    if (action != 'learningMute') {
      if (!_learningActive || m['creatureId'] != controller.creatureId) {
        return false;
      }
      final id = controller.creatureId;
      if (id.isNotEmpty &&
          camp.state.creatures[id]?.speciesId != controller.speciesId) {
        return false;
      }
      if (action == 'commonCare' && id.isEmpty && m['eggId'] != game.eggId) {
        return false;
      }
      if ({'companionTapped', 'closeCompanionInvitation'}.contains(action) &&
          (id.isEmpty || m['speciesId'] != controller.speciesId)) {
        return false;
      }
      if ({'companionChat', 'companionSpeech'}.contains(action) &&
          controller.conversationMode != 'chat') {
        return false;
      }
    }
    switch (action) {
      case 'companionTapped':
        _companionInputGeneration++;
        return controller.openConversation(requestId: _learningRequestId());
      case 'closeCompanionInvitation':
        _companionInputGeneration++;
        controller.closeInvitation();
        return true;
      case 'learningMute':
        controller.setMuted(m['value'] as bool? ?? !controller.muted);
        return true;
      case 'companionChat':
        return controller.chat(m['text'] as String,
            requestId: _learningRequestId());
      case 'companionSpeech':
        return _captureCompanion();
      case 'commonCare':
        return _commonCare(m['actionId'] as String);
    }
    return false;
  }

  Future<bool> _commonCare(String action) async {
    final controller = _learning;
    if (controller == null ||
        !_learningActive ||
        !_commonActions.contains(action)) {
      return false;
    }
    final target = controller.creatureId;
    final targetEgg = game.eggId;
    if (target.isEmpty) {
      if (_readEgg()['active'] != true || game.eggId == null) {
        return false;
      }
      // Reuse exactly one pet reward path. Other play never grants affinity.
      if (action == 'pet' &&
          game.affinityRound?.phase == AffinityPhase.incubating) {
        await game.petEgg();
        if (_disposed ||
            controller.creatureId != target ||
            game.eggId != targetEgg ||
            !_learningActive) {
          return false;
        }
      }
    } else {
      if (!camp.state.creatures.containsKey(target)) return false;
      // Existing counters refer to the current hatch only. Other owned friends
      // still play visually without spending camp recipes or training rewards.
      if (game.game.stage == Stage.hatched &&
          game.hatched?.id == controller.speciesId) {
        if (action == 'snack' || action == 'water') {
          game.feedCompanion(action == 'water' ? 'water' : null);
        } else {
          game.playWithCompanion(action);
        }
      }
      controller.interact();
    }
    _careActionId = action;
    _careSequence++;
    _changed();
    return true;
  }

  Future<bool> _waitForCompanionSurface(int inputGeneration) async {
    bool current() =>
        !_disposed &&
        inputGeneration == _companionInputGeneration &&
        view == 'cabin' &&
        !game.sessionEnded &&
        !_disconnected;
    if (!current()) return false;
    if (_learningActive) return true;
    final result = Completer<bool>();
    void changed() {
      if (!result.isCompleted && (!current() || _learningActive)) {
        result.complete(current() && _learningActive);
      }
    }

    addListener(changed);
    final timeout = Timer(const Duration(seconds: 3), () {
      if (!result.isCompleted) result.complete(false);
    });
    try {
      return await result.future;
    } finally {
      timeout.cancel();
      removeListener(changed);
    }
  }

  Future<bool> _captureCompanion() async {
    final controller = _learning;
    if (controller == null ||
        !_learningActive ||
        controller.creatureId.isEmpty ||
        controller.conversationMode != 'chat' ||
        controller.snapshot['available'] != true ||
        controller.snapshot['busy'] == true ||
        _nativeCompanionSpeech ||
        _nativeSpeech ||
        _nativePhoto) {
      return false;
    }
    final inputGeneration = ++_companionInputGeneration;
    final target = controller.creatureId;
    final contextGeneration = controller.contextGeneration;
    _nativeCompanionSpeech = true;
    controller.setRecording(true);
    try {
      final text = await _speechInput().timeout(const Duration(seconds: 60));
      if (!await _waitForCompanionSurface(inputGeneration) ||
          _disposed ||
          inputGeneration != _companionInputGeneration ||
          controller.creatureId != target ||
          controller.contextGeneration != contextGeneration ||
          controller.conversationMode != 'chat' ||
          view != 'cabin' ||
          game.sessionEnded ||
          _disconnected ||
          text == null ||
          !_string(text, 1000) ||
          text.runes.length > 500) {
        return false;
      }
      // The input activity is finished; API lifetime now follows real foreground state.
      _nativeCompanionSpeech = false;
      controller.setRecording(false);
      _syncLearning();
      return await controller.chat(text, requestId: _learningRequestId());
    } on PlatformException {
      _error = '음성을 시작하지 못했어요. 글로 입력해 주세요.';
      return false;
    } on MissingPluginException {
      _error = '이 기기에서는 글로 말을 걸어 주세요.';
      return false;
    } catch (_) {
      _error = '음성 입력을 완료하지 못했어요. 글로 입력해 주세요.';
      return false;
    } finally {
      _nativeCompanionSpeech = false;
      if (!_disposed) {
        controller.setRecording(false);
        _syncLearning();
        _changed();
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

  Future<bool> _pair(PairingCredentials credentials,
      {bool enterCabin = true}) async {
    if (_disposed || game.busy || game.endingSession) return false;
    final pairingView = view;
    final navigationGeneration = _navigationGeneration;
    final profile = '${game.dex.namespace}:${game.dex.profile}';
    // A repeated scan of the running demo must not toggle its live connection.
    if (!game.isFake ||
        !game.paired ||
        game.sessionEnded ||
        (game.eggId == null && !game.collectionRewardForTrip)) {
      await game.pair(credentials.sessionId, pairCode: credentials.code);
      if (game.error != null) return false;
    }
    if (_disposed ||
        !game.paired ||
        profile != '${game.dex.namespace}:${game.dex.profile}') {
      return false;
    }
    _disconnected = false;
    _stoppedRoundTier = null;
    await _quests.refresh();
    if (_disposed) return false;
    if (enterCabin &&
        view == pairingView &&
        navigationGeneration == _navigationGeneration) {
      view = 'cabin';
    }
    _changed();
    return true;
  }

  Future<bool> _testPair() async {
    if (_scanningPairing || !{'pairing', 'settings'}.contains(view)) {
      return false;
    }
    if (!game.isFake) {
      return !game.paired && onStartTestConnection != null
          ? onStartTestConnection!()
          : false;
    }
    final generation = _navigationGeneration;
    final credentials = PairingCredentials.parseFields(
        '00000000-0000-4000-8000-000000000001', '000000');
    if (game.sessionEnded && !game.sessionSaved && !await game.endSession()) {
      return false;
    }
    if (_disposed || generation != _navigationGeneration) return false;
    if (!await _pair(credentials, enterCabin: false)) return false;
    final terminal = !game.collectionRewardForTrip &&
        (game.eggId == null ||
            game.game.stage == Stage.failed ||
            game.game.stage == Stage.hatched ||
            game.affinityRound?.isTerminal == true);
    if (!terminal) {
      if (generation == _navigationGeneration) {
        view = 'cabin';
        _changed();
      }
      return true;
    }
    if (_disposed || generation != _navigationGeneration) return false;
    // A test connection can begin a new demo trip after restoring a completed egg.
    game.endFakeTrip();
    if (!await game.endSession() ||
        _disposed ||
        generation != _navigationGeneration) {
      return false;
    }
    return _pair(credentials);
  }

  Future<bool> _scanPairingQr() async {
    if (onReturnToVehicle != null) return false;
    final scan = pairingScanner;
    final scanView = view;
    if (_disposed ||
        !{'pairing', 'settings'}.contains(scanView) ||
        scan == null ||
        _scanningPairing ||
        game.busy ||
        game.endingSession) {
      return false;
    }
    final generation = ++_pairingGeneration;
    final profile = '${game.dex.namespace}:${game.dex.profile}';
    _scanningPairing = true;
    _pending++;
    _error = '';
    _changed();
    try {
      final credentials = await scan();
      if (_disposed ||
          credentials == null ||
          generation != _pairingGeneration ||
          view != scanView ||
          profile != '${game.dex.namespace}:${game.dex.profile}' ||
          _hostLifecycle == AppLifecycleState.detached) {
        return false;
      }
      return await _pair(credentials);
    } catch (_) {
      if (!_disposed && generation == _pairingGeneration) {
        _error = 'QR을 읽지 못했어요. 다시 스캔하거나 코드를 입력해 주세요.';
      }
      return false;
    } finally {
      _scanningPairing = false;
      _pending--;
      if (!_disposed) _changed();
    }
  }

  Future<bool> _dispatch(Map<String, dynamic> m) async {
    switch (m['action']) {
      case 'testPair':
        return _testPair();
      case 'returnToVehicle':
        if (_scanningPairing ||
            !{'pairing', 'settings'}.contains(view) ||
            onReturnToVehicle == null) {
          return false;
        }
        return onReturnToVehicle!();
      case 'pair':
        if (_scanningPairing || onReturnToVehicle != null) return false;
        final p = PairingCredentials.parseFields(m['sessionId'], m['pairCode']);
        return _pair(p);
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
        await _loadVillageSelection();
        await _quests.refresh();
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
      case 'setVillageFriends':
        final ids = List<String>.from(m['creatureIds'] as List);
        if (!_villageSelectionReady ||
            !camp.ready ||
            !ids.every(camp.state.creatures.containsKey)) {
          _error = '도감을 새로고침한 뒤 소유한 친구를 다시 골라 주세요.';
          return false;
        }
        try {
          await _villageSelectionStore.write(_villageProfile, ids);
        } catch (_) {
          _error = '마을 친구 선택을 저장하지 못했어요. 다시 시도해 주세요.';
          return false;
        }
        if (_disposed) return false;
        _villageCreatureIds = ids;
        _villageSelectionRequestId = m['requestId'] as String;
        _notice = '마을 친구 선택을 저장했어요.';
        return true;
      case 'selectCarCompanion':
        final inputGeneration = ++_companionInputGeneration;
        final selectionView = view;
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
            inputGeneration != _companionInputGeneration ||
            view != selectionView ||
            entry == null ||
            camp.state.creatures[id]?.speciesId != entry.speciesId ||
            !game.paired ||
            game.sessionEnded ||
            game.endingSession ||
            game.busy) {
          if (!_disposed) _error = '도감을 새로고침한 뒤 소유한 친구를 다시 골라 주세요.';
          return false;
        }
        final selected = await game.selectCarCompanion(entry, creatureId: id);
        if (!selected ||
            _disposed ||
            inputGeneration != _companionInputGeneration ||
            view != selectionView ||
            !game.paired ||
            game.sessionEnded ||
            camp.state.creatures[id]?.speciesId != entry.speciesId) {
          return false;
        }
        _learningUiBlocked = false;
        _syncLearning();
        if (await _learning?.select(id) != true ||
            _disposed ||
            inputGeneration != _companionInputGeneration ||
            view != selectionView ||
            !game.paired ||
            game.sessionEnded ||
            game.endingSession ||
            camp.state.creatures[id]?.speciesId != entry.speciesId) {
          return false;
        }
        view = 'cabin';
        _syncLearning();
        return true;
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
    _pairingGeneration++;
    _companionInputGeneration++;
    _learning?.removeListener(_learningChanged);
    _learning?.dispose();
    _quests.removeListener(_changed);
    _quests.dispose();
    game.removeListener(_changed);
    camp.removeListener(_changed);
    _send = null;
    super.dispose();
  }
}
