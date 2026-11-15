import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 도감 + 이어하기 거리. **기기에만 저장**한다. 서버에는 올리지 않는다 (아동 개인정보 설계).
class DexStore {
  DexStore({this.namespace = '', this.profile = 'default'}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(profile)) {
      throw ArgumentError.value(profile, 'profile', 'Invalid local profile');
    }
  }
  final String namespace;
  final String profile;
  String _key(String value) =>
      '$namespace${profile == 'default' ? '' : 'profile.$profile.'}$value';
  static const _kDex = 'dex.entries.v1';
  static const _kProgress = 'hatch.progress.v2.';
  static const _kCarry = 'hatch.carried.v1.'; // + eggTier

  String _ledgerKey(bool demo) =>
      _key('hatch.trip.v1.${demo ? 'demo' : 'vehicle'}');

  // A second controller (e.g. during a host recreation) must see the first
  // controller's committed grant before deciding which egg to prepare.
  static final _tripWrites = <String, Future<void>>{};
  Future<T> withTripLock<T>(bool demo, Future<T> Function() action) {
    final key = _ledgerKey(demo);
    final result =
        (_tripWrites[key] ?? Future<void>.value()).then((_) => action());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tripWrites[key] = tail;
    tail.whenComplete(() {
      if (identical(_tripWrites[key], tail)) _tripWrites.remove(key);
    });
    return result;
  }

  Future<TripEggLedger> tripEggLedger(bool demo) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ledgerKey(demo));
    return raw == null
        ? TripEggLedger()
        : TripEggLedger.fromJson(jsonDecode(raw));
  }

  Future<void> saveTripEggLedger(bool demo, TripEggLedger ledger) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_ledgerKey(demo), jsonEncode(ledger.toJson()))) {
      throw StateError('Could not save trip egg');
    }
  }

  Future<IncubationProgress> tripProgress(bool demo, EggTier tier) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key('hatch.demo.v1.${tier.name}');
    final raw = prefs.getString(key);
    if (demo && raw != null) {
      return IncubationProgress.fromJson(jsonDecode(raw));
    }
    final legacy = await incubationProgress(tier);
    final fakeCheckpoint = legacy.round != null &&
        legacy.round!['sessionId'] == null &&
        legacy.sessionDistances.isEmpty;
    if (!fakeCheckpoint) return demo ? const IncubationProgress() : legacy;
    // Preserve the identifiable old demo copy before a real trip reuses its tier slot.
    if (!await prefs.setString(key, raw ?? jsonEncode(legacy.toJson()))) {
      throw StateError('Could not migrate demo egg');
    }
    return demo ? legacy : const IncubationProgress();
  }

  Future<void> saveTripProgress(
      bool demo, EggTier tier, IncubationProgress value) async {
    if (!demo) return saveIncubationProgress(tier, value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key('hatch.demo.v1.${tier.name}'), jsonEncode(value.toJson()))) {
      throw StateError('Could not save demo egg');
    }
  }

  Future<List<DexEntry>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_key(_kDex)) ?? const [];
    return raw
        .map((s) => DexEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Include sourceEggId ownership identity through the existing validated model.
  /// Delegating to all() preserves namespace isolation and in-memory overrides.
  Future<List<Map<String, dynamic>>> allRecords() async =>
      (await all()).map((entry) => entry.toJson()).toList();

  Future<void> add(DexEntry e) async {
    final p = await SharedPreferences.getInstance();
    final raw = List<String>.from(p.getStringList(_key(_kDex)) ?? const []);
    final encoded = jsonEncode(e.toJson());
    var sameEgg = false;
    if (e.sourceEggId != null) {
      for (final value in raw) {
        final previous =
            DexEntry.fromJson(jsonDecode(value) as Map<String, dynamic>);
        if (previous.sourceEggId == e.sourceEggId) {
          if (jsonEncode(previous.toJson()) != encoded) {
            throw StateError('Conflicting result for source egg');
          }
          sameEgg = true;
        }
      }
    }
    if (!sameEgg && !raw.contains(encoded)) raw.add(encoded);
    // Retry the write even when the cache already contains a failed prior write.
    final saved = await p.setStringList(_key(_kDex), raw);
    if (!saved) throw StateError('Could not save dex entry');
  }

  Future<IncubationProgress> incubationProgress(EggTier tier) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key('$_kProgress${tier.name}'));
    if (raw != null) {
      return IncubationProgress.fromJson(jsonDecode(raw));
    }
    return IncubationProgress(
        carriedM: p.getDouble(_key('$_kCarry${tier.name}')) ?? 0);
  }

  /// 누적 거리와 해당 세션의 반영 위치를 한 값으로 저장한다.
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    final p = await SharedPreferences.getInstance();
    final saved = await p.setString(
        _key('$_kProgress${tier.name}'), jsonEncode(progress.toJson()));
    if (!saved) throw StateError('Could not save incubation progress');
  }

  Future<double> carriedDistance(EggTier tier) async =>
      (await incubationProgress(tier)).carriedM;

  Future<void> setCarriedDistance(EggTier tier, double m) =>
      saveIncubationProgress(tier, IncubationProgress(carriedM: m));
}

/// 로컬 이어하기 기록. 각 세션의 반영 위치는 부화 후에도 보존한다.
class IncubationProgress {
  const IncubationProgress(
      {this.carriedM = 0, this.sessionDistances = const {}, this.round});
  final Map<String, dynamic>? round;
  final double carriedM;
  final Map<String, double> sessionDistances;
  factory IncubationProgress.fromJson(Map<String, dynamic> data) =>
      IncubationProgress(
        carriedM: (data['carriedM'] as num).toDouble(),
        sessionDistances: (data['sessionDistances'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        round: (data['round'] as Map?)?.cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
        'carriedM': carriedM,
        'sessionDistances': sessionDistances,
        if (round != null) 'round': round,
      };
}

/// A claim and its initial progress are one write. The changing checkpoint
/// can lag it or belong to an earlier egg in the same tier.
class TripEggLedger {
  TripEggLedger({Map<String, String>? claims}) : claims = claims ?? {};
  final Map<String, String> claims;
  String? demoSessionId;
  String? eggId;
  EggTier tier = EggTier.small;
  bool useAffinity = true;
  IncubationProgress initial = const IncubationProgress();

  factory TripEggLedger.fromJson(Map<String, dynamic> data) =>
      TripEggLedger(claims: (data['claims'] as Map).cast<String, String>())
        ..demoSessionId = data['demoSessionId'] as String?
        ..eggId = data['eggId'] as String?
        ..tier = EggTier.values.byName(data['tier'] as String)
        ..useAffinity = data['useAffinity'] as bool
        ..initial = IncubationProgress.fromJson(data['initial']);

  Map<String, dynamic> toJson() => {
        'claims': claims,
        'eggId': eggId,
        'tier': tier.name,
        'useAffinity': useAffinity,
        'initial': initial.toJson(),
        'demoSessionId': demoSessionId,
      };
}
