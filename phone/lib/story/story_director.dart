import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../scene/window_scene.dart';
import 'story_pack.dart';
import 'story_store.dart';
export 'story_pack.dart';
export 'story_store.dart';

/// Local educational state only: never modifies affinity, materials or ownership.
class StoryDirector extends ChangeNotifier {
  StoryDirector(
      {required List<StoryPack> packs,
      required this.store,
      this.playableTopics})
      : packs = {for (final p in packs) p.id: p},
        _owner = StoryStoreOwner(store);
  final Set<String>? playableTopics;
  final StoryStoreOwner _owner;
  bool _playable(String id) => playableTopics?.contains(id) ?? true;
  final Map<String, StoryPack> packs;
  final StoryStore store;
  final _cards = <String>{}, _completed = <String>{}, _handled = <String>{};
  final _records = <String, Map<String, String>>{};
  Map<String, dynamic>? _retainedSession;
  Map<String, String> _evidence = {};
  bool _observedA = false, _observedB = false, _explained = false;
  bool _initialized = false;
  bool get _ownsStore => !_disposed && _owner.owns;
  bool get _writable => _initialized && _ownsStore;
  static const _evidenceFields = [
    'prediction',
    'firstAction',
    'observation',
    'principle',
    'nextQuestion'
  ];
  static Map<String, String> _readEvidence(dynamic value) {
    if (value != null && value is! Map) {
      throw const FormatException('Invalid story evidence');
    }
    final result = <String, String>{};
    if (value is Map) {
      for (final field in _evidenceFields) {
        if (!value.containsKey(field)) continue;
        if (value[field] is! String) {
          throw const FormatException('Invalid story evidence field');
        }
        result[field] = value[field] as String;
      }
    }
    return result;
  }

  String? _current, _candidate;
  String _node = 'intro', _instance = '', _notice = '';
  int _revision = 0, _now = 0, _lastOffer = -90000, _quietUntil = 0;
  static int _serial = 0;
  bool _paused = false,
      _pending = false,
      _canPlay = false,
      _canOffer = false,
      _connected = false,
      _disposed = false;
  String? _visibleOffer, _weatherKey, _stableWeather;
  int _weatherSince = 0;
  WindowScene? _lastScene;
  Future<void> flush() => _owner.flush();
  bool get active => _current != null && !_paused;
  bool get paused => _current != null && _paused;
  bool get pending => _pending;
  StoryPack? get _pack => packs[_current];
  bool get _eligible =>
      _candidate != null &&
      _playable(_candidate!) &&
      _canOffer &&
      _connected &&
      _now >= _quietUntil &&
      !_completed.contains(_candidate);
  bool get _available =>
      _eligible && (_visibleOffer == _candidate || _now - _lastOffer >= 90000);
  Map<String, dynamic> get snapshot {
    final pack = _pack ?? packs[_candidate];
    final node = _pack?.nodes[_node];
    return {
      'available': _available && _current == null,
      'active': active,
      'paused': paused,
      'pending': _pending,
      'canPlay': _canPlay,
      'instanceId': _instance,
      'topicId': pack?.id ?? '',
      'title': pack?.title ?? '',
      'nodeId': _node,
      'revision': _revision,
      'line': node?.line ?? pack?.invitation ?? '',
      'invitation': pack?.invitation ?? '',
      'choices': node?.choices.map((c) => c.snapshot).toList() ?? [],
      'visual': pack?.visual ?? '',
      'variant': node?.variant ?? 'neutral',
      'cardTitle': pack?.cardTitle ?? '',
      'cardText': pack?.cardText ?? '',
      'notice': _notice,
      ..._evidence,
      'cardCount': _cards.length,
      'savedCards': _cards
          .where(packs.containsKey)
          .map((id) => {
                'id': id,
                'topicId': id,
                'title': packs[id]!.cardTitle,
                'text': packs[id]!.cardText,
                ...?_records[id]
              })
          .toList(),
      'library': packs.values
          .map((p) => {
                'id': p.id,
                'topicId': p.id,
                'title': p.title,
                'text': p.invitation,
                'playable': _playable(p.id)
              })
          .toList()
    };
  }

