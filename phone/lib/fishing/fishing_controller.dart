import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:allo_core/allo_core.dart';

import 'fishing_store.dart';

/// Phone-only owner of companion selection and fishing. All operations are queued;
/// no received wall-clock timestamp contributes to progress.
class FishingController {
  FishingController({
    FishingStore? store,
    required this.onChanged,
    int Function()? clockMs,
    String Function()? newId,
  })  : store = store ?? FishingStore(),
        _clock = clockMs,
        _newId = newId ?? _randomId {
    _watch.start();
  }

  static const targetMs = 60000;
  static const _revisionWindow = 1000000;
  final FishingStore store;
  final void Function() onChanged;
  final int Function()? _clock;
  final String Function() _newId;
  final Stopwatch _watch = Stopwatch();
  Timer? _watchdog;
  int get _now => _clock?.call() ?? _watch.elapsedMilliseconds;
  Future<void> _tail = Future.value();
  Future<void> get settled => _tail;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _pending;
  String? _session;
  String _lease = '';
  bool _active = true;
  bool _disposed = false;
  bool _saving = false;
  int _inputGeneration = 0;
  int _accrualFloor = 0;
  int _revision = 0;
  int _revisionLimit = 0;
  int? _presenceAt;
  int? _sequence;
  String? _epoch;
  bool _presenceAllowed = false;
  int _lastSavedElapsed = 0;
  String? _error;
  String? get error => _error;
  bool get hasPendingWrite => _pending != null;
  bool get initialized => _profile != null && _session != null;
  String? get selectedSpeciesId => _entry?['speciesId'] as String?;
  String? get selectedOwnedCreatureId =>
      _profile?['selectedOwnedCreatureId'] as String?;
  int get totalRecords => (_entry?['totalRecords'] as int?) ?? 0;

  /// Read committed per-acquisition state; same-species records remain distinct.
  bool isSelected(DexEntry entry) =>
      _profile?['selected'] == jsonEncode(entry.toJson());
  String? get companionLocation => _profile?['location'] as String?;
  int recordsFor(DexEntry entry) {
    final records = _profile?['entries'] as Map?;
    final record = records?[jsonEncode(entry.toJson())] as Map?;
    return (record?['totalRecords'] as int?) ?? 0;
  }

  Map<String, dynamic>? get _entry {
    final p = _profile;
    if (p == null || p['selected'] == null) return null;
    return (p['entries'] as Map)[p['selected']] as Map<String, dynamic>?;
  }

  bool get _live =>
      _active &&
      _presenceAllowed &&
      _presenceAt != null &&
      _now >= _presenceAt! &&
      _now - _presenceAt! <= 3000;

