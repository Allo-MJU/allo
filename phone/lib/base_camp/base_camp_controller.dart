import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/dex_store.dart';
import 'base_camp_store.dart';

/// Local camp commands are copied, serialized and saved before publication.
/// Feed snapshots must be forwarded by the caller's existing subscription.
class BaseCampController extends ChangeNotifier {
  BaseCampController({
    required BaseCampStore store,
    DexStore? dex,
    int Function()? nowMs,
    String Function()? taskIdFactory,
  })  : _store = store,
        _dex = dex ?? DexStore(),
        _clock = nowMs ?? _epochNow,
        _taskIdFactory = taskIdFactory,
        _camp = BaseCamp.empty(nowMs: (nowMs ?? _epochNow)());

  static int _epochNow() => DateTime.now().millisecondsSinceEpoch;
  final BaseCampStore _store;
  final DexStore _dex;
  final int Function() _clock;
  final String Function()? _taskIdFactory;
  final Random _random = Random.secure();
  BaseCamp _camp;
  _CreatureRegistry _registry = _CreatureRegistry();
  Future<void> _tail = Future<void>.value();
  Timer? _timer;
  int _pending = 0;
  int _taskNumber = 0;
  bool _ready = false;
  bool _disposed = false;
  String? _error;
  final Map<String, int> _sessionGeneration = {};
  final Map<String, int> _acceptedGeneration = {};

  bool get ready => _ready;
  bool get busy => _pending > 0;
  String? get error => _error;

  /// The engine is mutable internally; callers receive a detached snapshot.
  BaseCamp get state => BaseCamp.fromJson(_camp.toJson());