  Future<void> initialize() async {
    _initialized = false;
    try {
      final raw = await _owner.read();
      if (!_ownsStore) return;
      final data = raw == null ? {'version': 1} : jsonDecode(raw);
      if (data is! Map || data['version'] != 1) {
        throw const FormatException('Invalid story save version');
      }
      final ids = data['cards'] ?? const [];
      final savedRecords = data['records'];
      final saved = data['session'];
      if (ids is! List ||
          ids.any((id) => id is! String) ||
          (savedRecords != null && savedRecords is! Map) ||
          (saved != null && saved is! Map)) {
        throw const FormatException('Invalid story save');
      }
      final cards = ids.cast<String>().where(packs.containsKey).toSet();
      final records = <String, Map<String, String>>{};
      if (savedRecords is Map) {
        for (final id in cards) {
          final evidence = _readEvidence(savedRecords[id]);
          if (evidence.isNotEmpty) records[id] = evidence;
        }
      }
      String? current;
      Map<String, dynamic>? retainedSession;
      var node = 'intro', instance = '', notice = '';
      var evidence = <String, String>{};
      var observedA = false, observedB = false, explained = false;
      if (saved is Map) {
        if (saved['topicId'] is! String ||
            saved['packVersion'] is! int ||
            saved['nodeId'] is! String ||
            ['observedA', 'observedB', 'explained']
                .any((key) => saved.containsKey(key) && saved[key] is! bool)) {
          throw const FormatException('Invalid story session');
        }
        final savedEvidence = _readEvidence(saved['evidence']);
        final pack = packs[saved['topicId']];
        if (pack != null) {
          if (!_playable(pack.id)) {
            retainedSession = Map<String, dynamic>.from(saved);
            notice = '바다 탐험을 시작하면 이전 미완료 탐험 대신 새로 시작해.';
          } else {
            current = pack.id;
            instance = 'restored-${DateTime.now().microsecondsSinceEpoch}';
            if (saved['packVersion'] == pack.version &&
                pack.nodes.containsKey(saved['nodeId'])) {
              node = saved['nodeId'] as String;
              evidence = savedEvidence;
              observedA = saved['observedA'] == true;
              observedB = saved['observedB'] == true;
              explained = saved['explained'] == true;
            } else {
              notice = '탐험이 새로워져 처음부터 시작해. 저장한 카드는 그대로야.';
            }
          }
        }
      }
      // Install only a fully validated save. Failed loads leave disk untouched.
      _cards
        ..clear()
        ..addAll(cards);
      _records
        ..clear()
        ..addAll(records);
      _retainedSession = retainedSession;
      _current = current;
      _paused = current != null;
      _node = node;
      _instance = instance;
      _evidence = evidence;
      _observedA = observedA;
      _observedB = observedB;
      _explained = explained;
      _notice = notice;
      _initialized = true;
      _emit();
    } catch (_) {
      _notice = '이전 이야기를 불러오지 못했어요. 다시 시도해 줘.';
      _emit();
      rethrow;
    }
  }

