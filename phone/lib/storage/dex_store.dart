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
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return IncubationProgress(
        carriedM: (data['carriedM'] as num).toDouble(),
        sessionDistances: (data['sessionDistances'] as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, (value as num).toDouble())),
        round: (data['round'] as Map?)?.cast<String, dynamic>(),
      );
    }
    return IncubationProgress(
        carriedM: p.getDouble(_key('$_kCarry${tier.name}')) ?? 0);
  }

  /// 누적 거리와 해당 세션의 반영 위치를 한 값으로 저장한다.
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    final p = await SharedPreferences.getInstance();
    final saved = await p.setString(
        _key('$_kProgress${tier.name}'),
        jsonEncode({
          'carriedM': progress.carriedM,
          'sessionDistances': progress.sessionDistances,
          if (progress.round != null) 'round': progress.round,
        }));
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
}
