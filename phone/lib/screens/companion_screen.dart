import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../widgets/character_stage.dart';

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
                  CharacterStage(controller: controller),
                  const SizedBox(height: 12),
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