  /// Feed the same already-stabilized scene as Unity; speed never selects topics.
  void updateContext(
      {required WindowScene scene,
      required int nowMs,
      required bool canOffer,
      required bool canPlay,
      required bool connected}) {
    if (!_writable) return;
    final before = jsonEncode(snapshot);
    _now = nowMs;
    _canOffer = canOffer;
    _canPlay = canPlay;
    _connected = connected;
    if (!canPlay && active) {
      _paused = true;
      _notice = '이야기를 보관했어. 돌봄을 마치고 이어 하자.';
      _persistLater();
    }
    final weather = '${scene.rainLevel > 0}:${scene.night}:${scene.highway}';
    if (_weatherKey != weather) {
      _weatherKey = weather;
      _weatherSince = nowMs;
    }
    final old = _lastScene;
    String? env;
    if (connected) {
      if (scene.kind == SceneKind.tunnel) {
        env = 'tunnel';
      } else if (nowMs - _weatherSince >= 5000 && _stableWeather != weather) {
        final previous = (_stableWeather ?? 'false:false:false').split(':');
        if (scene.rainLevel > 0 && previous[0] != 'true') {
          env = 'rain';
        } else if (scene.night && previous[1] != 'true') {
          env = 'night';
        } else if (old == null || old.kind != scene.kind) {
          env = scene.kind.name;
        } else if (scene.highway && previous[2] != 'true') {
          env = 'highway';
        } else {
          env = scene.kind.name;
        }
        _stableWeather = weather;
      } else if (old == null || old.kind != scene.kind) {
        env = scene.kind.name;
      }
      if (_candidate != null && !_matches(packs[_candidate]!, scene)) {
        _candidate = null;
      }
      if (env != null) {
        final found = packs.values.where((p) => p.environment == env);
        if (found.isNotEmpty) _candidate = found.first.id;
      }
      _lastScene = scene;
    } else {
      _candidate = null;
      _lastScene = null;
      _weatherKey = null;
      _stableWeather = null;
    }
    if (_available && _current == null && _visibleOffer != _candidate) {
      _visibleOffer = _candidate;
      _lastOffer = _now;
    }
    if (!_eligible) _visibleOffer = null;
    if (before != jsonEncode(snapshot)) _emit();
  }

  bool _matches(StoryPack p, WindowScene s) => switch (p.environment) {
        'rain' => s.rainLevel > 0 && s.kind != SceneKind.tunnel,
        'night' => s.night && s.kind != SceneKind.tunnel,
        'highway' => s.highway && s.kind != SceneKind.tunnel,
        _ => p.environment == s.kind.name
      };
  void pause() {
    if (!_writable || !active) return;
    _paused = true;
    _emit();
    _persistLater();
  }

  bool _validNode(Map<String, dynamic> m) =>
      m['instanceId'] == _instance &&
      m['nodeId'] == _node &&
      m['storyRevision'] == _revision;
  Future<bool> handle(String action, Map<String, dynamic> intent) async {
    if (!_writable) return false;
    final request = intent['requestId'];
    if (request is! String ||
        request.isEmpty ||
        request.length > 128 ||
        _handled.contains(request)) {
      return false;
    }
    if (!{
      'storyStart',
      'storyChoose',
      'storyPause',
      'storyResume',
      'storySave',
      'storyDismiss',
      'storyReplay',
      'storyClose'
    }.contains(action)) {
      return false;
    }
    if (_pending) {
      // Care return remains available while a card write is in flight.
      if (action != 'storyPause' || !active || !_validNode(intent)) {
        return false;
      }
      _remember(request);
      pause();
      return true;
    }
    if (action == 'storyStart') {
      if (!_canPlay || _current != null) return false;
      final target = intent['topicId'];
      final explicit = target is String && target.isNotEmpty;
      final id = explicit ? target : _candidate;
      if (id == null ||
          !packs.containsKey(id) ||
          !_playable(id) ||
          (!explicit && !_available)) {
        return false;
      }
      final replaced = _retainedSession != null;
      _retainedSession = null;
      _resetEvidence();
      _current = id;
      _node = 'intro';
      _paused = false;
      _instance = 'story-$_now-${++_serial}';
      _notice = replaced
          ? '이전 미완료 탐험 대신 바다 탐험을 시작했어.'
          : explicit && !_connected
              ? '지금은 상상 탐험이야. 준비된 이야기로 놀아 보자.'
              : '';
    } else if (action == 'storyDismiss') {
      if (_current != null) return false;
      _quietUntil = _now + 180000;
      _visibleOffer = null;
    } else {
      if (_current == null || !_validNode(intent)) return false;
      if (action == 'storyPause') {
        _paused = true;
      } else if (action == 'storyClose') {
        _current = null;
        _paused = false;
      } else if (action == 'storyResume') {
        if (!_canPlay || !_paused) return false;
        _paused = false;
      } else {
        if (!_canPlay || !active) return false;
        if (action == 'storySave') {
          if (_node != 'ending') return false;
          return _save(request);
        }
        if (action == 'storyReplay') {
          _resetEvidence();
          _node = _current == 'coast_sail' ? 'prediction' : 'choose';
        } else {
          final choices = _pack!.nodes[_node]!.choices
              .where((c) => c.id == intent['actionId']);
          if (choices.isEmpty) return false;
          final next = choices.first.next;
          if (_current == 'coast_sail') {
            if (_node == 'prediction') {
              _evidence['prediction'] = choices.first.id == 'a'
                  ? '돛을 펼친 배가 더 멀리 갈 것 같았어.'
                  : '돛을 접은 배가 더 멀리 갈 것 같았어.';
            } else if (_node == 'choose') {
              _evidence['firstAction'] = choices.first.label;
            }
            if (next == 'prediction') _resetEvidence();
            if (next == 'react_a' || next == 'second_a') _observedA = true;
            if (next == 'react_b' || next == 'second_b') _observedB = true;
            if (next == 'discovery' && _observedA && _observedB) {
              _evidence['observation'] = '같은 시간 동안 돛을 펼친 배가 더 멀리 갔어.';
            }
            if (next == 'explain') {
              _explained = true;
              _evidence['principle'] = '바람이 펼쳐진 돛을 밀어 배를 움직일 수 있어.';
              _evidence['nextQuestion'] = '바람으로 움직이는 다른 물건도 있을까?';
            }
          }
          if (next == '@save') return _save(request);
          if (next == '@close') {
            _current = null;
            _paused = false;
          } else {
            _node = next;
          }
        }
      }
      _notice = '';
    }
    _remember(request);
    _emit();
    _persistLater();
    return true;
  }