  Future<bool> load() => _enqueue(() async {
        Map<String, dynamic>? saved;
        try {
          saved = await _store.load();
        } catch (_) {
          throw const _ControllerFailure('load_failed');
        }
        late BaseCamp next;
        late _CreatureRegistry registry;
        try {
          if (saved == null) {
            next = BaseCamp.empty(nowMs: _clock());
            registry = _CreatureRegistry();
          } else {
            if (saved['version'] != 1 ||
                saved['core'] is! Map<String, dynamic> ||
                saved['registry'] is! Map<String, dynamic>) {
              throw const FormatException('Invalid camp envelope');
            }
            registry = _CreatureRegistry.fromJson(
                saved['registry'] as Map<String, dynamic>);
            next = BaseCamp.fromJson(saved['core'] as Map<String, dynamic>);
            if (next.creatures.keys
                .any((id) => !registry.ids.containsValue(id))) {
              throw const FormatException('Missing creature identity');
            }
          }
        } catch (_) {
          throw const _ControllerFailure('invalid_data');
        }
        final entries = await _readOwnership();
        final at = max(next.nowMs, _clock());
        next.syncCreatures(registry.resolve(entries), atMs: at);
        await _save(next, registry);
        if (!_disposed) {
          _camp = next;
          _registry = registry;
          _ready = true;
          // Closed-app distance is unobserved, even for a persisted session.
          _sessionGeneration.clear();
          _acceptedGeneration.clear();
          _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (!_disposed && !busy && _camp.jobs.isNotEmpty) {
              unawaited(tick());
            }
          });
        }
        return true;
      });

  Future<bool> refreshOwnership() => _mutate((camp, registry, at) async {
        final entries = await _readOwnership();
        camp.syncCreatures(registry.resolve(entries), atMs: at);
        return true;
      });

  Future<bool> tick() => _mutate((camp, registry, at) => true);

  Future<bool> assign(CampRole role, String? creatureId) =>
      _mutate((camp, registry, at) {
        camp.assign(role, creatureId, atMs: at);
        return true;
      });

  Future<bool> startBuild(CampFacility facility) =>
      _mutate((camp, registry, at) {
        camp.startBuild(taskId: _newTaskId(), facility: facility, atMs: at);
        return true;
      });

  Future<bool> startCooking(String recipeId) => _mutate((camp, registry, at) {
        camp.startCooking(taskId: _newTaskId(), recipeId: recipeId, atMs: at);
        return true;
      });

  Future<bool> startTraining(String actionId, String targetId) =>
      _mutate((camp, registry, at) {
        camp.startTraining(
            taskId: _newTaskId(),
            actionId: actionId,
            targetId: targetId,
            atMs: at);
        return true;
      });

  Future<bool> cancel(CampRole role) => _mutate((camp, registry, at) {
        camp.cancel(role, atMs: at);
        return true;
      });

  Future<bool> feedFood(String recipeId, String creatureId) =>
      _mutate((camp, registry, at) {
        camp.feedFood(recipeId: recipeId, creatureId: creatureId, atMs: at);
        return true;
      });

  /// Call whenever the existing vehicle stream attaches or resumes.
  /// A stale sample cannot consume the requirement for a fresh baseline.
  void beginDrivingSession(String sessionId) {
    if (_disposed) return;
    if (sessionId.isEmpty) throw ArgumentError.value(sessionId, 'sessionId');
    _sessionGeneration[sessionId] = (_sessionGeneration[sessionId] ?? 0) + 1;
  }

  Future<bool> recordVehicle(
      {required String sessionId, required VehicleState vehicle}) {
    final generation = _sessionGeneration[sessionId] ?? 0;
    var acceptedSample = false;
    return _mutate((camp, registry, at) {
      final accepted = camp.recordDrive(
          sessionId: sessionId,
          ts: vehicle.ts,
          distanceM: vehicle.distanceM,
          atMs: at,
          baselineOnly: _acceptedGeneration[sessionId] != generation);
      acceptedSample = accepted;
      return accepted;
    }, onCommit: () {
      if (acceptedSample) {
        // A queued old sample may settle its generation, never a newer resume.
        _acceptedGeneration[sessionId] = generation;
      }
    });
  }

  Future<bool> recordLookOut({required String eventId}) => _mutate(
      (camp, registry, at) => camp.recordLookOut(eventId: eventId, atMs: at));

  /// Resolve an existing camp ID against freshly read ownership, without saving IDs.
  Future<DexEntry?> ownedEntryForCreature(String creatureId) async {
    final expected = _camp.creatures[creatureId];
    if (_disposed || !_ready || expected == null) return null;
    final registry = _CreatureRegistry.fromJson(_registry.toJson());
    try {
      final entries = await _readOwnership();
      DexEntry? owned;
      registry.resolve(entries, onResolved: (id, entry) {
        if (id == creatureId) owned = entry;
      });
      if (_disposed ||
          _camp.creatures[creatureId]?.speciesId != expected.speciesId ||
          owned?.speciesId != expected.speciesId) {
        return null;
      }
      return owned;
    } catch (_) {
      return null;
    }
  }

  bool canUseAction(String id, String action) =>
      !_disposed && _ready && _camp.canUseAction(id, action);

  String? performAction(String id, String action) =>
      canUseAction(id, action) ? action : null;

  String _newTaskId() =>
      _taskIdFactory?.call() ??
      'camp-${_epochNow()}-${_random.nextInt(0x7fffffff)}-${_taskNumber++}';

  Future<List<_CampOwnership>> _readOwnership() async {
    try {
      await (await SharedPreferences.getInstance()).reload();
      return (await _dex.allRecords()).map(_CampOwnership.fromRecord).toList();
    } catch (_) {
      throw const _ControllerFailure('ownership_read_failed');
    }
  }

  Future<void> _save(BaseCamp camp, _CreatureRegistry registry) async {
    try {
      await _store.save(
          {'version': 1, 'registry': registry.toJson(), 'core': camp.toJson()});
    } catch (_) {
      throw const _ControllerFailure('save_failed');
    }
  }

  Future<bool> _mutate(
          FutureOr<bool> Function(
                  BaseCamp camp, _CreatureRegistry registry, int at)
              command,
          {void Function()? onCommit}) =>
      _enqueue(() async {
        if (!_ready) throw const _ControllerFailure('not_ready');
        final next = BaseCamp.fromJson(_camp.toJson());
        final registry = _CreatureRegistry.fromJson(_registry.toJson());
        final at = max(next.nowMs, _clock());
        next.advanceTo(at);
        final result = await command(next, registry, at);
        await _save(next, registry);
        if (!_disposed) {
          _camp = next;
          _registry = registry;
          onCommit?.call();
        }
        return result;
      });

  Future<bool> _enqueue(Future<bool> Function() operation) {
    if (_disposed) return Future<bool>.value(false);
    _pending++;
    final result = _tail.then((_) async {
      try {
        if (_disposed) return false;
        _error = null;
        return await operation();
      } on _ControllerFailure catch (failure) {
        if (!_disposed) _error = failure.code;
        return false;
      } on CampException catch (failure) {
        if (!_disposed) _error = failure.code;
        return false;
      } catch (_) {
        if (!_disposed) _error = 'command_failed';
        return false;
      } finally {
        _pending--;
        _notify();
      }
    });
    _tail = result.then<void>((_) {});
    _notify();
    return result;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class _ControllerFailure implements Exception {
  const _ControllerFailure(this.code);
  final String code;
}

class _CampOwnership {
  _CampOwnership.fromRecord(Map<String, dynamic> record)
      : entry = DexEntry.fromJson(record),
        sourceEggId = record['sourceEggId'];

  final DexEntry entry;
  final Object? sourceEggId;
}

class _CreatureRegistry {
  _CreatureRegistry();
  int nextCreatureNumber = 1;
  final Map<String, String> ids = {};

  factory _CreatureRegistry.fromJson(Map<String, dynamic> json) {
    final next = json['nextCreatureNumber'];
    final raw = json['ids'];
    if (next is! int || next < 1 || raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid creature registry');
    }
    final registry = _CreatureRegistry()..nextCreatureNumber = next;
    final used = <String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      final number = value is String && value.startsWith('creature-')
          ? int.tryParse(value.substring(9))
          : null;
      if (entry.key.isEmpty ||
          value is! String ||
          number == null ||
          number < 1 ||
          number >= next ||
          !used.add(value)) {
        throw const FormatException('Invalid creature identity');
      }
      registry.ids[entry.key] = value;
    }
    return registry;
  }

  Map<String, dynamic> toJson() => {
        'nextCreatureNumber': nextCreatureNumber,
        'ids': Map<String, String>.of(ids),
      };

  List<CampCreature> resolve(List<_CampOwnership> entries,
      {void Function(String id, DexEntry entry)? onResolved}) {
    final occurrences = <String, int>{};
    final current = <String>{};
    final creatures = <CampCreature>[];
    for (final owned in entries) {
      final entry = owned.entry;
      final source = owned.sourceEggId;
      late String key;
      if (source is String &&
          RegExp(r'^[A-Za-z0-9_.:-]{1,200}$').hasMatch(source)) {
        key = 'source:$source';
      } else {
        final tags = List<String>.of(entry.envTags)..sort();
        final canonical = jsonEncode({
          'envTags': tags,
          'obtainedAt': entry.obtainedAt.toUtc().toIso8601String(),
          'regionTag': entry.regionTag,
          'speciesId': entry.speciesId,
          'tier': entry.tier,
        });
        final occurrence =
            occurrences.update(canonical, (n) => n + 1, ifAbsent: () => 0);
        key = 'legacy:$canonical:$occurrence';
      }
      // An authoritative source egg identifies one ownership record.
      if (!current.add(key)) continue;
      final id = ids.putIfAbsent(key, () => 'creature-${nextCreatureNumber++}');
      creatures.add(CampCreature(id: id, speciesId: entry.speciesId));
      onResolved?.call(id, entry);
    }
    return creatures;
  }
}
