import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../affinity/egg_demo_api.dart';
import '../base_camp/base_camp_controller.dart';
import '../game/game_controller.dart';
import 'travel_history_store.dart';

class TravelPlace {
  const TravelPlace(
      {required this.placeId, required this.name, required this.region});
  final String placeId, name, region;
}

class CompanionQuestCoordinator extends ChangeNotifier {
  CompanionQuestCoordinator(
      {required this.game,
      required this.camp,
      TravelHistoryStore? historyStore,
      Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
          templateRequest,
      Future<List<TravelPlace>> Function()? loadPlaces,
      int Function()? nowMs,
      this.onTravelRequest})
      : _historyStore = historyStore ?? TravelHistoryStore(),
        _allowHistory = historyStore != null || !game.isFake,
        _templateRequest = templateRequest,
        _loadPlaces = loadPlaces ?? _readPlaces,
        _nowMs = nowMs ?? _clock {
    camp.addListener(_changed);
  }
  final GameController game;
  final BaseCampController camp;
  final TravelHistoryStore _historyStore;
  final bool _allowHistory;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      _templateRequest;
  final Future<List<TravelPlace>> Function() _loadPlaces;
  final int Function() _nowMs;
  final Future<bool> Function(
          String creatureId, String questId, String region, String placeId)?
      onTravelRequest;
  static int _clock() => DateTime.now().millisecondsSinceEpoch;
  static Future<List<TravelPlace>> _readPlaces() async {
    final data = jsonDecode(
        await rootBundle.loadString('assets/data/travel_places.json')) as Map;
    return (data['places'] as List)
        .map((e) => TravelPlace(
            placeId: e['id'] as String,
            name: e['name'] as String,
            region: e['region'] as String))
        .toList();
  }

  static const _stories = {
    'road_sprout',
    'breeze_wyrm',
    'cloud_strider',
    'dewcap',
    'dune_roller',
    'ember_crab',
    'pebble_orbit',
    'puddle_pip',
    'sea_mist',
    'storm_lantern',
    'lamp_moth',
    'highway_comet'
  };
  TravelHistorySnapshot _history = TravelHistorySnapshot.unknown;
  List<TravelPlace> _places = [];
  final Map<String, Map<String, dynamic>> _bodies = {};
  final Set<String> _opened = {}, _busy = {};
  final Map<String, String> _errors = {};
  bool _disposed = false;
  bool _active = true, _initialized = false;
  int _generation = 0;
  final Map<String, int> _openGeneration = {};
  Timer? _historyTimer;
  bool _refreshing = false;
  int get _now => max(_nowMs(), camp.state.nowMs);
  void _changed() {
    if (!_disposed && _active) notifyListeners();
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _generation++;
    _historyTimer?.cancel();
    _historyTimer = null;
    _refreshing = false;
    _busy.clear();
    if (active && _initialized) unawaited(initialize());
  }

  bool _current(int generation) =>
      !_disposed && _active && generation == _generation;

