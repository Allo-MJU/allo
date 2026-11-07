import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:allo_core/allo_core.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../theme/allo_colors.dart';
import '../widgets/egg_art.dart';
import '../widgets/species_art.dart';

/// 폰의 부화 연출. 게임 판정과 저장은 컨트롤러가 담당한다.
class HatchingScreen extends StatefulWidget {
  const HatchingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<HatchingScreen> createState() => _HatchingScreenState();
}

class _HatchingScreenState extends State<HatchingScreen>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
      duration: AlloPresentation.hatchDuration);

  bool _reduceMotion = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_started) {
      _started = true;
      _anim.duration = _reduceMotion
          ? AlloPresentation.fadeDuration
          : AlloPresentation.hatchDuration;
      _anim.forward();
    } else if (_reduceMotion) {
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final species = c.hatched;
    final attribute = species?.attribute ?? Attribute.normal;
    const color = AlloColors.actionPrimary;
    final (label, icon) = switch (attribute) {
      Attribute.water => ('물', Icons.water_drop_rounded),
      Attribute.dark => ('어둠', Icons.star_rounded),
      Attribute.normal => ('일반', Icons.eco_rounded),
    };
    return Scaffold(
      backgroundColor: AlloColors.discoveryBackground,
      body: SafeArea(
          child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _reduceMotion ? 1.0 : _anim.value;
          final revealed = t >= .68;
          final reveal = ((t - .68) / .32).clamp(0.0, 1.0);
          final frame = t < .44
              ? (t / .44 * 3).floor().clamp(0, 2) + 1
              : t < .56
                  ? 4
                  : 5;
          return Opacity(
              opacity: _reduceMotion ? _anim.value : 1,
              child: LayoutBuilder(builder: (context, constraints) {
                final artSize = math.min(240.0, constraints.maxWidth - 64);
                return SingleChildScrollView(
                    child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 28),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(revealed ? '새 친구' : '알 안에서 소리가 나요',
                              style: TextStyle(
                                  color: AlloColors.textPrimary,
                                  fontSize: 16,
                                  letterSpacing: 1)),
                          const SizedBox(height: 16),
                          Semantics(
                              liveRegion: true,
                              child: Text(
                                  revealed
                                      ? '반가워!'
                                      : t < .44
                                          ? '조금씩 깨어나는 중'
                                          : '곧 만나요',
                                  style: const TextStyle(
                                      color: AlloColors.textPrimary,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700))),
                          const SizedBox(height: 24),
                          SizedBox(
                              width: artSize + 16,
                              height: artSize + 16,
                              child:
                                  Stack(alignment: Alignment.center, children: [
                                Container(
                                    width: artSize,
                                    height: artSize,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(colors: [
                                          color.withValues(alpha: .24),
                                          color.withValues(alpha: 0)
                                        ]))),
                                if (revealed)
                                  for (var i = 0; i < 8; i++)
                                    Transform.translate(
                                        offset: Offset(
                                            math.cos(i * math.pi / 4) *
                                                artSize *
                                                (.28 + .16 * reveal),
                                            math.sin(i * math.pi / 4) *
                                                artSize *
                                                (.28 + .16 * reveal)),
                                        child: ExcludeSemantics(
                                            child: Icon(icon,
                                                size: i.isEven ? 16 : 10,
                                                color: color.withValues(
                                                    alpha: .7 - .3 * reveal)))),
                                if (!revealed)
                                  Transform.rotate(
                                      angle: t < .44
                                          ? math.sin(t * math.pi * 28) * .06
                                          : 0,
                                      child: EggArt(
                                          tier: c.game.eggTier,
                                          progress: 1,
                                          hatchFrame: frame,
                                          color: color,
                                          size: artSize * .8))
                                else
                                  Transform.scale(
                                      scale: .8 +
                                          .2 *
                                              AlloPresentation.standardCurve
                                                  .transform(reveal),
                                      child: Opacity(
                                          opacity: reveal,
                                          child: species == null
                                              ? Icon(Icons.auto_awesome,
                                                  size: artSize * .6,
                                                  color: color)
                                              : SpeciesArt(
                                                  species: species,
                                                  size: artSize * .65))),
                              ])),
                          const SizedBox(height: 20),
                          if (revealed) ...[
                            Text(species?.nameKo ?? '새로운 친구',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AlloColors.textPrimary,
                                    fontSize: 36,
                                    height: 44 / 36,
                                    fontWeight: FontWeight.w800)),
                            if (species != null)
                              Text(species.nameEn,
                                  style: const TextStyle(
                                      color: AlloColors.textPrimary,
                                      fontSize: 16)),
                            const SizedBox(height: 12),
                            Text('$label 속성 · ${c.game.tier ?? 1}등급',
                                style: TextStyle(
                                    color: AlloColors.textPrimary,
                                    fontSize: 16)),
                            const SizedBox(height: 28),
                            FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AlloColors.actionPrimary,
                                    foregroundColor: AlloColors.textInverse,
                                    minimumSize: const Size(double.infinity,
                                        AlloPresentation.touchKid),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    textStyle: const TextStyle(
                                        fontFamily: AlloPresentation.fontFamily,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700)),
                                onPressed: () {
                                  if (c.sessionEnded) return;
                                  context.go(c.game.stage == Stage.hatched
                                      ? '/companion'
                                      : '/incubating');
                                },
                                child: const Text('친구 만나기')),
                          ] else
                            TextButton(
                                style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                        AlloPresentation.touchMin,
                                        AlloPresentation.touchMin)),
                                onPressed: () => _anim.value = 1,
                                child: const Text('건너뛰기',
                                    style: TextStyle(
                                        color: AlloColors.textPrimary))),
                        ]),
                  ),
                ));
              }));
        },
      )),
    );
  }
}
