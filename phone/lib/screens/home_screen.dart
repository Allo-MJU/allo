import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../explore/explore_screen.dart';
import '../game/game_controller.dart';
import '../ui_mode.dart';
import '../widgets/species_art.dart';

/// 광장. 주행 중 폰의 집 화면 — 여기서 차 안(Unity 탐험)·도감·주행 종료로 오간다.
/// 차 안 모습은 Unity 에서만 보여 주고, 이 화면은 지금 알·동행 상태와 갈 곳만 둔다.
///
/// - 알을 받으면 바로 차 안으로 들어간다 (알마다 한 번). 차 안에서 ← 로 나오면 여기
/// - 차 안에서 깨어나는 걸 봤으면 동행 카드로 바뀌고, 못 봤으면(Unity 없음·광장에서 부화) 부화 화면으로
/// - 알 탭 = 감싸기, 동행 탭 = 놀아주기 (차 안에서 하는 것과 같은 돌봄)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.enterExplore});
  final GameController controller;

  /// 알을 받으면 바로 차 안으로 들어갈지. null 이면 [autoEnterExplore] 를 따른다
  final bool? enterExplore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 이 알로 이미 차 안에 자동으로 들어갔는지 (광장으로 돌아올 때마다 다시 들어가지 않게)
String? _autoEnteredEggId;

/// 이 알의 깨어나는 장면을 이미 보여 줬는지 (차 안에서 봤거나 부화 화면으로 보냈거나). 광장은 알마다 한 번만 부화 화면으로 보낸다
String? _hatchShownEggId;

class _HomeScreenState extends State<HomeScreen> {
  bool _routing = false;
  bool _sawExplore = false;

  bool get _enterExplore =>
      !widget.controller.usesAffinity &&
      (widget.enterExplore ?? autoEnterExplore);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSignal);
    exploreScreenOpen.addListener(_onExploreOpen);
    _onSignal();
    final c = widget.controller;
    if (_enterExplore &&
        c.game.stage == Stage.incubating &&
        !c.sessionEnded &&
        _autoEnteredEggId != (c.eggId ?? '')) {
      _autoEnteredEggId = c.eggId ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_routing &&
            !c.sessionEnded &&
            c.game.stage == Stage.incubating) {
          _openExplore();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSignal);
    exploreScreenOpen.removeListener(_onExploreOpen);
    super.dispose();
  }

  void _openExplore() => context.push('/explore');

  /// 광장이 보이는 동안 부화하면 부화 화면으로. 차 안이 떠 있으면 그 안에서 깨어나므로 넘기지 않는다
  void _onSignal() {
    final c = widget.controller;
    if (c.sessionEnded || exploreScreenOpen.value) return;
    if (c.game.stage == Stage.hatched &&
        !_routing &&
        _hatchShownEggId != (c.eggId ?? '')) {
      _routing = true;
      _hatchShownEggId = c.eggId ?? '';
      final eggId = c.eggId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !c.sessionEnded &&
            c.game.stage == Stage.hatched &&
            c.eggId == eggId) {
          context.go('/hatching');
        } else {
          _routing = false;
        }
      });
    }
  }

  /// 차 안에서 나왔다. 깨어나는 연출을 봤으면 그대로 광장(동행 카드), 못 봤으면 평소처럼 신호를 본다
  void _onExploreOpen() {
    if (exploreScreenOpen.value) {
      _sawExplore = true;
      return;
    }
    if (!_sawExplore) return;
    _sawExplore = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (exploreHatchShown) {
        _hatchShownEggId = widget.controller.eggId ?? '';
        setState(() {});
        return;
      }
      _onSignal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final g = c.game;
        final hatched = g.stage == Stage.hatched && c.hatched != null;
        return Scaffold(
          body: SafeArea(
            child: Row(children: [
              Expanded(
                  flex: 5,
                  child: hatched ? _companionCard(c) : _eggCard(c, g)),
              Expanded(flex: 4, child: _places(context, c)),
            ]),
          ),
        );
      },
    );
  }

  Widget _eggCard(GameController c, GameState g) {
    final remaining = g.stage == Stage.idle
        ? '남은 주행이 짧아 다음 알을 기다리고 있어요'
        : g.hatchAtSec != null
            ? '앞으로 ${((1 - g.progress) * g.hatchAtSec! / 60).ceil()}분'
            : '앞으로 ${((1 - g.progress) * (g.hatchAtM ?? 0) / 1000).toStringAsFixed(1)}km';
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          container: true,
          button: true,
          label: '자라고 있는 알, 돌봄 ${g.careCount}회',
          child: GestureDetector(
            onTap: c.care,
            child:
                Icon(Icons.egg, size: 120, color: Colors.amber.shade300),
          ),
        ),
        const SizedBox(height: 12),
        Text('알을 품는 중', style: Theme.of(context).textTheme.titleLarge),
        Text(remaining),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: LinearProgressIndicator(
              value: g.progress,
              minHeight: 10,
              semanticsLabel: '알 성장',
              semanticsValue: '${(g.progress * 100).round()}%'),
        ),
        const SizedBox(height: 6),
        Text('성장 ${(g.progress * 100).round()}% · 돌봄 ${g.careCount}회'),
      ]),
    );
  }

  Widget _companionCard(GameController c) {
    final s = c.hatched!;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Semantics(
          container: true,
          button: true,
          label: '${s.nameKo}, 놀이 ${c.playCount}회',
          child: GestureDetector(
            onTap: c.playWithCompanion,
            child: SpeciesArt(species: s, size: 140),
          ),
        ),
        const SizedBox(height: 12),
        Text(s.nameKo, style: Theme.of(context).textTheme.titleLarge),
        Text('${s.nameEn} · 같이 가는 중'),
        if (c.companionMessage != null) ...[
          const SizedBox(height: 8),
          Text(c.companionMessage!, textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  Widget _places(BuildContext context, GameController c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('광장',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: _openExplore,
                icon: const Icon(Icons.directions_car),
                label: const Text('차 안으로')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: () => context.push('/dex'),
                icon: const Icon(Icons.menu_book),
                label: const Text('도감')),
            const SizedBox(height: 10),
            if (c.isFake)
              TextButton(
                  onPressed: c.endFakeTrip, child: const Text('주행 종료'))
            else
              TextButton(
                  onPressed: () async {
                    final saved = await c.endSession();
                    if (saved && context.mounted) context.go('/pairing');
                  },
                  child: const Text('품기 저장하고 나가기')),
          ],
        ),
      );
}
