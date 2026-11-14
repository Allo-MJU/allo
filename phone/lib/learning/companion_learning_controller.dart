import 'dart:async';
import 'package:flutter/foundation.dart';
import 'learning_catalog.dart';
import 'learning_store.dart';

typedef LearningRequest = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body);

class _Progress {
  _Progress(
      {required this.storyId,
      required this.version,
      required this.sceneId,
      this.introduced = false,
      this.completed = const [],
      this.parentGap = 10,
      this.invited = false});
  factory _Progress.fromJson(Map<String, dynamic> value) {
    final progress = _Progress(
        storyId: value['storyId'] as String,
        version: value['version'] as int,
        sceneId: value['sceneId'] as String,
        introduced: value['introduced'] as bool,
        completed: List<String>.from(value['completed'] as List),
        parentGap: value['parentGap'] as int,
        invited: value['invited'] as bool);
    if (progress.version < 1 ||
        progress.parentGap < 0 ||
        progress.parentGap > 10 ||
        progress.completed.length > 100) {
      throw const FormatException('Invalid progress');
    }
    return progress;
  }
  final int version, parentGap;
  final String storyId, sceneId;
  final bool introduced, invited;
  final List<String> completed;
  Map<String, dynamic> toJson() => {
        'storyId': storyId,
        'version': version,
        'sceneId': sceneId,
        'introduced': introduced,
        'completed': completed,
        'parentGap': parentGap,
        'invited': invited
      };
  _Progress copy(
          {String? sceneId,
          bool? introduced,
          List<String>? completed,
          int? parentGap,
          bool? invited}) =>
      _Progress(
          storyId: storyId,
          version: version,
          sceneId: sceneId ?? this.sceneId,
          introduced: introduced ?? this.introduced,
          completed: completed ?? this.completed,
          parentGap: parentGap ?? this.parentGap,
          invited: invited ?? this.invited);
}