  Future<bool> _save(String request) async {
    final id = _current!;
    if (id == 'coast_sail' &&
        (!_observedA ||
            !_observedB ||
            !_explained ||
            !_evidenceFields.every(_evidence.containsKey))) {
      return false;
    }
    final record = Map<String, String>.from(_evidence);
    final records = {..._records, if (record.isNotEmpty) id: record};
    _remember(request);
    _pending = true;
    _notice = '';
    _emit();
    try {
      await _enqueue(
          _encoded(cards: {..._cards, id}, node: 'saved', records: records));
      if (!_writable) return false;
      _cards.add(id);
      if (record.isNotEmpty) _records[id] = record;
      _completed.add(id);
      _node = 'saved';
      _notice = '오늘의 발견을 여행 노트에 담았어.';
      return true;
    } catch (_) {
      if (!_disposed) _notice = '카드를 저장하지 못했어. 다시 해 볼까?';
      return false;
    } finally {
      _pending = false;
      if (!_disposed) _emit();
    }
  }

  void _remember(String id) {
    _handled.add(id);
    if (_handled.length > 256) _handled.remove(_handled.first);
  }

  void _resetEvidence() {
    _evidence = {};
    _observedA = _observedB = _explained = false;
  }

  String _encoded(
          {Set<String>? cards,
          String? node,
          Map<String, Map<String, String>>? records}) =>
      jsonEncode({
        'version': 1,
        'cards': (cards ?? _cards).toList(),
        'records': records ?? _records,
        'session': _current == null
            ? _retainedSession
            : {
                'topicId': _current,
                'packVersion': _pack!.version,
                'nodeId': node ?? _node,
                'evidence': _evidence,
                'observedA': _observedA,
                'observedB': _observedB,
                'explained': _explained
              }
      });
  Future<void> _enqueue(String value) => _owner.write(value);

  void _persistLater() {
    // The pending card transaction already persists this node. Do not enqueue
    // a stale pre-save card set when navigation pauses it during the write.
    if (_pending || !_writable) return;
    _enqueue(_encoded()).catchError((Object _) {
      if (!_disposed && !_pending) {
        _notice = '진행을 저장하지 못했어. 다시 시도해 줘.';
        _emit();
      }
    });
  }

  void _emit() {
    if (!_disposed) {
      _revision++;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _owner.release();
    super.dispose();
  }
}
