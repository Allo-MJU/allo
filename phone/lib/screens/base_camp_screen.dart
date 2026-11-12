import 'dart:convert';
import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../game/game_controller.dart';

/// Commands operate on the phone's durable camp; the car receives its summary.
class BaseCampScreen extends StatefulWidget {
  const BaseCampScreen({super.key, required this.controller});
  final GameController controller;
  @override
  State<BaseCampScreen> createState() => _BaseCampScreenState();
}

class _BaseCampScreenState extends State<BaseCampScreen> {
  Map<String, String> names = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/data/species.json'))
            as Map;
    if (!mounted) return;
    setState(() => names = {
          for (final s in data['species'] as List)
            s['id'] as String: s['nameKo'] as String
        });
    final camp = widget.controller.baseCamp;
    if (camp != null) {
      if (camp.ready) {
        await camp.refreshOwnership();
      } else {
        await camp.load();
      }
    }
  }

  static const roles = {
    CampRole.builder: '건설',
    CampRole.cook: '요리',
    CampRole.trainer: '훈련'
  };
  static const facilities = {
    CampFacility.workshop: '작업장',
    CampFacility.kitchen: '주방',
    CampFacility.training: '훈련장'
  };
  static const materials = {
    CampMaterial.wood: '나무',
    CampMaterial.stone: '돌',
    CampMaterial.ingredient: '식재료'
  };
  String errorText(String code) => switch (code) {
        'insufficient_materials' => '재료가 부족해요. 함께 여행하며 모아 주세요.',
        'missing_worker' => '먼저 건설 담당 친구를 배치해 주세요.',
        'role_busy' || 'creature_busy' => '진행 중인 작업이 끝나면 바꿀 수 있어요.',
        'facility_locked' => '작업장을 먼저 건설해 주세요.',
        _ => '거점 정보를 저장하지 못했어요. 잠시 후 다시 시도해 주세요.',
      };

  @override
  Widget build(BuildContext context) {
    final camp = widget.controller.baseCamp;
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '돌아가기',
              onPressed: () => context.go('/pairing')),
          title: const Text('우리 거점')),
      body: camp == null
          ? const Center(child: Text('거점을 준비하고 있어요.'))
          : ListenableBuilder(
              listenable: camp,
              builder: (context, _) {
                if (!camp.ready) {
                  return Center(
                      child: camp.error == null
                          ? const CircularProgressIndicator()
                          : FilledButton(
                              onPressed: camp.busy ? null : camp.load,
                              child: const Text('거점 다시 불러오기')));
                }
                final state = camp.state;
                return ListView(padding: const EdgeInsets.all(24), children: [
                  const Text('함께 모으고, 함께 만드는 집',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                      '관측된 주행 1km마다 나무·돌·식재료를 1개씩 모아요. 저장된 거점 요약은 연결된 차량에도 표시돼요.'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    for (final m in CampMaterial.values)
                      Chip(
                          label: Text(
                              '${materials[m]} ${state.materials[m] ?? 0}'))
                  ]),
                  if (camp.error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(errorText(camp.error!),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 16),
                  const Text('친구 배치',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  for (final role in CampRole.values)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: DropdownButtonFormField<String>(
                          initialValue: state.assignments[role] ?? '',
                          key: ValueKey(
                              '${role.name}:${state.assignments[role]}'),
                          isExpanded: true,
                          decoration: InputDecoration(
                              labelText: '${roles[role]} 담당',
                              border: const OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('배치하지 않음')),
                            for (final c in state.creatures.values.where((c) =>
                                CampCatalog.roleFor(c.speciesId) == role))
                              DropdownMenuItem(
                                  value: c.id,
                                  child:
                                      Text(names[c.speciesId] ?? c.speciesId))
                          ],
                          onChanged: camp.busy || state.jobs.containsKey(role)
                              ? null
                              : (value) =>
                                  camp.assign(role, value == '' ? null : value),
                        )),
                  const SizedBox(height: 16),
                  const Text('시설 건설',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (state.jobs.isNotEmpty)
                    const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('친구가 작업 중이에요. 완료되면 시설 정보가 자동으로 갱신돼요.')),
                  for (final facility in CampFacility.values)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${facilities[facility]} · Lv.${state.facilities[facility] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  if ((state.facilities[facility] ?? 0) <
                                      CampCatalog.maxLevel) ...[
                                    Text(
                                        '다음 단계: 나무 ${2 * ((state.facilities[facility] ?? 0) + 1)} · 돌 ${(state.facilities[facility] ?? 0) + 1}'),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                        onPressed: camp.busy ||
                                                state.jobs.containsKey(
                                                    CampRole.builder)
                                            ? null
                                            : () => camp.startBuild(facility),
                                        child:
                                            Text('${facilities[facility]} 건설')),
                                  ] else
                                    const Text('최고 레벨이에요.'),
                                ]))),
                ]);
              },
            ),
    );
  }
}
