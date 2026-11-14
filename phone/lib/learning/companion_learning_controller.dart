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
      this.completed = const []});
  factory _Progress.fromJson(Map<String, dynamic> value) {
    final progress = _Progress(
        storyId: value['storyId'] as String,
        version: value['version'] as int,
        sceneId: value['sceneId'] as String,
        completed: List<String>.from(value['completed'] as List? ?? const []));
    if (progress.version < 1 || progress.completed.length > 100) {
      throw const FormatException('Invalid progress');
    }
    return progress;
  }
  final int version;
  final String storyId, sceneId;
  final List<String> completed;
  Map<String, dynamic> toJson() => {
        'storyId': storyId,
        'version': version,
        'sceneId': sceneId,
        'completed': completed
      };
  _Progress copy({String? sceneId, List<String>? completed}) => _Progress(
      storyId: storyId,
      version: version,
      sceneId: sceneId ?? this.sceneId,
      completed: completed ?? this.completed);
}

/// Owns presentation lifetime and saved checkpoints; the server owns every turn.
class CompanionLearningController extends ChangeNotifier {
  CompanionLearningController(
      {required LearningCatalog catalog,
      required LearningStore store,
      required LearningRequest? request,
      required Future<void> Function(String text) speak,
      required Future<void> Function() stop})
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
  Map<String, LearningCreature> _creatures = {};
  final List<Map<String, String>> _history = [];
  final Set<String> _completedRequests = {};
  String _profile = '',
      _creatureId = '',
      _text = '',
      _lastUserText = '',
      _source = '',
      _error = '',
      _title = '';
  String _conversationMode = 'closed';
  _Progress? _progress;
  bool _active = false,
      _busy = false,
      _recording = false,
      _muted = false,
      _disposed = false,
      _needsRestart = false,
      _serverCanNext = false;
  int _generation = 0,
      _outputSequence = 0,
      _contextGeneration = 0,
      _turnSequence = 0;
  Future<void> _writeTail = Future.value();
  String get creatureId => _creatureId;
  String get speciesId => _creatures[_creatureId]?.speciesId ?? '';
  String get conversationMode => _conversationMode;
  bool get active => _active;
  bool get recording => _recording;
  bool get muted => _muted;
  int get generation => _generation;
  int get contextGeneration => _contextGeneration;
  LearningStory? get _story => _catalog.stories[speciesId];
  bool get _canTalk =>
      !_disposed &&
      _active &&
      !_recording &&
      !_busy &&
      _story != null &&
      _progress != null;
  List<Map<String, String>> get history =>
      [for (final item in _history) Map.unmodifiable(item)];
  Map<String, dynamic> get snapshot => {
        'creatureId': _creatureId,
        'speciesId': speciesId,
        'invitationOpen': _conversationMode == 'menu',
        'conversationMode': _conversationMode,
        'invitationText': _conversationMode == 'menu' ? _text : '',
        'name': _creatures[_creatureId]?.name ?? '',
        'target': _creatureId.isEmpty ? 'egg' : 'companion',
        'storyId': _story?.id ?? '',
        'sceneId': _progress?.sceneId ?? '',
        'title': _title,
        'text': _text,
        'lastUserText': _lastUserText,
        'source': _source,
        'error': _error,
        'busy': _busy,
        'available': _story != null,
        'active': _active,
        'canNext': _serverCanNext && !_needsRestart,
        'muted': _muted,
        'recording': _recording,
        'creatures': [
          for (final creature in _creatures.values) creature.toJson()
        ],
      };
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate({bool clearHistory = true, bool closeConversation = true}) {
    _generation++;
    _outputSequence++;
    _busy = false;
    if (closeConversation) {
      _conversationMode = 'closed';
      _text = '';
      _title = '';
      _source = '';
    }
    if (clearHistory) {
      _history.clear();
      _lastUserText = '';
    }
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
    final changed = profile != _profile ||
        _creatureId.isNotEmpty &&
            (!next.containsKey(_creatureId) ||
                next[_creatureId]?.speciesId != speciesId);
    _creatures = next;
    if (changed) {
      _contextGeneration++;
      invalidate();
      _profile = profile;
      _creatureId = '';
      _progress = null;
      _error = '';
      _needsRestart = false;
      _serverCanNext = false;
      _completedRequests.clear();
    }
    setActive(active);
    _notify();
  }