  Future<void> initialize() async {
    _initialized = true;
    if (_disposed || !_active) return;
    final generation = _generation;
    await refresh();
    if (_current(generation)) {
      _historyTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
        if (!_refreshing &&
            camp.ready &&
            camp.state.quests.values.any((q) =>
                q.kind == CompanionQuestKind.travel &&
                q.status == CompanionQuestStatus.accepted)) {
          unawaited(refresh());
        }
      });
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed || !_active) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final results = await Future.wait<Object>([
        _allowHistory
            ? _historyStore
                .load()
                .catchError((_) => TravelHistorySnapshot.unknown)
            : Future.value(TravelHistorySnapshot.unknown),
        _loadPlaces().catchError((_) => <TravelPlace>[])
      ]);
      if (!_current(generation)) return;
      _history = results[0] as TravelHistorySnapshot;
      _places = results[1] as List<TravelPlace>;
      for (final q in camp.state.quests.values.toList()) {
        if (!_current(generation)) return;
        if (q.kind != CompanionQuestKind.travel ||
            q.status != CompanionQuestStatus.accepted) {
          continue;
        }
        for (final visit in _history.visits) {
          if (visit.placeId == q.targetPlaceId &&
              visit.companionIds.contains(q.creatureId) &&
              visit.arrivedAtMs > (q.acceptedAtMs ?? 0) &&
              visit.arrivedAtMs <= _now) {
            await camp.completeTravelQuest(q.creatureId, q.questId,
                placeId: visit.placeId,
                visitId: visit.visitId,
                arrivedAtMs: visit.arrivedAtMs,
                companionIds: visit.companionIds);
            break;
          }
        }
      }
      if (_current(generation)) _changed();
    } finally {
      if (_current(generation)) _refreshing = false;
    }
  }

  bool _due(String id) {
    try {
      final quest = camp.state.quests[id];
      if (quest?.status == CompanionQuestStatus.completed &&
          _opened.contains(quest?.questId)) {
        return false;
      }
      return camp.state.questDue(id, atMs: _now);
    } catch (_) {
      return false;
    }
  }

  String _id(String id, CompanionQuest? q, bool due) => due || q == null
      ? 'quest_${id}_${camp.state.questInvitationAtMs(id, atMs: _now)}'
      : q.questId;
  List<TravelPlace> _candidates(String? region) {
    if (!_history.known) return [];
    final result = _places
        .where((p) =>
            p.region == region && !_history.places.containsKey(p.placeId))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  String? _displayText(String creatureId, Map<String, dynamic>? body) {
    final text = body?['text'] as String?;
    if (text == null ||
        body?['kind'] != 'travel' ||
        body?['targetRegion'] != 'coast' ||
        !_history.known ||
        _candidates('coast').isEmpty) {
      return text;
    }
    final visits = _history.visits
        .where((v) =>
            v.regionTag == 'coast' &&
            v.companionIds.contains(creatureId) &&
            v.arrivedAtMs <= _now)
        .toList()
      ..sort((a, b) => b.arrivedAtMs.compareTo(a.arrivedAtMs));
    if (visits.isEmpty ||
        _now - visits.first.arrivedAtMs < 14 * 24 * 60 * 60 * 1000) {
      return text;
    }
    return '$text 전에 함께 ${visits.first.placeName}에 갔었지. 이번엔 다른 바닷가에 가 볼까?';
  }

  List<Map<String, dynamic>> get snapshot {
    if (!camp.ready || _disposed) return [];
    final state = camp.state;
    return state.creatures.values.map((creature) {
      final q = state.quests[creature.id];
      final due = _due(creature.id);
      final id = _id(creature.id, q, due);
      final body = _bodies[id];
      final kind = due ? null : q?.kind.name;
      final candidates = _candidates(body?['targetRegion'] as String?);
      return <String, dynamic>{
        'creatureId': creature.id,
        'questId': id,
        'available': due || q != null,
        'opened': _opened.contains(id),
        'busy': _busy.contains(id),
        'status': due ? 'offered' : q?.status.name,
        'kind': kind,
        'title': body?['title'],
        'text': _displayText(creature.id, body),
        'error': _errors[id],
        'requirement': kind == 'food'
            ? '간식을 먹여 주세요'
            : kind == 'story'
                ? '함께 관찰해 주세요'
                : kind == 'travel'
                    ? '선택한 장소에 함께 도착해 주세요'
                    : null,
        'targetPlaceId': q?.targetPlaceId,
        'candidates': candidates
            .map((p) =>
                {'placeId': p.placeId, 'name': p.name, 'region': p.region})
            .toList()
      };
    }).toList();
  }

  CompanionQuestKind _nextKind(CompanionQuest? previous, String species) {
    if (previous == null) return CompanionQuestKind.food;
    final story = _stories.contains(species);
    if (previous.kind == CompanionQuestKind.food && story) {
      return CompanionQuestKind.story;
    }
    if (previous.kind != CompanionQuestKind.travel &&
        _history.known &&
        _candidates('coast').isNotEmpty) {
      return CompanionQuestKind.travel;
    }
    return CompanionQuestKind.food;
  }

  bool _valid(Map<String, dynamic> r, String species, String requested) {
    bool str(Object? v) => v is String && v.isNotEmpty;
    bool nullable(Object? v) => v == null || str(v);
    final kind = r['kind'];
    return r.keys.toSet().containsAll({
          'schemaVersion',
          'templateId',
          'templateVersion',
          'speciesId',
          'kind',
          'title',
          'text',
          'storyId',
          'targetFoodId',
          'targetRegion'
        }) &&
        r['schemaVersion'] == 1 &&
        r['templateVersion'] is int &&
        (r['templateVersion'] as int) > 0 &&
        r['speciesId'] == species &&
        (kind == requested ||
            (requested == 'story' &&
                !_stories.contains(species) &&
                kind == 'food')) &&
        str(r['templateId']) &&
        str(r['title']) &&
        str(r['text']) &&
        nullable(r['storyId']) &&
        nullable(r['targetFoodId']) &&
        nullable(r['targetRegion']) &&
        (kind != 'food' || str(r['targetFoodId'])) &&
        (kind != 'story' || str(r['storyId'])) &&
        (kind != 'travel' || str(r['targetRegion']));
  }

  Future<void> open(String creatureId, {String? questId}) async {
    if (_disposed || !_active || !camp.ready) return;
    final creature = camp.state.creatures[creatureId];
    if (creature == null) return;
    final old = camp.state.quests[creatureId];
    final due = _due(creatureId);
    if (old == null && !due) return;
    final id = _id(creatureId, old, due);
    if (questId != null && questId != id || _busy.contains(id)) return;
    final token = _generation;
    final openToken = _openGeneration[creatureId] ?? 0;
    _busy.add(id);
    _errors.remove(id);
    _changed();
    try {
      final kind = due ? _nextKind(old, creature.speciesId) : old!.kind;
      final api = game.eggApi;
      final request = _templateRequest ??
          (api is HttpEggDemoApi ? api.companionQuestTemplate : null);
      if (request == null) throw StateError('No quest API');
      final response = await request({
        'speciesId': creature.speciesId,
        'kind': kind.name,
        'variant': (int.tryParse(id.split('_').last) ?? 0) % 2147483648
      });
      if (_disposed ||
          token != _generation ||
          openToken != (_openGeneration[creatureId] ?? 0) ||
          camp.state.creatures[creatureId]?.speciesId != creature.speciesId ||
          camp.state.quests[creatureId]?.questId != old?.questId ||
          _due(creatureId) != due ||
          _id(creatureId, old, due) != id ||
          !_valid(response, creature.speciesId, kind.name)) {
        throw StateError('Invalid template');
      }
      if (due) {
        final at = camp.state.questInvitationAtMs(creatureId, atMs: _now);
        final offered = CompanionQuest(
            creatureId: creatureId,
            questId: id,
            kind: CompanionQuestKind.values.byName(response['kind'] as String),
            templateId: response['templateId'] as String,
            templateVersion: response['templateVersion'] as int,
            issuedAtMs: at,
            nextEligibleAtMs: at + BaseCamp.questIntervalMs,
            targetFoodId: response['targetFoodId'] as String?);
        if (!await camp.offerQuest(offered)) throw StateError('Save failed');
      } else if (old!.templateId != response['templateId'] ||
          old.templateVersion != response['templateVersion'] ||
          old.targetFoodId != response['targetFoodId']) {
        throw StateError('Template changed');
      }
      if (_disposed ||
          token != _generation ||
          openToken != (_openGeneration[creatureId] ?? 0) ||
          camp.state.quests[creatureId]?.questId != id) {
        return;
      }
      _bodies[id] = response;
      _opened.add(id);
    } catch (_) {
      if (!_disposed &&
          token == _generation &&
          openToken == (_openGeneration[creatureId] ?? 0)) {
        _errors[id] = '부탁을 불러오지 못했어요. 다시 시도해 주세요.';
      }
    } finally {
      if (_current(token)) {
        _busy.remove(id);
        _changed();
      }
    }
  }

  Future<void> accept(String creatureId, String questId,
      {String? placeId}) async {
    final q = camp.state.quests[creatureId];
    if (_disposed ||
        !_active ||
        q?.questId != questId ||
        !_opened.contains(questId) ||
        _busy.contains(questId)) {
      return;
    }
    if (q!.kind == CompanionQuestKind.travel &&
        !_candidates(_bodies[questId]?['targetRegion'] as String?)
            .any((p) => p.placeId == placeId)) {
      return;
    }
    final token = _openGeneration[creatureId] ?? 0;
    final generation = _generation;
    _busy.add(questId);
    _changed();
    final ok =
        await camp.acceptQuest(creatureId, questId, targetPlaceId: placeId);
    if (!_current(generation)) return;
    _busy.remove(questId);
    if (!_disposed &&
        token == (_openGeneration[creatureId] ?? 0) &&
        camp.state.quests[creatureId]?.questId == questId) {
      if (ok) {
        _errors.remove(questId);
      } else {
        _errors[questId] = '부탁을 저장하지 못했어요. 다시 시도해 주세요.';
      }
      _changed();
    }
  }

  Future<void> observe(String creatureId, String questId) async {
    if (!_disposed &&
        _active &&
        _opened.contains(questId) &&
        !_busy.contains(questId) &&
        camp.state.quests[creatureId]?.questId == questId) {
      final token = _openGeneration[creatureId] ?? 0;
      final generation = _generation;
      _busy.add(questId);
      _changed();
      final ok = await camp.completeStoryQuest(creatureId, questId);
      if (!_current(generation)) return;
      _busy.remove(questId);
      if (!_disposed &&
          token == (_openGeneration[creatureId] ?? 0) &&
          camp.state.quests[creatureId]?.questId == questId) {
        if (ok) {
          _errors.remove(questId);
        } else {
          _errors[questId] = '완료를 저장하지 못했어요. 다시 시도해 주세요.';
        }
        _changed();
      }
    }
  }

  Future<void> requestTravel(String creatureId, String questId) async {
    final q = camp.state.quests[creatureId];
    final region = _bodies[questId]?['targetRegion'];
    if (_disposed ||
        !_active ||
        q?.questId != questId ||
        q?.kind != CompanionQuestKind.travel ||
        q?.status != CompanionQuestStatus.accepted ||
        q?.targetPlaceId == null ||
        region is! String ||
        _busy.contains(questId) ||
        onTravelRequest == null) {
      return;
    }
    final token = _openGeneration[creatureId] ?? 0;
    final generation = _generation;
    _busy.add(questId);
    _changed();
    try {
      final sent = await onTravelRequest!(
          creatureId, questId, region, q!.targetPlaceId!);
      if (_current(generation) &&
          token == (_openGeneration[creatureId] ?? 0) &&
          camp.state.quests[creatureId]?.questId == questId) {
        if (sent) {
          _errors.remove(questId);
        } else {
          _errors[questId] = '차량에 부탁을 전달하지 못했어요. 다시 시도해 주세요.';
        }
      }
    } catch (_) {
      if (_current(generation) &&
          token == (_openGeneration[creatureId] ?? 0) &&
          camp.state.quests[creatureId]?.questId == questId) {
        _errors[questId] = '차량에 부탁을 전달하지 못했어요. 다시 시도해 주세요.';
      }
    }
    if (_current(generation)) {
      _busy.remove(questId);
      _changed();
    }
  }

  void later(String creatureId) {
    if (_disposed || !_active) return;
    final q = camp.state.quests[creatureId];
    if (q != null) _opened.remove(q.questId);
    _openGeneration[creatureId] = (_openGeneration[creatureId] ?? 0) + 1;
    _changed();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _historyTimer?.cancel();
    camp.removeListener(_changed);
    super.dispose();
  }
}
