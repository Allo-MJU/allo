import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';

/// 동행. 생물이 차 기울기에 따라 기울고, 가끔 창밖을 가리킨다 ("저기 봐! 산이야" + 영어 단어 1개).
class CompanionScreen extends StatelessWidget {
  const CompanionScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.hatched;
        return Scaffold(
          appBar: AppBar(title: Text(s?.nameKo ?? '동행')),
          body: Column(
            children: [
              if (controller.error != null) Text(controller.error!),
              const Spacer(),
              // TODO(B): v.harshSteer 변화 → 기울기 애니메이션. 스프라이트 assets/species/{id}.png
              const Icon(Icons.pets, size: 140),
              const Spacer(),
              Card(
                margin: const EdgeInsets.all(16),
                child: ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('저기 봐! 산이야'),
                  subtitle: const Text('mountain'),
                  trailing: FilledButton(
                      onPressed: controller.lookOut, child: const Text('봤어!')),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FilledButton.tonal(onPressed: () {}, child: const Text('먹이')),
                  FilledButton.tonal(
                      onPressed: () {}, child: const Text('놀아주기')),
                  OutlinedButton(
                    onPressed: () async {
                      final saved = await controller.endSession();
                      if (saved && context.mounted) context.go('/dex');
                    },
                    child: const Text('도착'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