  static String _randomId() {
    final r = Random.secure();
    return List.generate(
      20,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Map<String, dynamic> _clone(Map<String, dynamic> value) =>
      (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();
  Future<void> _queue(Future<void> Function() operation) {
    final work = _tail.then((_) async {
      if (!_disposed) await operation();
    });
    // A failed operation must not poison future operations.
    _tail = work.catchError((Object _) {});
    return work;
  }

  void _notify() {
    if (!_disposed) onChanged();
  }

  void _resetLease() {
    _lease = _newId();
    _presenceAt = null;
    _sequence = null;
    _epoch = null;
    _presenceAllowed = false;
  }

  /// Call once per whole-game publication. The reserved durable range prevents
  /// revision reuse after a process restart, even when its wall clock moves back.
  Map<String, dynamic> get snapshotFields {
    if (!initialized) return const {};
    if (_revision >= _revisionLimit) {
      throw StateError(
        'Fishing revision reservation exhausted; reconnect required',
      );
    }
    final p = _profile!;
    final e = _entry;
    return {
      'contractVersion': 2,
      'gameRevision': ++_revision,
      'companion': e == null
          ? null
          : {
              'displayId': p['displayId'],
              'displayRevision': p['displayRevision'],
              'speciesId': e['speciesId'],
              'location': p['location'],
            },
      'transferResult': p['transferResult'],
      'fishing': e == null || p['location'] != 'car'
          ? null
          : {
              'version': 1,
              'leaseId': _lease,
              'displayId': p['displayId'],
              'displayRevision': p['displayRevision'],
              'activityId': e['activityId'],
              'cycle': e['cycle'],
              'state': _pending != null
                  ? 'saveFailed'
                  : _saving && e['activityId'] != ''
                      ? 'saving'
                      : e['state'],
              'elapsedMs': e['elapsedMs'],
              'targetMs': targetMs,
              'totalRecords': e['totalRecords'],
              'rewardName':
                  _pending == null && !_saving && e['state'] == 'reward'
                      ? e['rewardName']
                      : null,
              'requestId': p['requestId'],
            },
    };
  }

  Future<void> attach(String sessionId) => _queue(() async {
        if (sessionId.isEmpty) throw ArgumentError('Empty session');
        // Do not silently abandon unresolved writes when pairing another session.
        if (_pending != null) {
          _error = '저장을 먼저 다시 확인해 주세요.';
          _notify();
          return;
        }
        if (_profile != null) await _pause('paused');
        if (_pending != null) return;
        try {
          final saved = await store.read();
          final p = saved == null ? _empty() : _validate(saved);
          final nextBase = max(
            p['revisionHigh'] as int,
            DateTime.now().millisecondsSinceEpoch * 1000,
          );
          p['revisionHigh'] = nextBase + _revisionWindow;
          if (p['session'] != sessionId) {
            p['transferReceipts'] = <String, dynamic>{};
            p['requests'] = <String, dynamic>{};
            p['transferResult'] = null;
          }
          // Reissue display generation on every attachment; only durable
          // receipts may replay across a same-session process restart.
          p['displayId'] = _newId();
          p['displayRevision'] = (p['displayRevision'] as int) + 1;
          p['session'] = sessionId;
          p['requestId'] = null;
          for (final e in (p['entries'] as Map).values) {
            if (e['state'] == 'running' || e['state'] == 'reward') {
              e['state'] = 'paused';
            }
          }
          await store.write(p);
          if (_disposed) return;
          _profile = p;
          _session = sessionId;
          _revision = nextBase;
          _revisionLimit = p['revisionHigh'] as int;
          _error = null;
          _lastSavedElapsed = (_entry?['elapsedMs'] as int?) ?? 0;
          _resetLease();
          _notify();
        } catch (_) {
          _profile = null;
          _session = null;
          _error = '친구와 낚시 기록을 읽거나 저장하지 못했어요. 다시 연결해 주세요.';
          _notify();
        }
      });

  Map<String, dynamic> _empty() => {
        'version': 1,
        'revisionHigh': 0,
        'session': null,
        'selected': null,
        'selectedOwnedCreatureId': null,
        'displayId': _newId(),
        'displayRevision': 0,
        'location': 'car',
        'entries': <String, dynamic>{},
        'transferReceipts': <String, dynamic>{},
        'requests': <String, dynamic>{},
        'transferResult': null,
        'requestId': null,
      };
  Map<String, dynamic> _validate(Map<String, dynamic> source) {
    final p = _clone(source);
    if (p['version'] != 1 ||
        p['revisionHigh'] is! int ||
        p['revisionHigh'] < 0 ||
        p['displayRevision'] is! int ||
        p['displayRevision'] < 0 ||
        p['displayId'] is! String ||
        !['car', 'phone'].contains(p['location']) ||
        p['entries'] is! Map ||
        p['requests'] is! Map ||
        p['transferReceipts'] is! Map ||
        (p['selectedOwnedCreatureId'] != null &&
            (p['selected'] == null ||
                p['selectedOwnedCreatureId'] is! String ||
                !RegExp(r'^[A-Za-z0-9_-]{1,128}$')
                    .hasMatch(p['selectedOwnedCreatureId'] as String))) ||
        (p['selected'] != null &&
            !(p['entries'] as Map).containsKey(p['selected']))) {
      throw const FormatException('Invalid profile');
    }
    for (final e in (p['entries'] as Map).values) {
      if (e is! Map ||
          e['speciesId'] is! String ||
          e['activityId'] is! String ||
          e['cycle'] is! int ||
          e['cycle'] < 0 ||
          e['elapsedMs'] is! int ||
          e['elapsedMs'] < 0 ||
          e['elapsedMs'] > targetMs ||
          e['totalRecords'] is! int ||
          e['totalRecords'] < 0 ||
          !['ready', 'running', 'paused', 'reward'].contains(e['state'])) {
        throw const FormatException('Invalid fishing entry');
      }
    }
    return p;
  }

  Future<void> select(DexEntry entry, {String? ownedCreatureId}) =>
      _queue(() async {
        if (ownedCreatureId != null &&
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(ownedCreatureId)) {
          throw ArgumentError.value(ownedCreatureId, 'ownedCreatureId');
        }
        if (!initialized || _pending != null) return;
        final key = jsonEncode(entry.toJson());
        if (_profile!['selected'] == key &&
            _profile!['location'] == 'car' &&
            selectedOwnedCreatureId == ownedCreatureId) {
          return;
        }
        final p = _clone(_profile!);
        _pauseEntry(p);
        final entries = p['entries'] as Map;
        entries.putIfAbsent(
          key,
          () => {
            'speciesId': entry.speciesId,
            'activityId': '',
            'cycle': 0,
            'elapsedMs': 0,
            'totalRecords': 0,
            'state': 'ready',
            'rewardName': null,
          },
        );
        p['selected'] = key;
        p['selectedOwnedCreatureId'] = ownedCreatureId;
        p['location'] = 'car';
        p['displayId'] = _newId();
        p['displayRevision'] = (p['displayRevision'] as int) + 1;
        p['requestId'] = null;
        p['transferResult'] = null;
        if (await _commit(p)) {
          _resetLease();
          _lastSavedElapsed = _entry!['elapsedMs'] as int;
          _notify();
        }
      });

  Future<bool> _commit(Map<String, dynamic> p) async {
    _saving = true;
    _inputGeneration++;
    _notify();
    try {
      await store.write(p);
      if (_disposed) return false;
      _saving = false;
      _inputGeneration++;
      _accrualFloor = _now;
      _profile = p;
      _pending = null;
      _error = null;
      _lastSavedElapsed = (_entry?['elapsedMs'] as int?) ?? 0;
      _notify();
      return true;
    } catch (_) {
      _saving = false;
      _inputGeneration++;
      _accrualFloor = _now;
      _pending = _clone(p);
      _error = '낚시 기록을 저장하지 못했어요. 다시 확인해 주세요.';
      _resetLease();
      _notify();
      return false;
    }
  }

  void _pauseEntry(Map<String, dynamic> p) {
    final e = (p['entries'] as Map)[p['selected']];
    if (e != null && e['state'] != 'ready') e['state'] = 'paused';
  }

  Future<void> _pause(String state) async {
    if (!initialized || _pending != null) return;
    final e = _entry;
    if (e == null || e['state'] == 'ready' || e['state'] == 'paused') return;
    final p = _clone(_profile!);
    _pauseEntry(p);
    await _commit(p);
  }

  void observePresence(Map<String, dynamic>? presence) {
    if (!_active) return;
    if (_saving) {
      // Negative eligibility still fences an in-flight write; positive samples
      // received during storage never become later progress.
      if (presence == null ||
          presence['leaseId'] == _lease &&
              (presence['active'] != true ||
                  presence['parkedAllowed'] != true)) {
        _resetLease();
        _inputGeneration++;
        unawaited(_queue(() async {
          await _pause('paused');
          _notify();
        }));
      }
      return;
    }
    final at = _now;
    final generation = _inputGeneration;
    unawaited(
      _queue(() async {
        if (generation != _inputGeneration ||
            !initialized ||
            !_active ||
            _entry == null ||
            _profile!['location'] != 'car') {
          return;
        }
        if (presence == null) {
          await _invalidatePresence();
          return;
        }
        if (presence['leaseId'] != _lease) return;
        final seq = presence['sequence'];
        final epoch = presence['epoch'];
        if (presence['version'] is! int ||
            presence['version'] != 1 ||
            seq is! int ||
            seq < 0 ||
            epoch is! String ||
            epoch.isEmpty ||
            presence['active'] is! bool ||
            presence['parkedAllowed'] is! bool) {
          await _invalidatePresence();
          return;
        }
        if (!presence['active'] || !presence['parkedAllowed']) {
          await _invalidatePresence();
          return;
        }
        if (_epoch != null && _epoch != epoch) {
          await _invalidatePresence();
          return;
        }
        if (_sequence != null && seq <= _sequence!) return;
        final previous = _presenceAt;
        final continuous = previous != null &&
            seq == _sequence! + 1 &&
            at >= previous &&
            at - previous <= 2000;
        if (previous != null && !continuous) {
          await _invalidatePresence();
          return;
        }
        _presenceAt = at;
        _sequence = seq;
        _epoch = epoch;
        _presenceAllowed = true;
        _watchdog ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
          unawaited(tick());
        });
        if (_pending != null ||
            !continuous ||
            _entry == null ||
            _profile!['location'] != 'car') {
          return;
        }
        final e = _entry!;
        if (e['state'] == 'reward') {
          final p = _clone(_profile!);
          final n = (p['entries'] as Map)[p['selected']];
          n['state'] = 'running';
          n['elapsedMs'] = 0;
          n['rewardName'] = null;
          await _commit(p);
          return;
        }
        if (e['state'] != 'running') return;
        e['elapsedMs'] = min(
            targetMs,
            (e['elapsedMs'] as int) +
                max(0, at - max(previous, _accrualFloor)));
        if (e['elapsedMs'] == targetMs) {
          final p = _clone(_profile!);
          final n = (p['entries'] as Map)[p['selected']];
          n['totalRecords'] = (n['totalRecords'] as int) + 1;
          n['rewardName'] = '물고기 관찰 ${(n['cycle'] as int) % 3 + 1}';
          n['cycle'] = (n['cycle'] as int) + 1;
          n['state'] = 'reward';
          await _commit(p);
        } else if ((e['elapsedMs'] as int) - _lastSavedElapsed >= 5000) {
          await _commit(_clone(_profile!));
        } else {
          _notify();
        }
      }),
    );
  }

  Future<void> _invalidatePresence() async {
    if (_presenceAt == null &&
        !_presenceAllowed &&
        _entry?['state'] != 'running' &&
        _entry?['state'] != 'reward') {
      return;
    }
    _resetLease();
    await _pause('paused');
    _notify();
  }

  Future<void> tick() => _queue(() async {
        if (_presenceAt != null &&
            (_now < _presenceAt! || _now - _presenceAt! > 3000)) {
          await _invalidatePresence();
        }
      });

  Future<void> handleEvent(Map<String, Object?> event) => _queue(() async {
        if (!initialized || event['by'] != 'car') return;
        final payload = event['payload'];
        if (payload is! Map) return;
        final pld = payload.cast<String, dynamic>();
        if (event['type'] == 'companionTransferRequested') {
          await _transfer(pld);
          return;
        }
        if (event['type'] != 'fishingRequested') return;
        final request = pld['requestId'];
        if (request is! String ||
            request.isEmpty ||
            request.length > 128 ||
            pld['leaseId'] != _lease ||
            _entry == null ||
            pld['displayRevision'] is! int ||
            pld['cycle'] is! int ||
            pld['displayId'] != _profile!['displayId'] ||
            pld['displayRevision'] != _profile!['displayRevision']) {
          return;
        }
        if (!_live) {
          if (_pending == null) await _ackRejected(request);
          return;
        }
        if (_pending != null) {
          if (pld['action'] == 'retry') await _retry(request);
          return;
        }
        if ((_profile!['requests'] as Map).containsKey(request)) {
          _profile!['requestId'] = request;
          _notify();
          return;
        }
        if (pld['activityId'] != _entry!['activityId'] ||
            pld['cycle'] != _entry!['cycle']) {
          await _ackRejected(request);
          return;
        }
        final action = pld['action'];
        final state = _entry!['state'];
        final p = _clone(_profile!);
        final e = (p['entries'] as Map)[p['selected']];
        if (action == 'start' && state == 'ready') {
          e['activityId'] = _newId();
          e['state'] = 'running';
        } else if (action == 'resume' && state == 'paused') {
          e['state'] = 'running';
          if (e['elapsedMs'] == targetMs) e['elapsedMs'] = 0;
        } else if (action == 'pause' &&
            (state == 'running' || state == 'reward')) {
          e['state'] = 'paused';
        } else if (action != 'retry') {
          await _ackRejected(request);
          return;
        }
        p['requestId'] = request;
        (p['requests'] as Map)[request] = true;
        if (await _commit(p)) {
          if (action == 'start' || action == 'resume') _presenceAt = null;
        }
      });

  Future<void> _ackRejected(String request) async {
    final p = _clone(_profile!);
    p['requestId'] = request;
    (p['requests'] as Map)[request] = true;
    await _commit(p);
  }

  Future<void> _transfer(Map<String, dynamic> payload) async {
    if (_pending != null) return;
    final request = payload['requestId'];
    if (request is! String || request.isEmpty || request.length > 128) return;
    final previous = (_profile!['transferReceipts'] as Map)[request];
    if (previous != null) {
      _profile!['transferResult'] = previous;
      _notify();
      return;
    }
    if (_entry == null || !_live) return;
    final display = payload['displayId'];
    final revision = payload['displayRevision'] ?? payload['requestRevision'];
    if (display is! String || revision is! int) return;
    final status = display != _profile!['displayId'] ||
            revision != _profile!['displayRevision']
        ? 'staleSelection'
        : _profile!['location'] == 'phone'
            ? 'alreadyOnPhone'
            : 'accepted';
    final p = _clone(_profile!);
    if (status == 'accepted') {
      _pauseEntry(p);
      p['location'] = 'phone';
    }
    final result = {
      'requestId': request,
      'displayId': display,
      'requestRevision': revision,
      'status': status,
      'resultLocation': status == 'staleSelection' ? null : 'phone',
    };
    p['transferResult'] = result;
    (p['transferReceipts'] as Map)[request] = result;
    if (await _commit(p)) {
      _resetLease();
      _notify();
    }
  }

  Future<void> returnToCar() => _queue(() async {
        if (!initialized ||
            _pending != null ||
            _entry == null ||
            _profile!['location'] == 'car') {
          return;
        }
        final p = _clone(_profile!);
        p['location'] = 'car';
        p['transferResult'] = null;
        p['displayRevision'] = (p['displayRevision'] as int) + 1;
        _pauseEntry(p);
        if (await _commit(p)) {
          _resetLease();
          _notify();
        }
      });
  Future<void> retrySave() => _queue(() => _retry());
  Future<void> _retry([String? request]) async {
    final p = _pending;
    if (p == null) return;
    // Never restart accrual after a storage failure without a new live lease.
    final candidate = _clone(p);
    if (request != null) {
      candidate['requestId'] = request;
      (candidate['requests'] as Map)[request] = true;
    }
    _pauseEntry(candidate);
    if (await _commit(candidate)) {
      _resetLease();
      _notify();
    }
  }

  Future<void> setActive(bool active) {
    if (_active == active) return settled;
    // Fence queued signals immediately, before any in-flight disk write settles.
    _active = active;
    _inputGeneration++;
    _resetLease();
    return _queue(() async {
      if (!active) await _pause('paused');
      _notify();
    });
  }

  Future<void> detach() => _queue(() async {
        _active = false;
        _watchdog?.cancel();
        _watchdog = null;
        _resetLease();
        await _pause('paused');
        if (_pending != null) return;
        _session = null;
        _notify();
      });
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
  }
}
