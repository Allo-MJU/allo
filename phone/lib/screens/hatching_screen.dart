import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';

/// 부화 연출. 시연 영상의 하이라이트 — 가장 공들일 곳.
/// 금 가기 → 빛 → 등장. 속성별 이펙트(water/dark/normal). 정차 중이면 차 화면과 동시 재생.
class HatchingScreen extends StatefulWidget {
  const HatchingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<HatchingScreen> createState() => _HatchingScreenState();
}

class _HatchingScreenState extends State<HatchingScreen> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(seconds: 3))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.hatched;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            final t = _anim.value;
            if (t < 0.6) {
              // TODO(D): 금 가기 3컷 + 빛 2컷 프레임 교체
              return Opacity(opacity: 1 - t, child: const Icon(Icons.egg, size: 160, color: Colors.amber));
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(opacity: (t - 0.6) / 0.4, child: const Icon(Icons.auto_awesome, size: 160, color: Colors.white)),
                const SizedBox(height: 16),
                Text(s?.nameKo ?? '', style: const TextStyle(color: Colors.white, fontSize: 28)),
                Text(s?.nameEn ?? '', style: const TextStyle(color: Colors.white70, fontSize: 18)),
                Text('${s?.attribute.name} · tier ${widget.controller.game.tier}', style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 32),
                FilledButton(onPressed: () => context.go('/companion'), child: const Text('같이 가자')),
              ],
            );
          },
        ),
      ),
    );
  }
}
