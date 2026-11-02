import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';

/// 도감 한 화면. 그리드 + 빈칸. 상세엔 영어 이름·속성·등급·획득 날짜·날씨(태그).
class DexScreen extends StatelessWidget {
  const DexScreen({super.key, required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('도감'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/pairing')),
      ),
      body: FutureBuilder(
        future: Future.wait([controller.loadSpecies(), controller.dex.all()]),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final entries = snap.data![1] as List<DexEntry>;
          final owned = {for (final e in entries) e.speciesId: e};
          // TODO(B): SpeciesTable 을 controller 에서 노출해 12칸 그리드로. 지금은 획득분만.
          return GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(12),
            children: owned.values
                .map((e) => Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.pets, size: 40),
                          Text(e.speciesId),
                          Text('tier ${e.tier} · ${e.envTags.join(",")}', style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
