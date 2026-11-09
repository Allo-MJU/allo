import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../widgets/species_art.dart';
import '../widgets/window_view.dart';

class CompanionScreen extends StatelessWidget {
  const CompanionScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final species = controller.hatched;
          final prompt = controller.lookOutPrompt;
          return Scaffold(
            appBar: AppBar(title: Text(species?.nameKo ?? '동행'), actions: [
              if (controller.isFake)
                TextButton(
                    onPressed: controller.endFakeTrip,
                    child: const Text('주행 종료')),
            ]),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (controller.error != null) Text(controller.error!),
                  const SizedBox(height: 12),
                  WindowView(
                    vehicle: controller.vehicle,
                    friends: controller.collectedSpecies,
                    // 가로 화면에서 버튼이 밀려나지 않게 화면 높이의 절반까지만 (가로 2단 개편 전 임시)
                    height:
                        math.min(300, MediaQuery.sizeOf(context).height * 0.5),
                    child: AnimatedRotation(
                      turns: controller.playCount.isOdd ? 0.04 : -0.04,
                      duration: const Duration(milliseconds: 300),
                      child: species == null
                          ? const Icon(Icons.pets, size: 120)
                          : SpeciesArt(species: species, size: 120),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    child: Text(controller.companionMessage ?? '도착할 때까지 함께 가요!',
                        textAlign: TextAlign.center),
                  ),
                  Text(
                      '먹이 ${controller.feedCount}회 · 놀이 ${controller.playCount}회',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.visibility),
                      title: Text(prompt.$1),
                      subtitle:
                          Text('${prompt.$2} · 발견 ${controller.lookOutCount}회'),
                      trailing: FilledButton(
                          onPressed: controller.lookOut,
                          child: const Text('봤어!')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                          onPressed: () => context.push('/explore'),
                          icon: const Icon(Icons.threed_rotation),
                          label: const Text('차 안 둘러보기')),
                      FilledButton.tonal(
                          onPressed: controller.feedCompanion,
                          child: const Text('먹이')),
                      FilledButton.tonal(
                          onPressed: controller.playWithCompanion,
                          child: const Text('놀아주기')),
                      OutlinedButton(
                        onPressed: () async {
                          final saved = await controller.endSession();
                          if (saved && context.mounted) context.go('/dex');
                        },
                        child: const Text('도착'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}