  void setActive(bool value) {
    if (_disposed || _active == value) return;
    _active = value;
    if (!value) invalidate(clearHistory: false);
    _notify();
  }

  void setRecording(bool value) {
    if (_disposed || _recording == value) return;
    _recording = value;
    if (value) invalidate(clearHistory: false, closeConversation: false);
    _notify();
  }

  void setMuted(bool value) {
    if (_disposed || _muted == value) return;
    _muted = value;
    _outputSequence++;
    if (value) unawaited(_stopSafely());
    _notify();
  }

  void replaceCatalog(LearningCatalog catalog) {
    _contextGeneration++;
    invalidate();
    _catalog = catalog;
    _progress = null;
    _serverCanNext = false;
    _notify();
  }

  Future<bool> select(String id) async {
    if (_disposed || id.isNotEmpty && !_creatures.containsKey(id)) return false;
    _contextGeneration++;
    invalidate();
    final generation = _generation;
    _error = '';
    _serverCanNext = false;
    _needsRestart = false;
    _completedRequests.clear();
    final story = _catalog.stories[_creatures[id]?.speciesId];
    if (id.isEmpty || story == null) {
      _creatureId = id;
      _progress = null;
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
          !story.scenes.contains(progress.sceneId)) {
        _needsRestart = progress.storyId != story.id ||
            !story.scenes.contains(progress.sceneId);
        progress = _Progress(
            storyId: story.id,
            version: story.version,
            sceneId: _needsRestart ? story.firstSceneId : progress.sceneId,
            completed:
                progress.completed.where(story.scenes.contains).toList());
        if (_needsRestart) _error = '이야기가 바뀌었어요. 다시 듣기를 눌러 주세요.';
      }
      _creatureId = id;
      _progress = progress;
      _busy = false;
      _notify();
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

  void interact() {}
  Future<void> _show(String text, String source, int generation) async {
    if (!_current(generation)) return;
    final sequence = ++_outputSequence;
    _text = text;
    _source = source;
    _notify();
    if (_active && !_muted && !_recording) {
      try {
        await _speak(text);
      } catch (_) {
        if (_current(generation) && sequence == _outputSequence) {
          _error = '소리를 재생하지 못했어요. 화면의 글을 읽어 주세요.';
          _notify();
        }
      }
    }
  }

  String _requestId() =>
      'turn_${DateTime.now().microsecondsSinceEpoch}_${++_turnSequence}';
  Future<bool> openConversation({String? requestId}) async {
    if (!_active || _disposed || _recording || _creatureId.isEmpty) {
      return false;
    }
    invalidate(clearHistory: false);
    _conversationMode = 'chat';
    if (_story == null) {
      _error = '이 친구의 대화는 준비 중이에요. 함께 놀 수 있어요.';
      _notify();
      return false;
    }
    return _turn('greet', requestId: requestId ?? _requestId());
  }

  Future<bool> openInvitation({String? requestId}) async {
    if (!_active || _disposed || _recording || _creatureId.isEmpty) {
      return false;
    }
    invalidate(clearHistory: false);
    _conversationMode = 'menu';
    if (_story == null) {
      _error = '이 친구의 이야기는 준비 중이에요. 함께 놀 수 있어요.';
      _notify();
      return true;
    }
    return _turn('invite', requestId: requestId ?? _requestId());
  }

  Future<bool> listenStory({String? requestId}) async {
    if (_conversationMode != 'menu' || !_canTalk) return false;
    invalidate(clearHistory: false);
    _conversationMode = 'story';
    return _turn('listen', requestId: requestId ?? _requestId());
  }

  bool talkToCompanion() {
    if (_conversationMode != 'menu' || !_canTalk) return false;
    invalidate(clearHistory: false);
    _conversationMode = 'chat';
    _error = '';
    _notify();
    return true;
  }

  void closeInvitation() {
    invalidate(clearHistory: false);
    _notify();
  }

  Future<bool> repeat({String? requestId}) =>
      _turn('repeat', requestId: requestId ?? _requestId());
  Future<bool> next({String? requestId}) async {
    if (!_serverCanNext || _needsRestart) return false;
    return _turn('next', requestId: requestId ?? _requestId());
  }

  Future<bool> chat(String text, {required String requestId}) =>
      _turn('chat', text: text, requestId: requestId);
  Future<bool> _turn(String action,
      {String text = '', required String requestId}) async {
    if (!_canTalk ||
        action != 'greet' &&
            action != 'chat' &&
            action != 'repeat' &&
            action != 'invite' &&
            action != 'listen' &&
            _needsRestart ||
        action == 'chat' && (text.trim().isEmpty || text.runes.length > 500) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId) ||
        _completedRequests.contains(requestId)) {
      return false;
    }
    final generation = _generation, story = _story!, progress = _progress!;
    final body = <String, dynamic>{
      'requestId': requestId,
      'action': action,
      'creatureId': _creatureId,
      'speciesId': speciesId,
      'storyId': story.id,
      'version': story.version,
      'sceneId': progress.sceneId,
      'text': text.trim(),
      'history': history,
      'allowParentPrompt': true
    };
    _busy = true;
    _error = '';
    _outputSequence++;
    _notify();
    await _stopSafely();
    if (!_current(generation)) return false;
    try {
      if (_request == null) throw StateError('unconfigured');
      final response = await _request(body);
      if (!_current(generation)) return false;
      final answer = response['text'],
          parent = response['parentPromptUsed'],
          scene = response['sceneId'];
      final mode = response['mode'],
          source = response['source'],
          title = response['title'],
          canNext = response['canNext'];
      final expectedMode = action == 'invite'
          ? 'menu'
          : (action == 'chat' || action == 'greet')
              ? 'chat'
              : 'story';
      if (['requestId', 'creatureId', 'speciesId', 'storyId', 'version']
              .any((key) => response[key] != body[key]) ||
          scene is! String ||
          !story.scenes.contains(scene) ||
          action != 'next' && scene != progress.sceneId ||
          mode != expectedMode ||
          source is! String ||
          source !=
              ((action == 'chat' || action == 'greet') ? 'ai' : 'authored') ||
          title is! String ||
          title.runes.length > 200 ||
          canNext is! bool ||
          answer is! String ||
          answer.trim().isEmpty ||
          answer.runes.length > 600 ||
          parent is! bool ||
          parent && action != 'chat') {
        throw const FormatException('Invalid companion turn');
      }
      if (!{'invite', 'greet'}.contains(action)) {
        final saved = await _save(
            progress.copy(
              sceneId: scene,
              completed: action == 'next' && scene != progress.sceneId
                  ? {...progress.completed, progress.sceneId}.toList()
                  : progress.completed,
            ),
            generation);
        if (!saved) return false;
      }
      if (!_current(generation)) return false;
      _completedRequests.add(requestId);
      if (_completedRequests.length > 64) {
        _completedRequests.remove(_completedRequests.first);
      }
      if (action == 'chat') {
        _lastUserText = text.trim();
        _history.addAll([
          {'role': 'user', 'text': text.trim()},
          {'role': 'assistant', 'text': answer}
        ]);
        if (_history.length > 12) _history.removeRange(0, _history.length - 12);
      }
      _busy = false;
      _title = title;
      _serverCanNext = canNext;
      _conversationMode = mode as String;
      if (action == 'repeat' || action == 'listen') _needsRestart = false;
      await _show(answer, source, generation);
      return _current(generation);
    } catch (_) {
      if (!_current(generation)) return false;
      _text = '';
      _source = '';
      _error = '대화에 연결하지 못했어요. 잠시 뒤 다시 눌러 주세요.';
      return false;
    } finally {
      if (_current(generation)) {
        _busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    invalidate();
    _disposed = true;
    super.dispose();
  }
}
