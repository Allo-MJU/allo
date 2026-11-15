import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StoryStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesStoryStore implements StoryStore {
  SharedPreferencesStoryStore({this.prefix = 'unityApp.story.v1'});
  final String prefix;
  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    // Refresh Flutter's cache; StoryStoreOwner also guards failed native commits.
    await preferences.reload();
    return preferences.getString(prefix);
  }

  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(prefix, value)) {
      throw StateError('Story save failed');
    }
  }
}

/// Queues writes for the storage key, including writes from a retiring owner.
class StoryStoreOwner {
  StoryStoreOwner(StoryStore store)
      : _store = store,
        _queue = store is SharedPreferencesStoryStore
            ? _preferences.putIfAbsent(store.prefix, _StoryWriteQueue.new)
            : (_stores[store] ??= _StoryWriteQueue()) {
    _queue.owner = this;
  }
  static final _preferences = <String, _StoryWriteQueue>{};
  static final _stores = Expando<_StoryWriteQueue>();
  final StoryStore _store;
  final _StoryWriteQueue _queue;
  bool get owns => identical(_queue.owner, this);
  Future<void> flush() => _queue.tail;
  Future<String?> read() async {
    await flush();
    if (!owns) return null;
    if (_queue.failedWrite) {
      if (!_queue.hasCommittedValue) {
        throw StateError('Story commit state unknown');
      }
      return _queue.committedValue;
    }
    final value = await _store.read();
    if (!owns) return null;
    _queue.committedValue = value;
    _queue.hasCommittedValue = true;
    return value;
  }

  Future<void> write(String value) {
    if (!owns) return Future.error(StateError('Story owner replaced'));
    final next = _queue.tail.then((_) async {
      try {
        await _store.write(value);
        _queue.committedValue = value;
        _queue.hasCommittedValue = true;
        _queue.failedWrite = false;
      } catch (_) {
        // Android may update native memory before a disk commit reports failure.
        // Keep the last acknowledged value across owners until a write succeeds.
        _queue.failedWrite = true;
        rethrow;
      }
    });
    _queue.tail = next.catchError((Object _) {});
    return next;
  }

  void release() {
    if (owns) _queue.owner = null;
  }
}

class _StoryWriteQueue {
  StoryStoreOwner? owner;
  String? committedValue;
  bool hasCommittedValue = false, failedWrite = false;
  Future<void> tail = Future.value();
}
