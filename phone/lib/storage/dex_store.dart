import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 도감 + 이어하기 거리. **기기에만 저장**한다. 서버에는 올리지 않는다 (아동 개인정보 설계).
class DexStore {
  static const _kDex = 'dex.entries.v1';
  static const _kCarry = 'hatch.carried.v1.'; // + eggTier

  Future<List<DexEntry>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kDex) ?? const [];
    return raw
        .map((s) => DexEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(DexEntry e) async {
    final p = await SharedPreferences.getInstance();
    final raw = List<String>.from(p.getStringList(_kDex) ?? const []);
    final encoded = jsonEncode(e.toJson());
    if (!raw.contains(encoded)) raw.add(encoded);
    await p.setStringList(_kDex, raw);
  }

  Future<double> carriedDistance(EggTier t) async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble('$_kCarry${t.name}') ?? 0;
  }

  Future<void> setCarriedDistance(EggTier t, double m) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('$_kCarry${t.name}', m);
  }
}
