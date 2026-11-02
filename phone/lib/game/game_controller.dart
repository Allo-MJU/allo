import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../feed/vehicle_feed.dart';
import '../storage/dex_store.dart';

/// 한 세션의 게임 상태 머신. 판정은 allo_core 에 위임하고, 결과를 feed.publishGame 으로 차 화면에 보낸다.
class GameController extends ChangeNotifier {
  GameController({required this.feed, required this.dex, RarityEngine? engine}) : engine = engine ?? const RarityEngine();

  final VehicleFeed feed;
  final DexStore dex;
  final RarityEngine engine;

  SpeciesTable? _table;
  StreamSubscription<VehicleState>? _sub;
  HatchTimer? _timer;

  VehicleState? vehicle;
  GameState game = GameState(ts: 0, eggTier: EggTier.small, stage: Stage.idle, progress: 0);
  Species? hatched;
  final Set<String> seenTags = {};
  int careCount = 0;
  int lookOutCount = 0;
  bool paired = false;
  String? error;

  Future<void> loadSpecies() async {
    _table ??= SpeciesTable.fromJson(jsonDecode(await rootBundle.loadString('../data/species.json')) as Map<String, dynamic>);
  }

  Future<void> pair(String sessionId, {String? pairCode}) async {
    error = null;
    try {
      await feed.pair(sessionId, pairCode: pairCode);
      paired = true;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  /// 알 고르기 → 품기 시작. 이전 주행에서 넘어온 거리는 DexStore 에 있다.
  Future<void> startIncubating(EggTier tier) async {
    await loadSpecies();
    final carried = await dex.carriedDistance(tier);
    _timer = HatchTimer(eggTier: tier, carriedM: carried);
    seenTags.clear();
    careCount = 0;
    lookOutCount = 0;
    hatched = null;
    game = GameState(ts: _now, eggTier: tier, stage: Stage.incubating, progress: 0, hatchAtM: _timer!.hatchAtM);
    await _sub?.cancel();
    _sub = feed.watch().listen(_onVehicle);
    notifyListeners();
    unawaited(feed.publishGame(game));
  }

  void _onVehicle(VehicleState v) {
    vehicle = v;
    seenTags.addAll(v.envTags);
    final t = _timer;
    if (t == null || game.stage != Stage.incubating) {
      notifyListeners();
      return;
    }
    final p = t.update(v);
    game = game.copyWith(ts: _now, progress: p, careCount: careCount, lookOutCount: lookOutCount, hatchAtM: t.hatchAtM, hatchAtSec: t.hatchAtSec);
    if (t.shouldHatch(p)) _hatch(v);
    notifyListeners();
    unawaited(feed.publishGame(game));
  }

  void _hatch(VehicleState v) {
    final r = engine.judge(seenTags: seenTags, harshBrake: v.harshBrake, harshSteer: v.harshSteer, careCount: careCount, capabilities: v.capabilities);
    final s = _table!.pick(r, seenTags);
    hatched = s;
    game = game.copyWith(stage: Stage.hatched, progress: 1, speciesId: s.id, attribute: s.attribute, tier: r.tier);
    unawaited(feed.emitEvent('hatched', payload: {'speciesId': s.id, 'tier': r.tier}));
    final region = seenTags.where((t) => const {'coast', 'mountain', 'city'}.contains(t)).firstOrNull;
    unawaited(dex.add(DexEntry(
      speciesId: s.id,
      obtainedAt: DateTime.now(),
      envTags: seenTags.toList(),
      regionTag: region,
      tier: r.tier,
    )));
    unawaited(dex.setCarriedDistance(game.eggTier, 0));
  }

  void care() {
    if (game.stage != Stage.incubating) return;
    careCount++;
    game = game.copyWith(careCount: careCount);
    notifyListeners();
  }

  void lookOut() {
    lookOutCount++;
    game = game.copyWith(lookOutCount: lookOutCount);
    unawaited(feed.emitEvent('lookOutPrompt'));
    notifyListeners();
  }

  /// 도착(기어 P) 또는 앱 종료. 부화 전이면 거리를 다음 주행으로 넘긴다.
  Future<void> endSession() async {
    final t = _timer;
    if (t != null && game.stage == Stage.incubating) {
      await dex.setCarriedDistance(game.eggTier, t.carryOver(hatched: false));
    }
    await _sub?.cancel();
    _sub = null;
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  @override
  void dispose() {
    _sub?.cancel();
    feed.dispose();
    super.dispose();
  }
}
