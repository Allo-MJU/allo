import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../scene/window_scene.dart';
import 'story_pack.dart';
import 'story_store.dart';
export 'story_pack.dart';
export 'story_store.dart';

/// Local educational state only: never modifies affinity, materials or ownership.
class StoryDirector extends ChangeNotifier {
  StoryDirector({required List<StoryPack> packs, required this.store})
      : packs = {for (final p in packs) p.id: p};
  final Map<String, StoryPack> packs;
  final StoryStore store;
  final _cards = <String>{}, _completed = <String>{}, _handled = <String>{};
  String? _current, _candidate;
  String _node = 'intro', _instance = '', _notice = '';
  int _revision = 0,
      _now = 0,
      _lastOffer = -90000,
      _quietUntil = 0,
      _serial = 0;
  bool _paused = false,
      _pending = false,
      _canPlay = false,
      _canOffer = false,
      _connected = false,
      _disposed = false;
  String? _visibleOffer, _weatherKey, _stableWeather;
  int _weatherSince = 0;
  WindowScene? _lastScene;
  Future<void> _writes = Future.value();
  bool get active => _current != null && !_paused;
  bool get paused => _current != null && _paused;
  bool get pending => _pending;
  StoryPack? get _pack => packs[_current];
  bool get _eligible =>
      _candidate != null &&
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
      'cardCount': _cards.length,
      'savedCards': _cards
          .where(packs.containsKey)
          .map((id) => {
                'id': id,
                'topicId': id,
                'title': packs[id]!.cardTitle,
                'text': packs[id]!.cardText
              })
          .toList(),
      'library': packs.values
          .map((p) => {
                'id': p.id,
                'topicId': p.id,
                'title': p.title,
                'text': p.invitation
              })
          .toList()
    };
  }

  Future<void> initialize() async {
    try {
      final raw = await store.read();
      if (raw == null || _disposed) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1) return;
      for (final id in data['cards'] as List? ?? []) {
        if (id is String && packs.containsKey(id)) _cards.add(id);
      }
      final saved = data['session'];
      if (saved is Map && packs.containsKey(saved['topicId'])) {
        final pack = packs[saved['topicId']]!;
        if (saved['packVersion'] == pack.version &&
            pack.nodes.containsKey(saved['nodeId'])) {
          _current = pack.id;
          _node = saved['nodeId'] as String;
          _paused = true;
          _instance = 'restored-${DateTime.now().microsecondsSinceEpoch}';
        }
      }
    } catch (_) {
      _notice = '이전 이야기를 불러오지 못했어요.';
    }
    _emit();
  }

  /// Feed the same already-stabilized scene as Unity; speed never selects topics.
  void updateContext(
      {required WindowScene scene,
      required int nowMs,
      required bool canOffer,
      required bool canPlay,
      required bool connected}) {
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
    if (!active) return;
    _paused = true;
    _emit();
    _persistLater();
  }

  bool _validNode(Map<String, dynamic> m) =>
      m['instanceId'] == _instance &&
      m['nodeId'] == _node &&
      m['storyRevision'] == _revision;
  Future<bool> handle(String action, Map<String, dynamic> intent) async {
    if (_disposed) return false;
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
      if (id == null || !packs.containsKey(id) || (!explicit && !_available)) {
        return false;
      }
      _current = id;
      _node = 'intro';
      _paused = false;
      _instance = 'story-$_now-${++_serial}';
      _notice = explicit && !_connected ? '지금은 상상 탐험이야. 준비된 이야기로 놀아 보자.' : '';
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
          _node = 'choose';
        } else {
          final choices = _pack!.nodes[_node]!.choices
              .where((c) => c.id == intent['actionId']);
          if (choices.isEmpty) return false;
          final next = choices.first.next;
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
    _remember(request);
    _pending = true;
    _notice = '';
    _emit();
    try {
      await _enqueue(_encoded(cards: {..._cards, id}, node: 'saved'));
      if (_disposed) return false;
      _cards.add(id);
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

  String _encoded({Set<String>? cards, String? node}) => jsonEncode({
        'version': 1,
        'cards': (cards ?? _cards).toList(),
        'session': _current == null
            ? null
            : {
                'topicId': _current,
                'packVersion': _pack!.version,
                'nodeId': node ?? _node
              }
      });
  Future<void> _enqueue(String value) {
    final next = _writes.then((_) => store.write(value));
    _writes = next.catchError((Object _) {});
    return next;
  }

  void _persistLater() {
    // The pending card transaction already persists this node. Do not enqueue
    // a stale pre-save card set when navigation pauses it during the write.
    if (_pending) return;
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
    super.dispose();
  }
}