/// This controller owns local scene authority; generated text never supplies it.
class CompanionLearningController extends ChangeNotifier {
  CompanionLearningController(
      {required LearningCatalog catalog,
      required LearningStore store,
      required LearningRequest? request,
      required Future<void> Function(String text) speak,
      required Future<void> Function() stop,
      this.idleDuration = const Duration(minutes: 3)})
      : _catalog = catalog,
        _store = store,
        _request = request,
        _speak = speak,
        _stop = stop;
  LearningCatalog _catalog;
  final LearningStore _store;
  final LearningRequest? _request;
  final Future<void> Function(String) _speak;
  final Future<void> Function() _stop;
  final Duration idleDuration;
  Map<String, LearningCreature> _creatures = {};
  final List<Map<String, String>> _history = [];
  final Set<String> _completedRequests = {};
  String _profile = '', _creatureId = '', _text = '', _source = '', _error = '';
  _Progress? _progress;
  bool _active = false,
      _busy = false,
      _recording = false,
      _muted = false,
      _disposed = false,
      _invited = false,
      _needsRestart = false;
  int _generation = 0, _outputSequence = 0, _contextGeneration = 0;
  Timer? _idleTimer;
  // Writes remain ordered even when an old request loses its display generation.
  Future<void> _writeTail = Future.value();
  String get creatureId => _creatureId;
  String get speciesId => _creatures[_creatureId]?.speciesId ?? '';
  bool get active => _active;
  bool get recording => _recording;
  bool get muted => _muted;
  int get generation => _generation;
  int get contextGeneration => _contextGeneration;
  LearningStory? get _story => _catalog.stories[speciesId];
  LearningScene? get _scene => _story?.scenes[_progress?.sceneId];
  bool get _canTalk =>
      !_disposed && _active && !_recording && !_busy && _scene != null;
  List<Map<String, String>> get history =>
      [for (final item in _history) Map.unmodifiable(item)];
  Map<String, dynamic> get snapshot => {
        'creatureId': _creatureId,
        'speciesId': speciesId,
        'name': _creatures[_creatureId]?.name ?? '',
        'target': _creatureId.isEmpty ? 'egg' : 'companion',
        'storyId': _story?.id ?? '',
        'sceneId': _scene?.id ?? '',
        'title': _scene?.title ?? '',
        'text': _text,
        'source': _source,
        'error': _error,
        'busy': _busy,
        'available': _scene != null,
        'active': _active,
        'canNext': _scene?.nextSceneId != null && !_needsRestart,
        'muted': _muted,
        'recording': _recording,
        'creatures': [
          for (final creature in _creatures.values) creature.toJson()
        ],
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate({bool clearHistory = true}) {
    _generation++;
    _outputSequence++;
    _busy = false;
    _idleTimer?.cancel();
    if (clearHistory) _history.clear();
    unawaited(_stopSafely());
  }

  Future<void> _stopSafely() async {
    try {
      await _stop();
    } catch (_) {}
  }

  bool _current(int generation) => !_disposed && generation == _generation;
  void setContext(
      {required String profile,
      required Iterable<LearningCreature> creatures,
      required bool active}) {
    final next = {for (final creature in creatures) creature.id: creature};
    final profileChanged = profile != _profile;
    final removed = _creatureId.isNotEmpty &&
        (!next.containsKey(_creatureId) ||
            next[_creatureId]?.speciesId != speciesId);
    _creatures = next;
    if (profileChanged || removed) {
      _contextGeneration++;
      invalidate();
      _profile = profile;
      _creatureId = '';
      _progress = null;
      _text = '';
      _source = '';
      _error = '';
      _invited = false;
      _needsRestart = false;
      _completedRequests.clear();
    }
    setActive(active);
    _notify();
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    if (!value) {
      invalidate();
    } else {
      _scheduleInvite();
    }
    _notify();
  }

  void setRecording(bool value) {
    if (_disposed || _recording == value) return;
    _recording = value;
    if (value) {
      invalidate(clearHistory: false);
    } else {
      _scheduleInvite();
    }
    _notify();
  }

  void setMuted(bool value) {
    if (_disposed || _muted == value) return;
    _muted = value;
    _outputSequence++;
    if (value) {
      _idleTimer?.cancel();
      unawaited(_stopSafely());
    } else {
      _scheduleInvite();
    }
    _notify();
  }

  void replaceCatalog(LearningCatalog catalog) {
    _contextGeneration++;
    invalidate();
    _catalog = catalog;
    _progress = null;
    _text = '';
    _source = '';
    _notify();
  }

  Future<bool> select(String id) async {
    if (_disposed || id.isNotEmpty && !_creatures.containsKey(id)) return false;
    _contextGeneration++;
    invalidate();
    final generation = _generation;
    _creatureId = id;
    _progress = null;
    _text = '';
    _source = '';
    _error = '';
    _invited = false;
    _needsRestart = false;
    _completedRequests.clear();
    final story = _story;
    if (id.isEmpty || story == null) {
      if (id.isNotEmpty) _error = '이 친구의 이야기는 준비 중이에요. 함께 놀 수 있어요.';
      _notify();
      return true;
    }
    _busy = true;
    _notify();
    try {
      await _writeTail;
      if (!_current(generation)) return false;
      final saved = await _store.read(_profile, id);
      if (!_current(generation)) return false;
      var progress = saved == null
          ? _Progress(
              storyId: story.id,
              version: story.version,
              sceneId: story.firstSceneId)
          : _Progress.fromJson(saved);
      if (progress.storyId != story.id ||
          progress.version != story.version ||
          !story.scenes.containsKey(progress.sceneId)) {
        final sceneId = progress.storyId != story.id
            ? null
            : story.scenes.containsKey(progress.sceneId)
                ? progress.sceneId
                : story.migrations[progress.sceneId];
        _needsRestart = sceneId == null;
        progress = _Progress(
            storyId: story.id,
            version: story.version,
            sceneId: sceneId ?? story.firstSceneId,
            introduced: !_needsRestart && progress.introduced,
            completed:
                progress.completed.where(story.scenes.containsKey).toList(),
            parentGap: progress.parentGap,
            invited: progress.invited);
        if (_needsRestart) _error = '이야기가 바뀌어 첫 장면부터 다시 들어야 해요. 다시 듣기를 눌러 주세요.';
      }
      _progress = progress;
      _invited = progress.invited;
      _text = _scene!.text;
      _source = 'authored';
      _busy = false;
      _notify();
      if (!progress.introduced && !_needsRestart && _active) {
        return await repeat();
      }
      _scheduleInvite();
      return true;
    } catch (_) {
      if (_current(generation)) {
        _error = '이야기 진도를 불러오지 못했어요. 친구를 다시 골라 주세요.';
        _busy = false;
        _notify();
      }
      return false;
    }
  }

  Future<bool> _save(_Progress next, int generation) async {
    final profile = _profile, id = _creatureId;
    final result = _writeTail.then((_) async {
      if (!_current(generation)) return false;
      await _store.write(profile, id, next.toJson());
      return _current(generation);
    });
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    try {
      if (!await result) return false;
      _progress = next;
      return true;
    } catch (_) {
      if (_current(generation)) _error = '진도를 저장하지 못했어요. 다시 시도해 주세요.';
      return false;
    }
  }

  void interact() {
    _invited = false;
    _scheduleInvite();
  }

  Future<void> _show(String text, String source, int generation) async {
    if (!_current(generation)) return;
    final outputSequence = ++_outputSequence;
    _text = text;
    _source = source;
    _notify();
    if (_active && !_muted && !_recording) {
      try {
        await _speak(text);
      } catch (_) {
        if (_current(generation) && outputSequence == _outputSequence) {
          _error = '소리를 재생하지 못했어요. 화면의 글을 읽어 주세요.';
          _notify();
        }
      }
    }
  }

  Future<bool> repeat() async {
    if (!_canTalk) return false;
    final generation = _generation;
    final text = _scene!.text;
    _busy = true;
    _error = '';
    _idleTimer?.cancel();
    _notify();
    final ok = await _save(
        _progress!.copy(introduced: true, invited: false), generation);
    if (!_current(generation)) return false;
    _busy = false;
    if (ok) {
      _needsRestart = false;
      _invited = false;
      await _show(text, 'authored', generation);
    }
    _scheduleInvite();
    _notify();
    return ok;
  }

  Future<bool> next() async {
    if (!_canTalk || _scene!.nextSceneId == null || _needsRestart) return false;
    final generation = _generation;
    final nextScene = _story!.scenes[_scene!.nextSceneId]!;
    _busy = true;
    _error = '';
    _idleTimer?.cancel();
    _notify();
    final ok = await _save(
        _progress!.copy(
            sceneId: nextScene.id,
            introduced: true,
            completed: {..._progress!.completed, _scene!.id}.toList(),
            invited: false),
        generation);
    if (!_current(generation)) return false;
    _busy = false;
    if (ok) {
      _invited = false;
      await _show(nextScene.text, 'authored', generation);
    }
    _scheduleInvite();
    _notify();
    return ok;
  }

  Future<bool> chat(String text, {required String requestId}) async {
    if (!_canTalk ||
        _needsRestart ||
        text.trim().isEmpty ||
        text.runes.length > 500 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId) ||
        _completedRequests.contains(requestId)) {
      return false;
    }
    final generation = _generation, scene = _scene!, story = _story!;
    final allowParent = _progress!.parentGap >= 10;
    final body = <String, dynamic>{
      'requestId': requestId,
      'creatureId': _creatureId,
      'speciesId': speciesId,
      'storyId': story.id,
      'version': story.version,
      'sceneId': scene.id,
      'text': text.trim(),
      'history': history,
      'allowParentPrompt': allowParent
    };
    _busy = true;
    _outputSequence++;
    _error = '';
    _idleTimer?.cancel();
    _notify();
    await _stopSafely();
    if (!_current(generation)) return false;
    try {
      if (_request == null) throw StateError('unconfigured');
      final response = await _request(body);
      if (!_current(generation)) return false;
      final answer = response['text'], parent = response['parentPromptUsed'];
      if ([
            'requestId',
            'creatureId',
            'speciesId',
            'storyId',
            'version',
            'sceneId'
          ].any((key) => response[key] != body[key]) ||
          answer is! String ||
          answer.trim().isEmpty ||
          answer.runes.length > 600 ||
          parent is! bool ||
          parent && !allowParent) {
        throw const FormatException('Invalid learning reply');
      }
      if (!await _save(
          _progress!.copy(
              parentGap: parent ? 0 : (_progress!.parentGap + 1).clamp(0, 10),
              invited: false),
          generation)) {
        return false;
      }
      if (!_current(generation)) return false;
      _completedRequests.add(requestId);
      if (_completedRequests.length > 64) {
        _completedRequests.remove(_completedRequests.first);
      }
      _history.addAll([
        {'role': 'user', 'text': text.trim()},
        {'role': 'assistant', 'text': answer}
      ]);
      if (_history.length > 12) _history.removeRange(0, _history.length - 12);
      _busy = false;
      _invited = false;
      await _show(answer, 'ai', generation);
      return true;
    } catch (_) {
      if (!_current(generation)) return false;
      _error = '새 답변에 연결하지 못했어요. 준비된 이야기를 보여 줄게요.';
      _busy = false;
      await _show(scene.text, 'fallback', generation);
      return false;
    } finally {
      if (_current(generation)) {
        _busy = false;
        _scheduleInvite();
        _notify();
      }
    }
  }

  void _scheduleInvite() {
    _idleTimer?.cancel();
    if (!_canTalk || _muted || _invited || _needsRestart) return;
    final generation = _generation;
    _idleTimer = Timer(idleDuration, () async {
      if (!_current(generation) || !_canTalk || _muted || _invited) return;
      _invited = true;
      _busy = true;
      final ok = await _save(_progress!.copy(invited: true), generation);
      if (!_current(generation)) return;
      _busy = false;
      if (ok) {
        await _show('내 이야기를 더 듣고 싶으면 이야기 버튼을 눌러 줘.', 'invitation', generation);
      }
      _notify();
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    super.dispose();
  }
}
